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

use std::ffi::{c_void, CStr, CString};
use std::ptr;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{mpsc, Mutex};
use std::time::{Duration, Instant};

use mobilelm_core::dynlib::Lib;
use mobilelm_core::{
    json, Backend, Engine, EngineConfig, EngineError, GenOutcome, GenRequest, LoadReport,
};

mod ffi;
pub use ffi::*;

/// A loaded LiteRT-LM engine with one open conversation.
#[derive(Debug)]
pub struct LiteRt {
    api: ffi::Api,
    /// Kept alive for as long as `api`, which points into it. Declared after
    /// `api` so it outlives it on drop.
    _lib: Lib,
    engine: *mut LiteRtLmEngine,
    conversation: *mut LiteRtLmConversation,
    report: LoadReport,
    system_prompt: Option<String>,
}

// Pointers are only touched from the thread that created the engine, which is
// the same contract as the C++ engine: Send, not Sync.
unsafe impl Send for LiteRt {}

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

        let model = cstring(&cfg.model_path)?;
        let backend = cstring(backend_str(cfg.backend))?;
        // NULL rather than "": an empty string names a backend, and an unknown
        // name is handled differently from "not specified".
        let null = ptr::null();

        let mut notes = Vec::new();
        let settings = unsafe {
            (api.litert_lm_engine_settings_create)(model.as_ptr(), backend.as_ptr(), null, null)
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
        })
    }

    /// The system prompt this conversation was opened with, if any.
    pub fn system_prompt(&self) -> Option<&str> {
        self.system_prompt.as_deref()
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
}

impl Engine for LiteRt {
    fn backend(&self) -> Backend {
        self.report.actual
    }

    fn load_report(&self) -> &LoadReport {
        &self.report
    }

    fn generate(
        &mut self,
        req: &GenRequest,
        on_token: &mut dyn FnMut(&str),
    ) -> Result<GenOutcome, EngineError> {
        let started = Instant::now();
        let msg = cstring(&json::message("user", &req.prompt))?;

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
        // The header calls this "the text content of the chunk". On 0.17.1 it
        // is the serialised message, one envelope per token -- so the name lies
        // and the raw bytes are not the token. Verified on an Edge 60: 215 chunks,
        // every one of them `{"role":"assistant","content":[{"type":"text",
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
