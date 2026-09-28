//! The C ABI the Flutter app calls, and nothing else.
//!
//! This crate is the boundary. Everything worth testing lives in
//! `mobilelm-core` and `mobilelm-litert`; what is here is argument marshalling,
//! handle lifetime, and the error convention. That split is deliberate — a
//! `cargo test` on a laptop cannot load a 39 MB aarch64 runtime, so the tests
//! that matter have to be in the crates below this one, and this crate has to be
//! thin enough that its own logic is obviously correct by inspection.
//!
//! # The error convention
//!
//! Functions that return a string return `NULL` on failure and put the reason
//! where [`mobilelm_last_error`] reads it. Functions that return a number
//! return `-1`. Nothing panics across the boundary: a panic in `cdylib` code
//! unwinds into a runtime that does not know what to do with it, and the process
//! dies with no message on a phone. Every `extern "C"` entry point therefore
//! catches, records and returns.
//!
//! # Strings
//!
//! Every `char*` this library returns was allocated here and must be released
//! with [`mobilelm_string_free`]. Every `char*` it takes is borrowed for the
//! duration of the call, except where a function's docs say otherwise.
//!
//! # The stream callback
//!
//! [`mobilelm_send_stream`] **blocks**, and the callback fires on a LiteRT-owned
//! thread while it does. The `ctx` is an `int64` chosen by the caller, never a
//! pointer: an integer the caller can look up cannot dangle, and a pointer
//! handed back on a thread the caller does not control is exactly the
//! use-after-free the SD plugin's `Pointer.fromFunction` design invites. Dart
//! passes an id into a map and closes over nothing.

use std::cell::RefCell;
use std::ffi::{c_char, c_double, c_int, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use mobilelm_core::{json, Backend, Engine, EngineConfig, GenRequest};
use mobilelm_litert::{ConversationSpec, EngineExtras, LiteRt, Sampler};

/// A loaded engine, as Dart sees it: an opaque pointer.
pub struct Handle {
    engine: LiteRt,
    /// The path it was loaded from, kept so a later call can say which runtime
    /// answered — the log line that distinguishes "no NPU here" from "no runtime".
    runtime_path: String,
}

thread_local! {
    /// The reason the last failure happened. Thread-local because the FFI is
    /// called from a generation isolate and the UI isolate, and one must not read
    /// the other's error.
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_error(msg: impl Into<String>) {
    let msg = msg.into();
    LAST_ERROR.with(|slot| *slot.borrow_mut() = CString::new(msg).ok());
}

fn take_error() -> *mut c_char {
    LAST_ERROR.with(|slot| {
        slot.borrow_mut()
            .take()
            .map_or(ptr_null(), |c| c.into_raw())
    })
}

fn ptr_null() -> *mut c_char {
    std::ptr::null_mut()
}

/// Read a borrowed C string.
///
/// Errors are `String` because every caller sits inside [`guard`], whose error
/// type is `String`, and a `From<EngineError> for String` impl would be a lie
/// dressed as convenience: these are argument problems, not engine problems.
fn as_str<'a>(p: *const c_char) -> Result<&'a str, String> {
    if p.is_null() {
        return Ok("");
    }
    // SAFETY: a non-null `char*` from Dart is a valid NUL-terminated string for
    // the duration of the call; the C ABI has no other way to pass one.
    unsafe { CStr::from_ptr(p) }
        .to_str()
        .map_err(|_| "argument is not valid UTF-8".to_string())
}

/// Read an optional C string as an owned `String`, empty for `NULL`.
fn opt_str(p: *const c_char) -> Result<String, String> {
    as_str(p).map(str::to_string)
}

/// Run `f`, turning a panic into a recorded error rather than a dead process.
fn guard<T>(default: T, f: impl FnOnce() -> Result<T, String>) -> T {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => v,
        Ok(Err(e)) => {
            set_error(e);
            default
        }
        Err(_) => {
            set_error("the Rust core panicked; this is a bug, not a model error");
            default
        }
    }
}

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------

/// A C string literal with static storage: never freed, and never handed to
/// `mobilelm_string_free` — the Dart side special-cases it by pointer identity.
///
/// These are `c"…"` literals, not `&str`. A `&'static str`'s pointer points at
/// its *first byte*; Rust strings carry a length, not a terminator, so
/// `CStr::from_ptr` on one walks off the end into whatever follows in the
/// read-only segment. That is not a theoretical hazard: a test in this crate read
/// `0.4.0-ffi.1` followed by an unrelated error message from `Vec` internals. A
/// `c"…"` literal has the NUL inside the same static allocation, so what Dart
/// sees is a real C string.
/// The ABI revision, so a Dart build and a `.so` built from different commits
/// fail loudly instead of misinterpreting each other's arguments.
///
/// Bump the suffix on any change to a signature, a struct, or the meaning of a
/// return value. Adding a function does not need a bump; reordering arguments
/// very much does.
#[no_mangle]
pub extern "C" fn mobilelm_abi_version() -> *const c_char {
    c"0.4.0-ffi.1".as_ptr()
}

/// The optional C API symbols the given runtime does not have, as a JSON array.
///
/// Diagnostic, and the answer to "why is temperature not doing anything" on a
/// device whose runtime is not the one this build was tested against. Takes a
/// path because that is the only way to name a specific runtime; the app passes
/// the one in its `nativeLibraryDir`.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_symbols_missing(runtime_path: *const c_char) -> *mut c_char {
    guard(ptr_null(), || {
        let path = as_str(runtime_path)?;
        let lib = mobilelm_core::dynlib::Lib::open(path).map_err(|e| e.to_string())?;
        let missing = mobilelm_litert::ApiExt::load(&lib).missing();
        let joined: Vec<String> = missing.iter().map(|m| json::escape(m)).collect();
        CString::new(format!("[{}]", joined.join(",")))
            .map(|c| c.into_raw())
            .map_err(|_| "a symbol name contains a NUL byte".to_string())
    })
}

/// The reason the last call on this thread failed, or `NULL` if it did not.
#[no_mangle]
pub extern "C" fn mobilelm_last_error() -> *mut c_char {
    take_error()
}

/// Release a string this library returned.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    // Only strings from this library get here: every other `char*` in the ABI is
    // a `lit` literal or a Dart-owned allocation, and the Dart side never passes
    // those back here.
    drop(unsafe { CString::from_raw(s) });
}

// ---------------------------------------------------------------------------
// The probe and the ladder
// ---------------------------------------------------------------------------

/// What `/proc` and the vendor libraries say about this device, as JSON.
///
/// `npu_dir` is `/vendor/lib64` on most phones and `NULL` to skip that scan. The
/// scan is the cheap half of the NPU verdict; the expensive half is the linker
/// namespace, which no amount of reading `/vendor` can answer — this reports what
/// is on disk and lets the caller say what an app may link.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_probe(npu_dir: *const c_char) -> *mut c_char {
    guard(ptr_null(), || {
        let dir = as_str(npu_dir)?;
        let report = mobilelm_core::probe::DeviceReport::collect(
            &[],
            if dir.is_empty() { None } else { Some(dir) },
        );
        CString::new(report.to_json())
            .map(|c| c.into_raw())
            .map_err(|_| "probe output contains a NUL byte".to_string())
    })
}

/// The accelerator plan for a user's choice, as JSON.
///
/// This is the one place the ladder is decided, which is the point: the app had
/// `planLiteRtTier` in Dart and the core had `probe.rs` in Rust, and two
/// implementations of one rule is two answers waiting to disagree. `mode` is
/// what the settings screen passes (`cpu_safe`, or the GPU-fast mode);
/// `force_cpu` is the explicit CPU override. The result says which tier was
/// chosen *and* which one is actually reachable, because they are not always the
/// same and the app has to report the second.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_plan(
    mode: *const c_char,
    force_cpu: c_int,
    npu_available: c_int,
) -> *mut c_char {
    guard(ptr_null(), || {
        let mode = as_str(mode)?;
        let tier = mobilelm_core::plan::plan_litert_tier(mode, force_cpu != 0, npu_available != 0);
        CString::new(tier.to_json())
            .map(|c| c.into_raw())
            .map_err(|_| "plan output contains a NUL byte".to_string())
    })
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

/// Load a model and open a conversation.
///
/// Every `char*` argument is optional except the runtime and the model path, and
/// every one is named after the C API call it feeds, so there is no way to pair a
/// value with the wrong knob. `*_backend` of `NULL` means "this model has no such
/// encoder" — never "decide later": the engine is built without the encoder, and
/// sending it media then is a crash on a thread nothing is watching.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_engine_create(
    runtime_path: *const c_char,
    model_path: *const c_char,
    backend: *const c_char,
    n_ctx: c_int,
    n_threads: c_int,
    cache_dir: *const c_char,
    dispatch_dir: *const c_char,
    vision_backend: *const c_char,
    audio_backend: *const c_char,
    system_prompt: *const c_char,
) -> *mut c_void {
    guard(std::ptr::null_mut::<c_void>(), || {
        let backend_s = opt_str(backend)?;
        let cfg = EngineConfig {
            model_path: opt_str(model_path)?,
            mmproj_path: None,
            backend: Backend::parse(&backend_s).ok_or_else(|| {
                format!("unknown backend {backend_s:?}; expected cpu, gpu or npu")
            })?,
            n_ctx: (n_ctx > 0).then_some(n_ctx as u32),
            n_threads: (n_threads > 0).then_some(n_threads as u32),
        };
        let runtime = opt_str(runtime_path)?;
        let opt = |p: *const c_char| -> Option<Backend> {
            let raw = opt_str(p).ok()?;
            if raw.is_empty() {
                return None;
            }
            Backend::parse(&raw)
        };
        let dir =
            |p: *const c_char| -> Option<String> { opt_str(p).ok().filter(|d| !d.is_empty()) };
        let cache = dir(cache_dir);
        let dispatch = dir(dispatch_dir);
        let extras = EngineExtras {
            cache_dir: cache.as_deref(),
            dispatch_dir: dispatch.as_deref(),
            vision_backend: opt(vision_backend),
            audio_backend: opt(audio_backend),
        };
        let prompt_owned = opt_str(system_prompt)?;
        let prompt = (!prompt_owned.is_empty()).then_some(prompt_owned.as_str());
        let engine =
            LiteRt::load_with(&runtime, &cfg, &extras, prompt).map_err(|e| e.to_string())?;
        Ok(Box::into_raw(Box::new(Handle {
            engine,
            runtime_path: runtime,
        })) as *mut c_void)
    })
}

/// Free an engine and everything it holds. `NULL` is a no-op, so a double free
/// from a shutdown path that races a cancel is harmless.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_engine_free(h: *mut c_void) {
    if h.is_null() {
        return;
    }
    drop(unsafe { Box::from_raw(h as *mut Handle) });
}

/// The load report as JSON: the tier asked for, the tier that ran, why they
/// differ, the context, and any note worth a log line.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_engine_load_report(h: *mut c_void) -> *mut c_char {
    guard(ptr_null(), || {
        let handle = unsafe { handle_mut(h) }?;
        let r = handle.engine.load_report();
        let notes: Vec<String> = r.notes.iter().map(|n| json::escape(n)).collect();
        CString::new(format!(
            "{{\"runtime\":{},\"requested\":{},\"actual\":{},\"fallback_reason\":{},\
             \"load_ms\":{},\"model_bytes\":{},\"capabilities\":{},\"n_ctx\":{},\"notes\":[{}]}}",
            json::escape(&handle.runtime_path),
            json::escape(r.requested.as_str()),
            // The runtime does not report which accelerator it settled on, so
            // this is the requested one and the Dart side must present it as
            // such. The reason travels next to it.
            json::escape(r.actual.as_str()),
            r.fallback_reason
                .as_deref()
                .map_or("null".into(), json::escape),
            r.load_ms,
            r.model_bytes,
            r.capabilities,
            r.n_ctx,
            notes.join(","),
        ))
        .map(|c| c.into_raw())
        .map_err(|_| "load report contains a NUL byte".to_string())
    })
}

// ---------------------------------------------------------------------------
// Conversation
// ---------------------------------------------------------------------------

/// Open or replace the conversation. Any pointer may be `NULL` for "unchanged".
///
/// The sampler is fixed at creation, so a temperature change is a new
/// conversation; the app already recreates on exactly that condition, and this is
/// the call it makes. `history_json` is a JSON **array** of rendered messages,
/// `[]` meaning none — not a single message and not an empty string.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_conversation_open(
    h: *mut c_void,
    system_prompt: *const c_char,
    history_json: *const c_char,
    temperature: c_double,
    top_k: c_int,
    top_p: c_double,
    greedy: c_int,
    max_output_tokens: c_int,
) -> c_int {
    guard(-1i32, || {
        let handle = unsafe { handle_mut(h) }?;
        let prompt = as_str(system_prompt)?;
        let history_raw = as_str(history_json)?;
        let history: Vec<String> = if history_raw.trim().is_empty() {
            Vec::new()
        } else {
            split_message_array(history_raw)
                .ok_or_else(|| "history_json is not a JSON array of objects".to_string())?
        };
        let sampler = build_sampler(temperature, top_k, top_p, greedy != 0);
        let spec = ConversationSpec {
            system_prompt: if prompt.is_empty() {
                None
            } else {
                Some(prompt)
            },
            history: &history,
            sampler,
            max_output_tokens: (max_output_tokens > 0).then_some(max_output_tokens),
            visual_token_budget: None,
        };
        handle
            .engine
            .reopen_conversation(&spec)
            .map_err(|e| e.to_string())?;
        Ok(0)
    })
}

/// Split a flat JSON array of message objects into its elements.
///
/// The payloads are small — a conversation's history, tens of objects — and
/// pulled apart here rather than with a dependency. Returns `None` for anything
/// that is not a well-formed array of objects, because half a history is worse
/// than none: the model would answer as if the earlier turns never happened.
fn split_message_array(raw: &str) -> Option<Vec<String>> {
    let t = raw.trim();
    if !t.starts_with('[') || !t.ends_with(']') {
        return None;
    }
    let inner = &t[1..t.len() - 1];
    let mut out = Vec::new();
    let mut depth = 0usize;
    let mut in_string = false;
    let mut escaped = false;
    let mut start = 0usize;
    for (i, c) in inner.char_indices() {
        if in_string {
            if escaped {
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == '"' {
                in_string = false;
            }
            continue;
        }
        match c {
            '"' => in_string = true,
            '{' | '[' => depth += 1,
            '}' | ']' => depth = depth.checked_sub(1)?,
            ',' if depth == 0 => {
                out.push(inner[start..i].trim().to_string());
                start = i + 1;
            }
            _ => {}
        }
    }
    if in_string || depth != 0 {
        return None;
    }
    let tail = inner[start..].trim();
    if !tail.is_empty() {
        out.push(tail.to_string());
    }
    if out.iter().any(|m| !m.starts_with('{') || !m.ends_with('}')) {
        return None;
    }
    Some(out)
}

fn build_sampler(
    temperature: c_double,
    top_k: c_int,
    top_p: c_double,
    greedy: bool,
) -> Option<Sampler> {
    let temperature = if temperature > 0.0 {
        Some(temperature as f32)
    } else {
        None
    };
    let top_k = (top_k > 0).then_some(top_k);
    let top_p = (top_p > 0.0).then_some(top_p as f32);
    if temperature.is_none() && top_k.is_none() && top_p.is_none() && !greedy {
        return None;
    }
    Some(Sampler {
        temperature,
        top_k,
        top_p,
        greedy,
    })
}

// ---------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------

/// The stream callback Dart registers.
///
/// Called on a LiteRT-owned thread. Exactly one of `is_final` or a non-null `err`
/// ends the stream, and it is always the last call — the ABI contract the C API
/// itself makes about `is_final`, restated because a stream that silently loses
/// its tail is the failure this shape exists to prevent.
pub type MobilelmStreamCallback =
    extern "C" fn(ctx: i64, text: *const c_char, is_final: c_int, err: *const c_char);

/// Send one turn, blocking until it finishes, and return `0` or `-1`.
///
/// **Blocking** is deliberate. The C API's send is non-blocking and the engine
/// keeps calling back on its own thread, so a caller that returned immediately
/// would have to own the lifetime of its own callback context. Blocking makes the
/// answer the obvious one: the chunks arrive while this call is still on the
/// stack, and nothing outlives it. Dart runs it on a generation isolate.
///
/// `message_json` is a rendered message object — the app's multimodal turn
/// included — not a bare prompt, because the C API wants JSON and a bare string
/// is accepted as an empty turn. Building it in one place is the whole reason
/// `mobilelm_core::json` exists.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_send_stream(
    h: *mut c_void,
    message_json: *const c_char,
    max_tokens: c_int,
    cb: Option<extern "C" fn(i64, *const c_char, c_int, *const c_char)>,
    ctx: i64,
) -> c_int {
    guard(-1i32, || {
        let handle = unsafe { handle_mut(h) }?;
        let msg = as_str(message_json)?;
        let req = GenRequest {
            prompt: String::new(),
            max_tokens: max_tokens.max(0) as usize,
            stream: true,
        };
        // A callback pointer that is not a function is a caller bug with no way
        // to recover from; say so rather than dereferencing it.
        let cb = cb.ok_or("mobilelm_send_stream was given a null callback")?;
        let (final_sink, final_id) = (std::marker::PhantomData::<*const c_void>, 0);
        let _ = (final_sink, final_id);

        let mut on_token = |piece: &str| {
            // A NUL inside a chunk would truncate it. Text from a tokenizer
            // should not contain one, and if it does, a short token beats a
            // panic inside a foreign callback.
            let c = CString::new(piece).unwrap_or_default();
            cb(ctx, c.as_ptr(), 0, std::ptr::null());
        };
        let outcome = handle.engine.send_message_json(msg, &req, &mut on_token);
        match outcome {
            Ok(_) => {
                cb(ctx, std::ptr::null(), 1, std::ptr::null());
                Ok(0)
            }
            Err(e) => {
                // The engine's own message goes out on the stream *and* into the
                // thread-local last error, because the two reach different
                // readers and only one of them survives a failure.
                //
                // The Dart side throws when the return code is non-zero, building
                // its message from `lastError`. Returning `Ok(-1)` — which is what
                // this did — leaves the last error unset, so the throw produced
                // the generic "send_stream failed" and *preempted* the `_StreamEnd`
                // the callback had already queued with the real text in it. The
                // device said only "send_stream failed"; the reason was in a
                // message nobody read.
                set_error(e.to_string());
                let c = CString::new(e.to_string()).unwrap_or_default();
                cb(ctx, std::ptr::null(), 1, c.as_ptr());
                Ok(-1)
            }
        }
    })
}

/// One blocking turn with no streaming, returning the whole reply.
///
/// `NULL` on failure. For a smoke test and for the benchmark harness, not for
/// the app: the UI streams, and a path that is only used by tests is the path
/// that rots.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_send_text(h: *mut c_void, prompt: *const c_char) -> *mut c_char {
    guard(ptr_null(), || {
        let handle = unsafe { handle_mut(h) }?;
        let p = as_str(prompt)?;
        let reply = handle.engine.send_once(p).map_err(|e| e.to_string())?;
        CString::new(reply)
            .map(|c| c.into_raw())
            .map_err(|_| "reply contains a NUL byte".to_string())
    })
}

// ---------------------------------------------------------------------------
// Measurement
// ---------------------------------------------------------------------------

/// Tokens `text` would occupy, or `-1`. Zero is a real answer for empty input.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_count_tokens(h: *mut c_void, text: *const c_char) -> c_int {
    guard(-1i32, || {
        let handle = unsafe { handle_mut(h) }?;
        let t = as_str(text)?;
        let n = handle.engine.count_tokens(t).map_err(|e| e.to_string())?;
        c_int::try_from(n).map_err(|_| format!("{n} tokens does not fit in an int32"))
    })
}

/// The runtime's own timings for this conversation, as JSON, or `NULL` when the
/// runtime has no benchmark family or the switch was never thrown.
///
/// These are the engine's numbers, not wall time measured here. That is the
/// difference: the harness's own TTFT includes the JSON unwrap and the channel
/// hop, and quoting it as the engine's time would be measuring the plumbing.
///
/// # Safety
/// Every `char*` must be either null or a valid NUL-terminated UTF-8 string
/// that stays alive for the duration of the call. Null is never
/// dereferenced: it means "not supplied" everywhere in this ABI, so a caller
/// passing null gets the documented empty behaviour rather than a crash.
#[no_mangle]
pub unsafe extern "C" fn mobilelm_benchmark(h: *mut c_void) -> *mut c_char {
    guard(ptr_null(), || {
        let handle = unsafe { handle_mut(h) }?;
        let b = handle
            .engine
            .benchmark()
            .ok_or("this runtime has no benchmark API, or no turn has run")?;
        CString::new(format!(
            "{{\"ttft_ms\":{},\"prefill_tokens\":{},\"decode_tokens\":{},\
             \"prefill_tps\":{},\"decode_tps\":{}}}",
            b.ttft_ms, b.prefill_tokens, b.decode_tokens, b.prefill_tps, b.decode_tps
        ))
        .map(|c| c.into_raw())
        .map_err(|_| "benchmark contains a NUL byte".to_string())
    })
}

// ---------------------------------------------------------------------------

unsafe fn handle_mut<'a>(h: *mut c_void) -> Result<&'a mut Handle, String> {
    if h.is_null() {
        return Err("engine handle is null".into());
    }
    Ok(unsafe { &mut *(h as *mut Handle) })
}

#[cfg(test)]
mod tests;
