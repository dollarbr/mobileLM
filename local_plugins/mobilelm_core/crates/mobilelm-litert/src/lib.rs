//! LiteRT-LM through its C API, as a [`mobilelm_core::Engine`].
//!
//! This is the crate that makes the Rust core worth having. The AAR the Flutter
//! app uses today (`liblitertlm_jni.so`) exports JNI symbols only, so a Dart app
//! can reach the engine *only* through a Kotlin plugin. The C API is plain C, so
//! `dart:ffi` can call it directly and the Kotlin layer disappears.
//!
//! Three things in here are easy to get wrong, and each is commented where it
//! lives:
//!
//! - The runtime is **loaded, not linked** (see [`ffi`]). A missing 39 MB
//!   aarch64 library is an error value, not a failed process start.
//! - `send_message_stream` is **non-blocking**: it returns a status while chunks
//!   keep arriving on an engine-owned thread. Waiting for the terminal chunk is
//!   ours, and it has to be a channel rather than a sleep.
//! - Every handle is freed. The C API has no RAII, and a leaked engine on a
//!   phone is a leaked model in RAM.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{mpsc, Mutex};
use std::time::{Duration, Instant};

use mobilelm_core::dynlib::Lib;
use mobilelm_core::{
    json, Backend, Engine, EngineConfig, EngineError, GenOutcome, GenRequest, LoadReport,
    SamplerChoice,
};

mod ffi;
pub use ffi::*;

/// A loaded LiteRT-LM engine with one open conversation.
#[derive(Debug)]
pub struct LiteRt {
    api: ffi::Api,
    /// The optional half of the surface. Resolved best-effort, so a runtime that
    /// lacks a capability reports it instead of failing to load.
    ext: ffi::ApiExt,
    /// Kept alive for as long as `api`, which points into it. Declared after
    /// `api` so it outlives it on drop.
    _lib: Lib,
    engine: *mut LiteRtLmEngine,
    conversation: *mut LiteRtLmConversation,
    report: LoadReport,
    system_prompt: Option<String>,
    /// Which sampler type the open conversation is actually sampling with.
    ///
    /// Not a `notes` entry. The decision happens when the conversation is
    /// replaced, which is after the load report has already been read by the app,
    /// and it changes — a conversation opened with a different temperature can
    /// land on a different type. So it is current state, readable at any time,
    /// and it is what `mobilelm_sampler_report` returns.
    sampler: SamplerChoice,
}

// Pointers are only touched from the thread that created the engine, which is
// the same contract as the C++ engine: Send, not Sync.
unsafe impl Send for LiteRt {}

/// The engine-settings knobs that are not part of [`EngineConfig`].
///
/// Separate because they are all optional and all default to "off", and because
/// grouping them keeps `load`'s signature from growing a `bool` per turn of the
/// screw. Each field maps to exactly one `litert_lm_engine_settings_set_*` call.
#[derive(Debug, Clone, Default)]
pub struct EngineExtras<'a> {
    /// Where compiled graphs are cached. The app passes its own temp dir so a
    /// cleared cache actually frees the disk.
    pub cache_dir: Option<&'a str>,
    /// Directory holding a `libLiteRtDispatch_*.so`, for the NPU. On this phone
    /// it is a dead end -- see `docs/BENCH.md` "Arm E" -- so this stays `None`
    /// unless a device actually exposes one, and what the runtime does about it
    /// is reported rather than assumed.
    pub dispatch_dir: Option<&'a str>,
    /// Which backend runs the **vision encoder**. `None` means the model has no
    /// vision encoder built, and sending it an image is a crash rather than an
    /// error: the encoder is never constructed and the first frame dereferences
    /// it. The Flutter path learned this the hard way; see the comment on
    /// `audioBackend` in `inference_android.dart`.
    pub vision_backend: Option<Backend>,
    /// Same, for the audio encoder. The app ties audio to vision because the
    /// multimodal `.litertlm` files it loads carry both in one file and there is
    /// no separate flag to key off.
    pub audio_backend: Option<Backend>,
}

/// Sampling parameters.
///
/// A conversation's sampler is fixed when the conversation is created, so
/// changing the temperature means recreating it. The app already does exactly
/// that (`_ensureLiteRtConversation` compares the temperature), which is why
/// this is a conversation setting and not a per-turn one.
#[derive(Debug, Clone, Copy, Default)]
pub struct Sampler {
    pub temperature: Option<f32>,
    pub top_k: Option<i32>,
    pub top_p: Option<f32>,
    /// `kLiteRtLmSamplerTypeGreedy`. Set this to pin sampling, which is what a
    /// deterministic benchmark needs and what an image-generation prompt wants.
    pub greedy: bool,
}

/// Everything that describes a conversation, so one can be opened or replaced.
///
/// The app rebuilds a conversation when the system prompt changes, when the
/// temperature changes, or when it has sent messages and the caller shows up
/// with no history. All three are inputs here, and recreating is one call.
#[derive(Debug, Clone, Default)]
pub struct ConversationSpec<'a> {
    pub system_prompt: Option<&'a str>,
    /// Pre-rendered message objects, oldest first. Empty is legal and means "no
    /// history", which the app sends after a clear.
    pub history: &'a [String],
    pub sampler: Option<Sampler>,
    pub max_output_tokens: Option<i32>,
    /// Caps how many tokens the vision encoder may spend. `None` uses the
    /// engine's own default.
    pub visual_token_budget: Option<i32>,
}

/// Timings the C API actually measured, once benchmarking is switched on.
///
/// `docs/BENCH.md` recorded prefill as "not measured - the C API reports no
/// prompt timing". That was wrong: `litert_lm_conversation_get_benchmark_info`
/// exposes it, gated behind `litert_lm_engine_settings_enable_benchmark`. The
/// switch was simply never turned on.
#[derive(Debug, Clone, Copy, Default)]
pub struct Bench {
    pub ttft_ms: f64,
    pub prefill_tokens: i32,
    pub decode_tokens: i32,
    pub prefill_tps: f64,
    pub decode_tps: f64,
}

/// Bound on waiting for a final chunk. Not a limit on generation time -- a 0.6B
/// model on a phone takes seconds. It only trips when the producer died without
/// ever sending a terminal event, which is already a failure.
const STREAM_WATCHDOG: Duration = Duration::from_secs(600);

impl LiteRt {
    /// Load a `.litertlm` model from `runtime_path` and open a conversation.
    ///
    /// `runtime_path` is the `liblitert-lm.so` to dlopen. In an app this lives in
    /// the APK's `nativeLibraryDir`; from `adb shell` it is wherever it was
    /// pushed, with `LD_LIBRARY_PATH` set so the loader finds it.
    pub fn load(
        runtime_path: &str,
        cfg: &EngineConfig,
        system_prompt: Option<&str>,
    ) -> Result<Self, EngineError> {
        Self::load_with(runtime_path, cfg, &EngineExtras::default(), system_prompt)
    }

    /// [`LiteRt::load`] plus the encoder backends, cache dir and NPU dispatch
    /// dir. Benchmarking is switched on here, which is what makes [`Bench`]
    /// non-empty.
    pub fn load_with(
        runtime_path: &str,
        cfg: &EngineConfig,
        extras: &EngineExtras<'_>,
        system_prompt: Option<&str>,
    ) -> Result<Self, EngineError> {
        let lib = Lib::open(runtime_path).map_err(|why| {
            EngineError::BackendUnavailable {
                backend: cfg.backend,
                // Keep the loader's wording: "not found" and "forbidden by the
                // linker namespace" are different bugs with different fixes.
                reason: format!("cannot dlopen {runtime_path}: {why}"),
            }
        })?;
        let api = ffi::Api::load(&lib).map_err(|why| EngineError::BackendUnavailable {
            backend: cfg.backend,
            reason: format!("{runtime_path} is not a LiteRT-LM C API build: {why}"),
        })?;
        let ext = ffi::ApiExt::load(&lib);
        let mut notes = Vec::new();
        let missing = ext.missing();
        if !missing.is_empty() {
            // Not fatal. Text generation works without any of them; say so
            // rather than refusing a model the user can otherwise run.
            notes.push(format!(
                "runtime lacks {} optional C API symbol(s): {}",
                missing.len(),
                missing.join(", ")
            ));
        }

        let model = cstring(&cfg.model_path)?;
        let backend = cstring(backend_str(cfg.backend))?;
        // NULL rather than "": an empty string names a backend, and an unknown
        // name is handled differently from "not specified". This is the
        // distinction that decides whether a missing encoder is a segfault or an
        // error, so it is the reason the encoder backends are plumbed at all.
        let null = ptr::null();
        let vision = extras
            .vision_backend
            .map(|b| cstring(backend_str(b)))
            .transpose()?;
        let audio = extras
            .audio_backend
            .map(|b| cstring(backend_str(b)))
            .transpose()?;
        let vision_ptr = vision
            .as_ref()
            .map_or(null, |c| c.as_ptr() as *const c_char);
        let audio_ptr = audio.as_ref().map_or(null, |c| c.as_ptr() as *const c_char);

        let settings = unsafe {
            (api.litert_lm_engine_settings_create)(
                model.as_ptr(),
                backend.as_ptr(),
                vision_ptr,
                audio_ptr,
            )
        };
        if settings.is_null() {
            return Err(EngineError::Model(format!(
                "engine settings rejected {} (backend {})",
                cfg.model_path, cfg.backend
            )));
        }

        // Order matters: max_num_tokens is the context ceiling, and LiteRT-LM
        // clamps to 4096 in its own driver regardless of what is asked.
        unsafe {
            if let Some(n) = cfg.n_ctx {
                (api.litert_lm_engine_settings_set_max_num_tokens)(settings, n as i32);
                if n > 4096 {
                    notes.push(format!(
                        "n_ctx {n} requested; the LiteRT-LM driver caps this at 4096"
                    ));
                }
            }
            if let Some(t) = cfg.n_threads {
                (api.litert_lm_engine_settings_set_num_threads)(settings, t as i32);
            }
            if let Some(dir) = extras.cache_dir {
                let c = cstring(dir)?;
                (api.litert_lm_engine_settings_set_cache_dir)(settings, c.as_ptr());
            }
            if let Some(dir) = extras.dispatch_dir {
                let c = cstring(dir)?;
                (api.litert_lm_engine_settings_set_litert_dispatch_lib_dir)(settings, c.as_ptr());
                notes.push(format!(
                    "NPU dispatch dir set to {dir}; the runtime decides if it works"
                ));
            }
        }

        // The runtime's own measurement is OFF, and that is a measured decision
        // rather than a missing feature.
        //
        // Turning it on (`litert_lm_engine_settings_enable_benchmark`) was, until
        // the device run, in this load. It broke generation on the Edge 60:
        //
        //   [LiteRt] beginTurn turn=1 messageBytes=94 maxTokens=2048
        //   W native: tasks.cc:490] Failed to get prefill profile summary:
        //   INVALID_ARGUMENT [litert_profiler.h:91]
        //   ERROR: ... Error: mobilelm_core: send_stream failed
        //
        // The load succeeded, the conversation opened, the message was accepted
        // (41 tokens in the context counter), and then the send failed ~3 s in with
        // no token ever produced — while the profiler complained about exactly the
        // profile the flag asked for. The Kotlin plugin never enables it, and the
        // Kotlin path generates fine on the same runtime and the same model.
        //
        // So the instrumentation was killing the thing it was instrumenting. The
        // prefill number is worth having and this flag is the only source of it,
        // but it is not worth a turn that does not complete, and it is not worth
        // being on by default in a shipped path where nobody would connect the two.
        // `benchmark()` returns `None` with the flag off, which is the honest
        // answer rather than a zero pretending to be a measurement.
        if let Some(f) = ext.litert_lm_engine_settings_enable_benchmark {
            let _ = f;
            notes.push("benchmarking off: it breaks generation on this runtime".into());
        }

        let engine = unsafe { (api.litert_lm_engine_create)(settings) };
        if engine.is_null() {
            // The settings are ours either way; a failed load is exactly when a
            // leak goes unnoticed until the user has tried six models.
            unsafe { (api.litert_lm_engine_settings_delete)(settings) };
            return Err(EngineError::Model(format!(
                "engine failed to load {} -- the file exists but the runtime rejected it \
                 (wrong variant for this backend, or not a .litertlm at all)",
                cfg.model_path
            )));
        }

        let conversation = unsafe { open_conversation(&api, engine, system_prompt)? };

        Ok(Self {
            api,
            ext,
            _lib: lib,
            engine,
            conversation,
            report: LoadReport {
                requested: cfg.backend,
                // LiteRT-LM does not report which backend it settled on, so this
                // says only what was asked for. Anything stronger would be a
                // guess in the one struct whose job is to avoid guesses; the
                // engine's own stderr and log level are where the truth is.
                actual: cfg.backend,
                fallback_reason: None,
                load_ms: 0,
                model_bytes: std::fs::metadata(&cfg.model_path)
                    .map(|m| m.len())
                    .unwrap_or(0),
                capabilities: 0,
                n_ctx: cfg.n_ctx.unwrap_or(4096),
                notes,
            },
            system_prompt: system_prompt.map(str::to_string),
            // No conversation has asked for a sampler yet, so nothing is in force
            // but the engine's own default. Distinct from "asked for one and did
            // not get it", which is what the app will be told later.
            sampler: SamplerChoice {
                requested: "engine default",
                actual: None,
                full: false,
            },
        })
    }

    /// The system prompt this conversation was opened with, if any.
    pub fn system_prompt(&self) -> Option<&str> {
        self.system_prompt.as_deref()
    }

    /// Which sampler type the open conversation is sampling with, and what it
    /// took to find out.
    pub fn sampler(&self) -> &SamplerChoice {
        &self.sampler
    }

    /// One-shot, non-streaming generation. Used to prove the path before anything
    /// depends on the streaming behaviour.
    pub fn send_once(&mut self, prompt: &str) -> Result<String, EngineError> {
        let msg = cstring(&json::message("user", prompt))?;
        let resp = unsafe {
            (self.api.litert_lm_conversation_send_message)(
                self.conversation,
                msg.as_ptr(),
                ptr::null(),
                ptr::null(),
            )
        };
        if resp.is_null() {
            return Err(EngineError::Runtime("send_message returned NULL".into()));
        }
        unsafe {
            let raw = (self.api.litert_lm_json_response_get_string)(resp);
            let out = if raw.is_null() {
                String::new()
            } else {
                CStr::from_ptr(raw).to_string_lossy().into_owned()
            };
            (self.api.litert_lm_json_response_delete)(resp);
            Ok(out)
        }
    }

    /// Replace the open conversation.
    ///
    /// The C API fixes a conversation's sampler at creation time, so a
    /// temperature change is a new conversation. The old one is deleted first,
    /// which is what makes this safe to call before every turn.
    ///
    /// `optional` is built from `spec` and handed to each send; it is
    /// per-turn state, unlike the sampler, so it does not force a rebuild.
    pub fn reopen_conversation(&mut self, spec: &ConversationSpec<'_>) -> Result<(), EngineError> {
        if let Some(set_session) = self.ext.litert_lm_conversation_config_set_session_config {
            if let Some(s) = spec.sampler {
                let (params, choice) = sampler_params(&self.ext, s)?;
                // Recorded before the params are attached, and on every path —
                // including the ones that end up with no sampler at all. A
                // degradation only written down where it cannot be observed is
                // not a degradation, it is a surprise.
                self.sampler = choice;
                if let Some(params) = params {
                    let session = unsafe { self.ext.litert_lm_session_config_create.unwrap()() };
                    if session.is_null() {
                        return Err(EngineError::Runtime("session config is NULL".into()));
                    }
                    unsafe {
                        (self
                            .ext
                            .litert_lm_session_config_set_sampler_params
                            .unwrap())(session, params);
                    }
                    // The config copies the sampler, so the params are ours to free
                    // as soon as it is built. Leaking them would leak on every
                    // conversation recreate, and the app recreates on every
                    // temperature change.
                    unsafe { (self.ext.litert_lm_sampler_params_delete.unwrap())(params) };
                    let config = unsafe { (self.api.litert_lm_conversation_config_create)() };
                    if config.is_null() {
                        unsafe { (self.ext.litert_lm_session_config_delete.unwrap())(session) };
                        return Err(EngineError::Runtime("conversation config is NULL".into()));
                    }
                    unsafe {
                        set_session(config, session);
                        (self.ext.litert_lm_session_config_delete.unwrap())(session);
                    }
                    let conversation = self.finish_conversation(config, spec)?;
                    self.swap_conversation(conversation);
                    return Ok(());
                }
            }
        } else if let Some(s) = spec.sampler {
            // No sampler API at all, which is the same situation as a runtime that
            // implements no type and gets the same answer. Routed through `sampler`
            // so one place decides what was asked for and what is in force.
            self.sampler = SamplerChoice {
                requested: if s.greedy { "greedy" } else { "top_k" },
                actual: None,
                full: false,
            };
        }

        let config = unsafe { (self.api.litert_lm_conversation_config_create)() };
        if config.is_null() {
            return Err(EngineError::Runtime("conversation config is NULL".into()));
        }
        let conversation = self.finish_conversation(config, spec)?;
        self.swap_conversation(conversation);
        Ok(())
    }

    /// Apply the system prompt, history and turn limits to a fresh config, then
    /// create the conversation. The config is always deleted, on every path.
    fn finish_conversation(
        &mut self,
        config: *mut ffi::LiteRtLmConversationConfig,
        spec: &ConversationSpec<'_>,
    ) -> Result<*mut ffi::LiteRtLmConversation, EngineError> {
        if let Some(p) = spec.system_prompt {
            let as_json = cstring(&json::message("system", p))?;
            unsafe {
                (self.api.litert_lm_conversation_config_set_system_message)(
                    config,
                    as_json.as_ptr(),
                )
            };
        }
        if !spec.history.is_empty() {
            let arr = cstring(&json::messages_array(spec.history))?;
            if let Some(f) = self.ext.litert_lm_conversation_config_set_messages {
                unsafe { f(config, arr.as_ptr()) };
            } else {
                self.report
                    .notes
                    .push("history ignored: set_messages absent from this runtime".into());
            }
        }
        let conversation = unsafe { (self.api.litert_lm_conversation_create)(self.engine, config) };
        unsafe { (self.api.litert_lm_conversation_config_delete)(config) };
        if conversation.is_null() {
            return Err(EngineError::Runtime(
                "conversation_create returned NULL".into(),
            ));
        }
        Ok(conversation)
    }

    fn swap_conversation(&mut self, conversation: *mut ffi::LiteRtLmConversation) {
        unsafe {
            if !self.conversation.is_null() {
                (self.api.litert_lm_conversation_delete)(self.conversation);
            }
            self.conversation = conversation;
        }
    }

    /// Stream one turn of arbitrary content — text, or text plus an image and
    /// an audio file.
    ///
    /// The parts are rendered with `json::parts_message`, whose field names are
    /// pinned against the C++ that reads them. The alternative, a bare string
    /// message, silently drops media: the runtime ignores a part whose key it
    /// does not recognise and answers from the text alone.
    pub fn send_parts(
        &mut self,
        parts: &[json::Content],
        req: &GenRequest,
        on_token: &mut dyn FnMut(&str),
    ) -> Result<GenOutcome, EngineError> {
        let msg = json::parts_message("user", parts);
        self.stream(&msg, req, on_token)
    }

    /// Stream one turn of an already-rendered message.
    ///
    /// This is what the FFI boundary calls. Rendering happens on the Dart side of
    /// the boundary in that arrangement, so there is exactly one place that knows
    /// the engine's JSON dialect and it is [`json`], reachable from both sides.
    ///
    /// **Blocks** until the terminal chunk, the watchdog, or an error. The caller
    /// is expected to be a worker: the C callback fires on an engine-owned thread
    /// and `on_token` runs on this one, as chunks arrive.
    pub fn send_message_json(
        &mut self,
        message_json: &str,
        req: &GenRequest,
        on_token: &mut dyn FnMut(&str),
    ) -> Result<GenOutcome, EngineError> {
        self.stream(message_json, req, on_token)
    }

    /// Tokens `text` would occupy, via the engine's own tokenizer.
    ///
    /// The plugin's `countTokens` used the AAR's tokenizer; this is the C API's.
    /// They should agree, and if they do not the smaller number is the one that
    /// fits the context.
    pub fn count_tokens(&mut self, text: &str) -> Result<usize, EngineError> {
        let (Some(tokenize), Some(count)) = (
            self.ext.litert_lm_engine_tokenize,
            self.ext.litert_lm_tokenize_result_get_num_tokens,
        ) else {
            return Err(EngineError::NotImplemented("engine_tokenize"));
        };
        let c = cstring(text)?;
        let result = unsafe { tokenize(self.engine, c.as_ptr()) };
        if result.is_null() {
            return Err(EngineError::Runtime("engine_tokenize returned NULL".into()));
        }
        let n = unsafe { count(result) };
        if let Some(delete) = self.ext.litert_lm_tokenize_result_delete {
            unsafe { delete(result) };
        }
        Ok(n)
    }

    /// What the runtime itself measured for the turns so far.
    ///
    /// `None` when the switch was never thrown, or when the runtime has no
    /// benchmark family. The numbers are the engine's, not derived from wall
    /// time here, which is why they are worth having: the harness's own TTFT
    /// includes the JSON unwrap and the channel hop.
    pub fn benchmark(&mut self) -> Option<Bench> {
        let get = self.ext.litert_lm_conversation_get_benchmark_info?;
        if self.conversation.is_null() {
            return None;
        }
        let info = unsafe { get(self.conversation) };
        if info.is_null() {
            return None;
        }
        // Turn index 0: the first turn of this conversation. A per-turn read
        // would need an index the app does not track, and for a single-turn
        // measurement -- which is what the matrix records -- 0 is the turn.
        let at = |f: Option<
            unsafe extern "C" fn(*const ffi::LiteRtLmBenchmarkInfo, c_int) -> i32,
        >| { f.map(|f| unsafe { f(info, 0) }).unwrap_or(0) };
        let rate = |f: Option<
            unsafe extern "C" fn(*const ffi::LiteRtLmBenchmarkInfo, c_int) -> f64,
        >| { f.map(|f| unsafe { f(info, 0) }).unwrap_or(0.0) };
        let bench = Bench {
            ttft_ms: self
                .ext
                .litert_lm_benchmark_info_get_time_to_first_token
                .map(|f| unsafe { f(info) })
                .unwrap_or(0.0),
            prefill_tokens: at(self.ext.litert_lm_benchmark_info_get_prefill_token_count_at),
            decode_tokens: at(self.ext.litert_lm_benchmark_info_get_decode_token_count_at),
            prefill_tps: rate(
                self.ext
                    .litert_lm_benchmark_info_get_prefill_tokens_per_sec_at,
            ),
            decode_tps: rate(
                self.ext
                    .litert_lm_benchmark_info_get_decode_tokens_per_sec_at,
            ),
        };
        if let Some(delete) = self.ext.litert_lm_benchmark_info_delete {
            unsafe { delete(info) };
        }
        Some(bench)
    }
}

/// Sampler types, from `engine.h:127-138`. A C enum crosses the boundary as an
/// int, and a runtime is not obliged to implement every one of them.
const SAMPLER_TOP_K: c_int = 1;
const SAMPLER_TOP_P: c_int = 2;
const SAMPLER_GREEDY: c_int = 3;

/// The name a type has in `engine.h`, for a message a person will read.
fn sampler_name(kind: c_int) -> &'static str {
    match kind {
        SAMPLER_TOP_K => "top_k",
        SAMPLER_TOP_P => "top_p",
        SAMPLER_GREEDY => "greedy",
        _ => "unknown",
    }
}

/// The sampler types to try, in order, for a request that is or is not greedy.
///
/// Split out of [`sampler_params`] so the selection policy is testable without a
/// runtime. Only the `create` call itself is device-only; *which* types are
/// attempted, and in what order, is a decision, and a decision is worth a test.
///
/// The order is not arbitrary. Greedy never falls back to a sampling type, because
/// "greedy" means argmax and substituting random-ish sampling for it would change
/// what the user asked for rather than how precisely it is honoured. A non-greedy
/// request does fall back — TopK, TopP, Greedy — because all three are still
/// constrained sampling, and the engine's own default is narrower than any of them.
fn sampler_attempts(greedy: bool) -> Vec<c_int> {
    if greedy {
        vec![SAMPLER_GREEDY]
    } else {
        vec![SAMPLER_TOP_K, SAMPLER_TOP_P, SAMPLER_GREEDY]
    }
}

/// Build sampler params for whatever type this runtime actually implements.
///
/// **The type is probed, never assumed, and no outcome of the probe can fail a
/// turn.** Both halves are there because the device said so:
///
/// ```text
/// runtime: UNIMPLEMENTED: Sampler type: 1 not implemented yet.
/// ```
///
/// That is the v0.16.0 runtime refusing `kLiteRtLmSamplerTypeTopK` — the type
/// the app's own plugin requests (topK 64, topP 0.95, temperature from the
/// slider) — after the conversation was created and the turn was already under
/// way. Passing TopK unconditionally meant a preference, a cosmetic setting on a
/// slider, took the whole turn down with it.
fn sampler_params(
    ext: &ffi::ApiExt,
    s: Sampler,
) -> Result<(Option<*mut ffi::LiteRtLmSamplerParams>, SamplerChoice), EngineError> {
    let wanted = if s.greedy {
        SAMPLER_GREEDY
    } else {
        SAMPLER_TOP_K
    };
    let requested = sampler_name(wanted);

    let Some(create) = ext.litert_lm_sampler_params_create else {
        // A runtime with no sampler API at all is the same situation as one that
        // implements no type, and gets the same answer.
        return Ok((
            None,
            SamplerChoice {
                requested,
                actual: None,
                full: false,
            },
        ));
    };

    for kind in sampler_attempts(s.greedy) {
        let params = unsafe { create(kind) };
        if params.is_null() {
            continue;
        }
        unsafe {
            if let (Some(f), Some(v)) =
                (ext.litert_lm_sampler_params_set_temperature, s.temperature)
            {
                f(params, v);
            }
            if let (Some(f), Some(v)) = (ext.litert_lm_sampler_params_set_top_k, s.top_k) {
                f(params, v);
            }
            if let (Some(f), Some(v)) = (ext.litert_lm_sampler_params_set_top_p, s.top_p) {
                f(params, v);
            }
        }
        return Ok((
            Some(params),
            SamplerChoice {
                requested,
                actual: Some(sampler_name(kind)),
                full: kind == wanted,
            },
        ));
    }

    Ok((
        None,
        SamplerChoice {
            requested,
            actual: None,
            full: false,
        },
    ))
}

impl Engine for LiteRt {
    fn backend(&self) -> Backend {
        self.report.actual
    }

    fn load_report(&self) -> &LoadReport {
        &self.report
    }

    fn sampler_choice(&self) -> Option<&SamplerChoice> {
        Some(&self.sampler)
    }

    fn generate(
        &mut self,
        req: &GenRequest,
        on_token: &mut dyn FnMut(&str),
    ) -> Result<GenOutcome, EngineError> {
        let msg = json::message("user", &req.prompt);
        self.stream(&msg, req, on_token)
    }

    fn unload(&mut self) {
        unsafe {
            if !self.conversation.is_null() {
                (self.api.litert_lm_conversation_delete)(self.conversation);
                self.conversation = ptr::null_mut();
            }
            if !self.engine.is_null() {
                (self.api.litert_lm_engine_delete)(self.engine);
                self.engine = ptr::null_mut();
            }
        }
    }
}

impl LiteRt {
    /// Send one already-rendered message and drive the stream to its terminal
    /// chunk. Shared by [`Engine::generate`] and [`LiteRt::send_parts`] so there
    /// is one watchdog, one unwind of the JSON envelope, and one place that
    /// knows the send is non-blocking.
    fn stream(
        &mut self,
        message_json: &str,
        req: &GenRequest,
        on_token: &mut dyn FnMut(&str),
    ) -> Result<GenOutcome, EngineError> {
        let started = Instant::now();
        let msg = cstring(message_json)?;

        // The C callback runs on an engine-owned thread and cannot touch the
        // caller's `&mut dyn FnMut`, so an mpsc channel is the seam: the callback
        // sends, this thread receives and drives the UI. std only.
        let (tx, rx) = mpsc::channel::<Ev>();
        let sink = Box::new(Sink {
            // The callback gets a `void*` and nothing else, so it needs its own
            // copy of the pointer table to read a chunk.
            api: self.api,
            tx: Mutex::new(Some(tx)),
            chunks: AtomicU32::new(0),
            first_token_ms: Mutex::new(None),
            started: Mutex::new(Some(started)),
        });
        // Owned by the callback until the terminal event; see the watchdog below.
        let raw = Box::into_raw(sink);

        let status = unsafe {
            (self.api.litert_lm_conversation_send_message_stream)(
                self.conversation,
                msg.as_ptr(),
                ptr::null(),
                ptr::null(),
                chunk_trampoline,
                raw.cast::<c_void>(),
            )
        };

        // Drain until the terminal event, delivering tokens as they arrive.
        let deadline = started + STREAM_WATCHDOG;
        let mut collected = String::new();
        let mut failure: Option<String> = None;
        loop {
            let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
                failure = Some("stream watchdog expired".into());
                break;
            };
            match rx.recv_timeout(remaining) {
                Ok(Ev::Chunk(piece)) => {
                    collected.push_str(&piece);
                    if req.stream {
                        on_token(&piece);
                    }
                }
                Ok(Ev::Final) => break,
                Ok(Ev::Error(e)) => {
                    failure = Some(e);
                    break;
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    // The producer may still fire into `raw`, so the Sink is
                    // deliberately leaked rather than freed under it. One leaked
                    // sink per hung stream is the price of not risking a
                    // use-after-free; the alternative is a crash in a debuggable
                    // build, which is worse on a phone.
                    return Err(EngineError::Runtime(format!(
                        "no final chunk within {STREAM_WATCHDOG:?}; the call returned status \
                         {status}, so the engine accepted the request and then went quiet"
                    )));
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    failure = Some("stream closed without a final chunk".into());
                    break;
                }
            }
        }

        // Safe now: a terminal event arrived, so the callback is done with it.
        let sink = unsafe { Box::from_raw(raw) };
        if let Some(e) = failure {
            return Err(EngineError::Runtime(e));
        }
        if !req.stream && !collected.is_empty() {
            on_token(&collected);
        }

        let total_ms = started.elapsed().as_millis() as u64;
        let first_ms = sink
            .first_token_ms
            .lock()
            .ok()
            .and_then(|f| *f)
            .unwrap_or(total_ms);
        Ok(GenOutcome {
            ttft_ms: first_ms,
            // The C API's benchmark struct only fills in after a whole run, so
            // for a single turn the honest token count is the chunk count, which
            // is a lower bound: one chunk can carry several tokens.
            prefill_tokens: 0,
            decode_tokens: sink.chunks.load(Ordering::Relaxed),
            total_ms,
        })
    }
}

impl Drop for LiteRt {
    fn drop(&mut self) {
        self.unload();
    }
}

/// What the callback sends back to the calling thread.
enum Ev {
    Chunk(String),
    /// The producer is done. The only event after which the `Sink` may be freed.
    Final,
    Error(String),
}

/// The C entry point handed to `send_message_stream`.
///
/// It cannot capture anything -- it is `extern "C"` -- so everything it needs
/// arrives through `callback_data`, which is our [`Sink`].
extern "C" fn chunk_trampoline(data: *mut c_void, chunk: *const LiteRtLmStreamChunk) {
    if data.is_null() || chunk.is_null() {
        return;
    }
    // SAFETY: `data` is the Box::into_raw pointer from the caller, which keeps it
    // alive until the terminal event is seen.
    let sink = unsafe { &*(data as *const Sink) };
    let api = sink.api;

    let err = unsafe { (api.litert_lm_stream_chunk_get_error)(chunk) };
    if !err.is_null() {
        let msg = unsafe { CStr::from_ptr(err) }
            .to_string_lossy()
            .into_owned();
        sink.send(Ev::Error(msg));
        return;
    }
    let text = unsafe { (api.litert_lm_stream_chunk_get_text)(chunk) };
    if !text.is_null() {
        let piece = unsafe { CStr::from_ptr(text) }.to_string_lossy();
        // The header calls this "the text content of the chunk". On the runtime
        // we ship it is the serialised message, one envelope per token -- so the
        // name lies and the raw bytes are not the token. Verified on an Edge 60:
        // 215 chunks, every one of them `{"role":"assistant","content":[{"type":"text",
        // "text":"..."}]}`. Unwrap it here rather than making every consumer
        // learn the C API's JSON dialect.
        //
        // A failed extraction forwards the envelope unchanged. Losing a token
        // would be worse than showing the user a line of JSON, and the shape
        // makes the mistake obvious if it ever happens.
        let piece = match json::extract_content_text(&piece) {
            Some(text) => text,
            None => piece.into_owned(),
        };
        // An envelope can carry several text parts that concatenate to nothing
        // visible; counting it as a token anyway keeps the throughput figure
        // honest about what the engine did.
        sink.note_token();
        sink.send(Ev::Chunk(piece));
    }
    if unsafe { (api.litert_lm_stream_chunk_is_final)(chunk) } {
        sink.send(Ev::Final);
    }
}

/// The callback's view of the world. Touched from an engine-owned thread, so
/// every field is `Send`.
struct Sink {
    api: ffi::Api,
    /// `Option` so the owning thread can drop its own sender without reaching
    /// into the callback's copy.
    tx: Mutex<Option<mpsc::Sender<Ev>>>,
    chunks: AtomicU32,
    first_token_ms: Mutex<Option<u64>>,
    started: Mutex<Option<Instant>>,
}

impl Sink {
    fn send(&self, ev: Ev) {
        if let Ok(guard) = self.tx.lock() {
            if let Some(tx) = guard.as_ref() {
                // A send failure means the receiver is gone, i.e. the caller
                // already gave up. Nothing useful to do about it from here.
                let _ = tx.send(ev);
            }
        }
    }

    fn note_token(&self) {
        self.chunks.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut f) = self.first_token_ms.lock() {
            if f.is_none() {
                if let Ok(s) = self.started.lock() {
                    *f = s.map(|t| t.elapsed().as_millis() as u64);
                }
            }
        }
    }
}

fn cstring(s: &str) -> Result<CString, EngineError> {
    CString::new(s).map_err(|_| EngineError::Model("string contains a NUL byte".into()))
}

/// Open a conversation, applying an optional system prompt.
///
/// The config is copied by `conversation_create`, so it is freed on both paths
/// here -- which is why the delete sits after the null check rather than inside
/// a success arm.
unsafe fn open_conversation(
    api: &ffi::Api,
    engine: *mut LiteRtLmEngine,
    system_prompt: Option<&str>,
) -> Result<*mut LiteRtLmConversation, EngineError> {
    let config = unsafe { (api.litert_lm_conversation_config_create)() };
    if config.is_null() {
        return Err(EngineError::Runtime("conversation config is NULL".into()));
    }
    if let Some(p) = system_prompt {
        let as_json = cstring(&json::message("system", p))?;
        unsafe { (api.litert_lm_conversation_config_set_system_message)(config, as_json.as_ptr()) };
    }
    let conversation = unsafe { (api.litert_lm_conversation_create)(engine, config) };
    unsafe { (api.litert_lm_conversation_config_delete)(config) };
    if conversation.is_null() {
        return Err(EngineError::Runtime(
            "conversation_create returned NULL".into(),
        ));
    }
    Ok(conversation)
}

fn backend_str(b: Backend) -> &'static str {
    match b {
        // LiteRT-LM spells them "cpu" and "gpu"; the OpenCL/OpenGL choice is
        // internal to the GPU backend, which is why GpuVulkan has no separate
        // spelling and falls back to gpu.
        Backend::Cpu => "cpu",
        Backend::Gpu | Backend::GpuVulkan => "gpu",
        Backend::Npu => "npu",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_names_match_what_the_runtime_expects() {
        // A wrong spelling does not error: it selects a different, slower path.
        assert_eq!(backend_str(Backend::Cpu), "cpu");
        assert_eq!(backend_str(Backend::Gpu), "gpu");
    }

    #[test]
    fn a_runtime_without_the_sampler_api_gets_the_engine_default_instead_of_an_error() {
        // An empty table is a runtime with none of the optional symbols. This used
        // to be an `Err(NotImplemented)`, and the four device runs before this one
        // all ended in that shape: a turn that produced nothing because a slider
        // had a value. The engine's default is a working sampler, so the honest
        // answer is "nothing was applied", reported — not a failed turn.
        let ext = ffi::ApiExt::load(Lib::open("libc.so.6").as_ref().unwrap());
        let (params, choice) = sampler_params(
            &ext,
            Sampler {
                temperature: Some(0.7),
                top_k: Some(64),
                top_p: Some(0.95),
                greedy: false,
            },
        )
        .expect("a missing sampler API must not fail the turn");
        assert!(params.is_none());
        assert_eq!(choice.requested, "top_k");
        assert_eq!(choice.actual, None);
        assert!(
            !choice.full,
            "nothing was applied, so nothing is fully honoured"
        );
    }

    #[test]
    fn the_requested_type_is_tried_first_and_there_is_a_next_one() {
        // The device failure was `Sampler type: 1 not implemented yet`, and 1 is
        // top_k — the type the app asks for on every turn. If top_k were not
        // followed by a second attempt, probing would be pointless: it would find
        // the same refusal every time and have nothing to fall back to.
        let order = sampler_attempts(false);
        assert_eq!(
            order.first(),
            Some(&SAMPLER_TOP_K),
            "the app's own type has to be the one asked for first"
        );
        assert!(
            order.len() > 1,
            "a refusal of the first type must leave somewhere to go: {order:?}"
        );
    }

    #[test]
    fn greedy_does_not_fall_back_to_a_sampling_type() {
        // Substituting top-k for greedy would not honour the request more
        // precisely, it would change it: argmax and constrained sampling are
        // different answers to the same question. So greedy tries greedy and
        // stops, and the engine's own default applies if that is refused too.
        assert_eq!(sampler_attempts(true), vec![SAMPLER_GREEDY]);
    }

    #[test]
    fn sampler_names_match_the_header() {
        // engine.h:127-138 -- TopK 1, TopP 2, Greedy 3. These names go in a log a
        // person reads, and a name that does not match the header sends them to
        // the wrong line of it.
        assert_eq!(sampler_name(SAMPLER_TOP_K), "top_k");
        assert_eq!(sampler_name(SAMPLER_TOP_P), "top_p");
        assert_eq!(sampler_name(SAMPLER_GREEDY), "greedy");
        assert_eq!(sampler_name(0), "unknown");
    }

    #[test]
    fn a_substituted_sampler_says_which_knobs_it_ignores() {
        // `greedy` sampling with a temperature of 0.8 and one of 0.2 produce the
        // same reply, so "sampler: greedy" alone would read as a setting that is
        // being applied. The note has to name the substitution.
        let substituted = SamplerChoice {
            requested: "top_k",
            actual: Some("greedy"),
            full: false,
        };
        let note = substituted.describe();
        assert!(note.contains("substituted for top_k"), "{note}");
        // Not "contains no 'every knob'": the substituted wording reads "not every
        // knob it set is consulted", which does contain that phrase. What has to be
        // absent is the claim that every knob is in force.
        assert!(!note.contains("consults every knob the app set"), "{note}");

        let full = SamplerChoice {
            requested: "top_k",
            actual: Some("top_k"),
            full: true,
        };
        assert!(
            full.describe().contains("consults every knob the app set"),
            "{}",
            full.describe()
        );

        let none = SamplerChoice {
            requested: "top_k",
            actual: None,
            full: false,
        };
        assert!(
            none.describe().contains("engine default"),
            "{}",
            none.describe()
        );
    }

    #[test]
    fn the_conversation_api_takes_json_not_plain_text() {
        // The single most likely integration mistake: a bare string where a JSON
        // message is expected is accepted as an empty turn.
        let m = json::message("user", "hi");
        assert!(m.starts_with('{') && m.ends_with('}'));
        assert!(m.contains("\"role\":\"user\""));
    }

    #[test]
    fn a_missing_runtime_is_a_backend_error_not_a_crash() {
        // The reason the runtime is dlopened rather than linked: this test runs
        // on a machine with no LiteRT-LM at all.
        let cfg = EngineConfig {
            model_path: "/nope.litertlm".into(),
            mmproj_path: None,
            backend: Backend::Cpu,
            n_ctx: Some(4096),
            n_threads: Some(4),
        };
        match LiteRt::load("/nope/liblitert-lm.so", &cfg, None) {
            Err(EngineError::BackendUnavailable { reason, .. }) => {
                assert!(reason.contains("dlopen"), "{reason}");
            }
            other => panic!("expected BackendUnavailable, got {other:?}"),
        }
    }
}
