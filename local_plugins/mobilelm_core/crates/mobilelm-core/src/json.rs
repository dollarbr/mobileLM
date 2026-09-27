//! Minimal JSON string escaping.
//!
//! Exists because the LiteRT-LM C API speaks JSON on its boundary -- a message
//! in, a message out -- and a model that quotes a backslash or a newline must not
//! be able to produce a malformed request or, worse, a malformed *response* that
//! we then fail to parse. serde_json would do this, but the crates in this
//! workspace are deliberately dependency-free: `mobilelm-core` has to build and
//! run on a bare `adb shell`, and a build-time dependency is one more thing that
//! can break there.
//!
//! This only covers strings. The payloads are flat objects we build ourselves, so
//! a full parser is not needed anywhere.

/// Quote and escape a string as a JSON string literal, including the quotes.
pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// A chat message in the shape the LiteRT-LM conversation API expects.
pub fn message(role: &str, content: &str) -> String {
    format!(
        "{{\"role\":{},\"content\":{}}}",
        escape(role),
        escape(content)
    )
}

/// Pull the text out of a message envelope the LiteRT-LM stream delivers.
///
/// `litert_lm_stream_chunk_get_text` is documented to return "the text content of
/// the chunk", and in 0.17.1 what it actually returns is the **serialised
/// message**:
///
/// ```json
/// {"role":"assistant","content":[{"type":"text","text":"<think>"}]}
/// ```
///
/// One envelope per token, verified on an Edge 60 with Qwen3-0.6B. The Kotlin
/// path the Flutter app already ships handles the same thing by filtering
/// `contents` for `Content.Text` and joining -- this is that filter, for a
/// language with no `Content.Text` to filter on.
///
/// It only finds `"text":` string values inside a `content` array. That is
/// narrow on purpose: a hand-rolled scan over a document this small is cheaper
/// than a parser dependency, and anything it fails to recognise comes back as
/// `None` -- the caller keeps the raw envelope rather than losing the token.
pub fn extract_content_text(envelope: &str) -> Option<String> {
    let mut out = String::new();
    let mut rest = envelope;
    let mut found = false;
    while let Some(at) = rest.find("\"text\":") {
        rest = &rest[at + 7..];
        let bytes = rest.strip_prefix('"')?;
        let (text, tail) = unescape(bytes)?;
        out.push_str(&text);
        found = true;
        rest = tail;
    }
    found.then_some(out)
}

/// Read exactly four hex digits. A truncated escape is an error, not a shorter
/// number: `\u41` would otherwise decode as `A` on a truncated buffer.
fn hex4(it: &mut std::str::CharIndices<'_>) -> Option<u32> {
    let mut n = 0u32;
    for _ in 0..4 {
        let (_, c) = it.next()?;
        n = n * 16 + c.to_digit(16)?;
    }
    Some(n)
}
/// Decode one JSON string body, returning the text and whatever follows the
/// closing quote. `None` on anything malformed — an unterminated string, an
/// escape this module does not emit, a raw control character.
fn unescape(bytes: &str) -> Option<(String, &str)> {
    let mut out = String::new();
    let mut it = bytes.char_indices();
    loop {
        let (i, c) = it.next()?;
        match c {
            '"' => return Some((out, &bytes[i + 1..])),
            '\\' => {
                let (_, e) = it.next()?;
                match e {
                    '"' => out.push('"'),
                    '\\' => out.push('\\'),
                    '/' => out.push('/'),
                    'n' => out.push('\n'),
                    'r' => out.push('\r'),
                    't' => out.push('\t'),
                    'b' => out.push('\u{08}'),
                    'f' => out.push('\u{0c}'),
                    'u' => {
                        // \uXXXX, including a surrogate pair. A lone surrogate
                        // cannot be a `char`, so it is an error rather than a
                        // replacement character nobody asked for.
                        let hi = hex4(&mut it)?;
                        if (0xd800..0xdc00).contains(&hi) {
                            if it.next()?.1 != '\\' || it.next()?.1 != 'u' {
                                return None;
                            }
                            let lo = hex4(&mut it)?;
                            if !(0xdc00..0xe000).contains(&lo) {
                                return None;
                            }
                            let cp = 0x10000 + ((hi - 0xd800) << 10) + (lo - 0xdc00);
                            out.push(char::from_u32(cp)?);
                        } else {
                            out.push(char::from_u32(hi)?);
                        }
                    }
                    _ => return None,
                }
            }
            c if (c as u32) < 0x20 => return None,
            c => out.push(c),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_prompt_cannot_break_out_of_its_json_string() {
        // The whole reason this module exists: a model prompt containing a quote
        // and a newline must not terminate the string and inject a field.
        let nasty = "tell me about \"quotes\" and\nnewlines\tand\\backslash";
        let out = message("user", nasty);
        assert_eq!(
            out,
            "{\"role\":\"user\",\"content\":\"tell me about \\\"quotes\\\" and\\nnewlines\\tand\\\\backslash\"}"
        );
        // No raw newline or quote may survive inside the value.
        let value = out
            .split_once(":\"")
            .unwrap()
            .1
            .trim_end_matches("\"}")
            .to_string();
        assert!(!value.contains('\n'));
    }

    #[test]
    fn control_characters_become_unicode_escapes() {
        assert_eq!(escape("a\u{1}b"), "\"a\\u0001b\"");
        assert_eq!(escape("\u{0}\u{1f}"), "\"\\u0000\\u001f\"");
    }

    #[test]
    fn backslash_and_quote_are_the_only_escapes_that_matter() {
        assert_eq!(escape("a\"b"), "\"a\\\"b\"");
        assert_eq!(escape("a\\b"), "\"a\\\\b\"");
        assert_eq!(escape("plain"), "\"plain\"");
    }

    #[test]
    fn non_ascii_stays_literal() {
        // UTF-8 is valid JSON, and the consumer is a C++ parser that handles it.
        // Escaping to \u would only make the log harder to read.
        assert_eq!(escape("olá, maçã"), "\"olá, maçã\"");
    }

    // --- extract_content_text -------------------------------------------------
    //
    // The fixtures below are copied verbatim out of an Edge 60 run, not invented:
    // they are what `litert_lm_stream_chunk_get_text` returned for each token of
    // Qwen3-0.6B on 2026-09-27. A test written from the header's promise would
    // have passed while the app printed JSON at the user.

    #[test]
    fn extracts_the_text_of_a_real_stream_envelope() {
        let env = r#"{"role":"assistant","content":[{"type":"text","text":"<think>"}]}"#;
        assert_eq!(extract_content_text(env).as_deref(), Some("<think>"));
    }

    #[test]
    fn extracts_text_the_model_actually_emitted() {
        for (env, want) in [
            (
                r#"{"role":"assistant","content":[{"type":"text","text":"pal"}]}"#,
                "pal",
            ),
            (
                r#"{"role":"assistant","content":[{"type":"text","text":"avras"}]}"#,
                "avras",
            ),
            (
                r#"{"role":"assistant","content":[{"type":"text","text":" um"}]}"#,
                " um",
            ),
            (
                r#"{"role":"assistant","content":[{"type":"text","text":" token"}]}"#,
                " token",
            ),
        ] {
            assert_eq!(extract_content_text(env).as_deref(), Some(want), "{env}");
        }
    }

    #[test]
    fn unescapes_what_a_model_can_emit_inside_its_own_reply() {
        // A model writing prose about code is the ordinary case for these
        // escapes, not an exotic one -- the Edge 60 run produced "hello" and
        // then a lone quote.
        assert_eq!(
            extract_content_text(
                r#"{"role":"assistant","content":[{"type":"text","text":" \"hello\" e\nmais"}]}"#
            )
            .as_deref(),
            Some(" \"hello\" e\nmais")
        );
        assert_eq!(
            extract_content_text(r#"{"content":[{"type":"text","text":"seja \u00e7e"}]}"#)
                .as_deref(),
            Some("seja çe")
        );
        // A surrogate pair is the only way an emoji survives JSON.
        assert_eq!(
            extract_content_text(r#"{"content":[{"text":"🚀"}]}"#).as_deref(),
            Some("🚀")
        );
    }

    #[test]
    fn joins_several_text_parts_in_one_envelope() {
        assert_eq!(
            extract_content_text(
                r#"{"content":[{"type":"text","text":"<think>"},{"type":"text","text":"oi"}]}"#
            )
            .as_deref(),
            Some("<think>oi")
        );
    }

    #[test]
    fn refuses_rather_than_guesses() {
        // No text field: metadata-only chunk, or an error chunk. The caller keeps
        // the raw envelope, so returning None must not mean "empty token".
        assert_eq!(extract_content_text(r#"{"role":"assistant"}"#), None);
        assert_eq!(extract_content_text(""), None);
        assert_eq!(extract_content_text("not json at all"), None);
        // Truncated mid-string, which is what a half-flushed buffer looks like.
        assert_eq!(extract_content_text(r#"{"content":[{"text":"abc"#), None);
        // A `text` key whose value is not a string must not be read as one.
        assert_eq!(extract_content_text(r#"{"content":[{"text":42}]}"#), None);
    }
}
