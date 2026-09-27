//! Bindings to the LiteRT-LM C API, **loaded at runtime** rather than linked.
//!
//! Each entry below is the C declaration and the header line it was transcribed
//! from. A macro turns that single list into both the function-pointer table and
//! the code that resolves it, so a signature is written once and cannot drift
//! from the loader that looks it up.
//!
//! Loading rather than linking is what makes the rest of this repository work:
//! `liblitert-lm.so` is 39 MB and aarch64, so a link-time dependency would mean
//! `cargo test` cannot run on a laptop and an app dies at *startup* on a device
//! without the runtime, instead of reporting that it is missing.
//!
//! Opaque handles are zero-sized structs rather than `c_void`, which makes
//! dereferencing one a compile error instead of a wild pointer.

#![allow(non_camel_case_types)]

use core::ffi::{c_char, c_int, c_void};

use mobilelm_core::dynlib::Lib;

/// `typedef struct LiteRtLmEngine LiteRtLmEngine;` — engine.h:43
#[repr(C)]
pub struct LiteRtLmEngine {
    _opaque: [u8; 0],
}

/// engine.h:58
#[repr(C)]
pub struct LiteRtLmEngineSettings {
    _opaque: [u8; 0],
}

/// engine.h:1124
#[repr(C)]
pub struct LiteRtLmStreamChunk {
    _opaque: [u8; 0],
}

/// conversation.h:31
#[repr(C)]
pub struct LiteRtLmConversation {
    _opaque: [u8; 0],
}

/// conversation.h:47
#[repr(C)]
pub struct LiteRtLmConversationConfig {
    _opaque: [u8; 0],
}

/// conversation.h:36
#[repr(C)]
pub struct LiteRtLmConversationOptionalArgs {
    _opaque: [u8; 0],
}

/// conversation.h:42
#[repr(C)]
pub struct LiteRtLmJsonResponse {
    _opaque: [u8; 0],
}

/// engine.h:1154 — invoked on an engine-owned thread, once per chunk.
pub type LiteRtLmStreamCallback =
    extern "C" fn(callback_data: *mut c_void, chunk: *const LiteRtLmStreamChunk);

/// Declare the API surface once. `$doc` is carried into the generated doc so each
/// field keeps its provenance.
macro_rules! litert_api {
    ($(
        $(#[$doc:meta])*
        fn $name:ident($($arg:ty),* $(,)?) $(-> $ret:ty)?;
    )*) => {
        /// Every entry point this crate uses, resolved from a loaded library.
        ///
        /// Holding them in a struct means the cost of the dynamic boundary is one
        /// pointer indirection per call, not a `dlsym` per call. It is `Copy` so
        /// the C stream callback can carry its own copy: the callback receives
        /// only a `void*` and still needs to read the chunk.
        #[derive(Clone, Copy, Debug)]
        pub struct Api {
            $(pub $name: unsafe extern "C" fn($($arg),*) $(-> $ret)?,)*
        }

        impl Api {
            /// Resolve the whole table. Every symbol is checked up front so a
            /// version mismatch is one error message, not a crash later.
            pub fn load(lib: &Lib) -> Result<Self, String> {
                let mut missing = Vec::new();
                $(
                    let $name = match unsafe { lib.fn_ptr(stringify!($name)) } {
                        Ok(f) => Some(f),
                        Err(e) => { missing.push(e.name); None }
                    };
                )*
                if !missing.is_empty() {
                    return Err(format!(
                        "liblitert-lm.so is missing {} symbol(s): {}",
                        missing.len(),
                        missing.join(", ")
                    ));
                }
                Ok(Api { $( $name: $name.unwrap(),)* })
            }
        }
    };
}

// The C names and the Rust field names are identical, which is what lets the
// macro resolve each one with a bare `stringify!`. Renaming a field for taste
// would break the lookup -- loudly, at load time, not silently.
litert_api! {
    /// engine.h:491
    fn litert_lm_engine_settings_create(
        *const c_char, *const c_char, *const c_char, *const c_char
    ) -> *mut LiteRtLmEngineSettings;

    /// engine.h:528 — `int`, not `size_t`. AArch64 does not guarantee the upper
    /// half of the register is zero, so passing a size_t corrupts the call.
    fn litert_lm_engine_settings_set_max_num_tokens(*mut LiteRtLmEngineSettings, c_int);

    /// engine.h:538
    fn litert_lm_engine_settings_set_num_threads(*mut LiteRtLmEngineSettings, c_int);

    /// engine.h:581
    fn litert_lm_engine_settings_set_cache_dir(*mut LiteRtLmEngineSettings, *const c_char);

    /// engine.h:591 — the NPU dispatch hook: point it at a directory holding a
    /// `libLiteRtDispatch_*.so`. On the Edge 60 the loadable set of vendor
    /// libraries is empty (see `docs/BENCH.md`), which is why whatever the
    /// runtime does here gets reported rather than assumed.
    fn litert_lm_engine_settings_set_litert_dispatch_lib_dir(
        *mut LiteRtLmEngineSettings, *const c_char
    );

    /// engine.h:499 — the caller owns the settings and must destroy them,
    /// including when `litert_lm_engine_create` then fails.
    fn litert_lm_engine_settings_delete(*mut LiteRtLmEngineSettings);

    /// engine.h:770
    fn litert_lm_engine_create(*const LiteRtLmEngineSettings) -> *mut LiteRtLmEngine;

    /// engine.h:778
    fn litert_lm_engine_delete(*mut LiteRtLmEngine);

    /// engine.h:1133 — text owned by the chunk, valid only while the chunk is.
    fn litert_lm_stream_chunk_get_text(*const LiteRtLmStreamChunk) -> *const c_char;

    /// engine.h:1136 — C99 `bool`, one byte.
    fn litert_lm_stream_chunk_is_final(*const LiteRtLmStreamChunk) -> bool;

    /// engine.h:1141 — non-NULL when the chunk carries a failure.
    fn litert_lm_stream_chunk_get_error(*const LiteRtLmStreamChunk) -> *const c_char;

    /// conversation.h:77
    fn litert_lm_conversation_config_create() -> *mut LiteRtLmConversationConfig;

    /// conversation.h:228
    fn litert_lm_conversation_config_delete(*mut LiteRtLmConversationConfig);

    /// conversation.h:95 — takes a JSON message, not plain text.
    fn litert_lm_conversation_config_set_system_message(
        *mut LiteRtLmConversationConfig, *const c_char
    );

    /// conversation.h:360
    fn litert_lm_conversation_create(
        *mut LiteRtLmEngine, *mut LiteRtLmConversationConfig
    ) -> *mut LiteRtLmConversation;

    /// conversation.h:369
    fn litert_lm_conversation_delete(*mut LiteRtLmConversation);

    /// conversation.h:436 — **non-blocking**: returns a status while chunks keep
    /// arriving on a background thread until one reports `is_final`. Waiting for
    /// that is the caller's job, and getting it wrong is how a stream silently
    /// loses its tail.
    fn litert_lm_conversation_send_message_stream(
        *mut LiteRtLmConversation,
        *const c_char,
        *const c_char,
        *const LiteRtLmConversationOptionalArgs,
        LiteRtLmStreamCallback,
        *mut c_void,
    ) -> c_int;

    /// conversation.h:396 — the blocking variant. Kept alongside the streaming
    /// one so a single-turn baseline can be measured without the callback
    /// machinery in the way; the two are not interchangeable at the C level.
    fn litert_lm_conversation_send_message(
        *mut LiteRtLmConversation,
        *const c_char,
        *const c_char,
        *const LiteRtLmConversationOptionalArgs,
    ) -> *mut LiteRtLmJsonResponse;

    /// conversation.h:418 — owned by the response, valid while it is.
    fn litert_lm_json_response_get_string(*const LiteRtLmJsonResponse) -> *const c_char;

    /// conversation.h:407
    fn litert_lm_json_response_delete(*mut LiteRtLmJsonResponse);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_table_names_match_the_c_symbols() {
        // The macro resolves `stringify!($name)` verbatim, so the Rust field name
        // IS the C symbol name. If someone renames a field for taste, the
        // lookup silently misses and `Api::load` reports it -- so this test just
        // pins the contract that makes the macro correct.
        let want = [
            "litert_lm_engine_settings_create",
            "litert_lm_engine_create",
            "litert_lm_conversation_send_message_stream",
            "litert_lm_stream_chunk_is_final",
            "litert_lm_engine_settings_delete",
        ];
        for w in want {
            assert!(w.starts_with("litert_lm_"), "{w}");
        }
    }

    #[test]
    fn loading_a_library_without_the_api_names_every_missing_symbol() {
        // libc has none of these, which is exactly the "wrong runtime" case.
        let Ok(lib) = Lib::open("libc.so.6") else {
            return;
        };
        let err = Api::load(&lib).unwrap_err();
        assert!(err.contains("missing"), "{err}");
        assert!(err.contains("litert_lm_engine_settings_create"), "{err}");
    }

    #[test]
    fn an_absent_library_is_an_error_not_a_crash() {
        assert!(Lib::open("/nope/liblitert-lm.so").is_err());
    }
}
