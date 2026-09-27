//! Host tests for the FFI layer.
//!
//! None of these load a model: `liblitert-lm.so` is 39 MB and aarch64, which is
//! exactly why it is `dlopen`ed and why the engine cannot be exercised on a
//! laptop. What *can* be tested here is the part that is easy to get wrong and
//! silent when it is — the JSON array splitter, the error convention, the null
//! handling, and the sampler coercion. The engine behaviour lives in
//! `mobilelm-litert`'s tests and on the device.
//!
//! The ABI is called from `unsafe` blocks throughout, which is what its own
//! signature demands. The alternative — a module-level `allow` — would hide a
//! genuinely bad pointer in one of the tests, and the pointers here are the
//! interesting part of several of them.

use super::*;

#[test]
fn a_message_array_splits_into_its_elements() {
    let raw = r#"[{"role":"system","content":"a"},{"role":"user","content":"b"}]"#;
    let got = split_message_array(raw).expect("a well-formed array");
    assert_eq!(got.len(), 2);
    assert_eq!(got[0], r#"{"role":"system","content":"a"}"#);
    assert_eq!(got[1], r#"{"role":"user","content":"b"}"#);
}

#[test]
fn an_empty_array_is_no_history_not_an_error() {
    // The app sends this after a clear. It has to be accepted, because refusing
    // it would make "new conversation" the one thing that cannot be done.
    assert_eq!(split_message_array("[]"), Some(vec![]));
    assert_eq!(split_message_array("  [ ]  "), Some(vec![]));
    assert_eq!(
        split_message_array(""),
        None,
        "an empty string is not an array"
    );
}

#[test]
fn a_comma_inside_a_string_is_not_a_separator() {
    // The whole reason this is hand-written: a naive `split(',')` tears a message
    // in half, and half a message is a turn the model never saw.
    let raw = r#"[{"role":"user","content":"a, b, c"},{"role":"assistant","content":"d, e"}]"#;
    let got = split_message_array(raw).expect("commas inside strings");
    assert_eq!(got.len(), 2);
    assert!(got[0].contains("a, b, c"), "{}", got[0]);
    assert!(got[1].contains("d, e"), "{}", got[1]);
}

#[test]
fn a_brace_inside_a_string_does_not_confuse_the_depth_count() {
    let raw = r#"[{"role":"user","content":"{\"a\":1}"},{"role":"user","content":"x"}]"#;
    let got = split_message_array(raw).expect("braces inside a string");
    assert_eq!(got.len(), 2, "{got:?}");
    assert!(got[1].contains("\"x\""), "{}", got[1]);
}

#[test]
fn an_escaped_quote_does_not_end_the_string_early() {
    let raw = r#"[{"role":"user","content":"say \"hi\""},{"role":"user","content":"y"}]"#;
    let got = split_message_array(raw).expect("escaped quote");
    assert_eq!(got.len(), 2, "{got:?}");
}

#[test]
fn half_an_array_is_refused_rather_than_truncated() {
    // Truncating the history would leave the model answering as if the earlier
    // turns never happened, which is indistinguishable from a memory bug. Every
    // one of these has to be `None`.
    for bad in [
        r#"[{"role":"user","content":"a"}"#,
        r#"{"role":"user"}"#,
        r#"[{"role":"user","content":"unterminated}]"#,
        r#"[[1,2],[3,4]]"#,
        r#"[1,2]"#,
    ] {
        assert_eq!(split_message_array(bad), None, "should refuse: {bad}");
    }
}

#[test]
fn a_null_argument_means_absent_not_empty() {
    // `as_str` is safe precisely because it checks for null before dereferencing,
    // which is the whole claim this test makes.
    assert_eq!(as_str(std::ptr::null()).unwrap(), "");
    assert_eq!(as_str(c"cpu".as_ptr()).unwrap(), "cpu");
}

#[test]
fn a_sampler_is_only_built_when_something_was_asked_for() {
    // All-zero means "leave the engine's own default alone". Building a sampler
    // anyway would pin top_k to a value nobody chose, which on a model with a
    // small vocab is how a model that should be free becomes repetitive.
    assert!(build_sampler(0.0, 0, 0.0, false).is_none());
    let s = build_sampler(0.7, 64, 0.95, false).expect("three values set");
    assert_eq!(s.temperature, Some(0.7));
    assert_eq!(s.top_k, Some(64));
    assert!(s.top_p.unwrap() > 0.94 && s.top_p.unwrap() < 0.96);
    // Greedy alone is a request too.
    let g = build_sampler(0.0, 0, 0.0, true).expect("greedy alone");
    assert!(g.greedy);
    assert_eq!(g.temperature, None);
}

#[test]
fn a_null_handle_is_an_error_not_a_crash() {
    // Every entry point takes a handle from the caller, and a shutdown path that
    // races a cancel can hand over a null one. Dereferencing it would be the
    // difference between a logged error and a dead app.
    let e = match unsafe { handle_mut(std::ptr::null_mut()) } {
        Err(e) => e,
        Ok(_) => panic!("a null handle must not be accepted"),
    };
    assert!(e.contains("null"), "{e}");
    // And freeing nothing is allowed, so a double free is harmless.
    unsafe { mobilelm_engine_free(std::ptr::null_mut()) };
}

#[test]
fn the_abi_version_is_a_literal_that_must_not_be_freed() {
    let p = mobilelm_abi_version();
    // SAFETY: `mobilelm_abi_version` returns a static string, never an owned one.
    let s = unsafe { CStr::from_ptr(p) }.to_str().unwrap();
    assert_eq!(s, "0.4.0-ffi.1");
    // A second call must return the same pointer: it is a literal, and Dart
    // special-cases it by identity rather than calling mobilelm_string_free.
    assert_eq!(p, mobilelm_abi_version());
}

#[test]
fn a_failing_call_records_a_reason_and_returns_null() {
    let p = unsafe { mobilelm_symbols_missing(c"/definitely/not/here.so".as_ptr()) };
    assert!(
        p.is_null(),
        "a missing runtime must fail, not invent a list"
    );
    let err = mobilelm_last_error();
    assert!(!err.is_null(), "the reason must be retrievable");
    // SAFETY: `mobilelm_last_error` returns an owned CString we just took.
    let text = unsafe { CStr::from_ptr(err) }
        .to_string_lossy()
        .into_owned();
    unsafe { mobilelm_string_free(err) };
    assert!(
        text.contains("here.so"),
        "the reason must name what failed to open: {text}"
    );
    // Taking the error clears it, so a later success does not inherit it.
    assert!(mobilelm_last_error().is_null());
}

#[test]
fn libc_has_none_of_the_optional_symbols_and_saying_so_succeeds() {
    // The positive path: a real library that lacks all 26. Not an error — the
    // answer is "here is the list", which is what a device on an unexpected
    // runtime needs.
    let p = unsafe { mobilelm_symbols_missing(c"libc.so.6".as_ptr()) };
    assert!(!p.is_null(), "libc exists, so this must succeed");
    // SAFETY: returned by `mobilelm_symbols_missing`, freed below.
    let text = unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned();
    unsafe { mobilelm_string_free(p) };
    assert!(text.starts_with('[') && text.ends_with(']'), "{text}");
    // These are JSON strings, not objects, so the message-array splitter is the
    // wrong tool. Count them directly.
    let names: Vec<&str> = text
        .trim_matches(|c| c == '[' || c == ']')
        .split(',')
        .map(|s| s.trim().trim_matches('"'))
        .filter(|s| !s.is_empty())
        .collect();
    assert_eq!(
        names.len(),
        26,
        "every optional symbol should be reported missing: {text}"
    );
    assert!(
        names.contains(&"litert_lm_sampler_params_set_temperature"),
        "{names:?}"
    );
}

#[test]
fn the_ladder_is_answerable_without_a_device() {
    // The point of moving the rule into Rust: it is a pure function, so the app's
    // accelerator choice is now covered by `cargo test` rather than by trying a
    // model on a phone.
    // SAFETY: static NUL-terminated literals.
    let p = unsafe { mobilelm_plan(c"cpu_safe".as_ptr(), 0, 1) };
    assert!(!p.is_null());
    // SAFETY: returned by `mobilelm_plan`, freed below.
    let text = unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned();
    unsafe { mobilelm_string_free(p) };
    assert!(text.contains(r#""chosen":"cpu""#), "{text}");
    assert!(text.contains(r#""exact":true"#), "{text}");
}

#[test]
fn a_null_callback_is_refused_rather_than_called() {
    // `mobilelm_send_stream` takes an optional function pointer. A null one is a
    // caller bug, and calling through it would be an immediate segfault instead
    // of a message.
    let h = Box::into_raw(Box::new(0u8)) as *mut c_void;
    let rc = unsafe {
        mobilelm_send_stream(
            h,
            c"{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}".as_ptr(),
            16,
            None,
            7,
        )
    };
    assert_eq!(rc, -1);
    // SAFETY: freed through the same path the app uses.
    // SAFETY: `h` came from `Box::into_raw` above and is freed once.
    drop(unsafe { Box::from_raw(h as *mut u8) });
    assert!(!mobilelm_last_error().is_null());
}
