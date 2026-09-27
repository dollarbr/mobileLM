//! Headless probe and benchmark harness.
//!
//! Deliberately not an app. Milestone 0 answers two questions that an APK cannot
//! answer any faster:
//!
//! 1. Does the LiteRT-LM C API `.so` load on this phone's Bionic, and do its
//!    symbols resolve? (The AAR's JNI path proves nothing about the C API.)
//! 2. What does this CPU report, and which NPU libraries are visible?
//!
//! Both run from `adb shell` with nothing else installed, which is why there is
//! no Gradle project here yet. An APK adds packaging questions that cannot fail
//! any earlier than the engine itself.

use std::process::ExitCode;

use mobilelm_core::probe::{DeviceReport, LITERT_LM_C_API_SYMBOLS};
// `Engine` is a trait: without it in scope, `generate` and `load_report` are
// invisible on the struct.
use mobilelm_core::Engine as _;
use mobilelm_litert::LiteRt;

const USAGE: &str = "\
mobilelm-bench — device probe and engine benchmark (mobileLM-rs)

USAGE:
    mobilelm-bench --probe [--npu-dir <dir>] [--litertlm <path/to/liblitert-lm.so>]

    Reports CPU model + feature letters, total RAM, peak RSS, and whether the
    given native libraries dlopen and export the symbols we need. Exits 0 when
    every requested library loaded, 1 otherwise.

    mobilelm-bench --bench --model <file.litertlm> --runtime <path/to/liblitert-lm.so>
                    [--mmproj <path>] [--backend cpu|gpu|npu] [--ctx <n>]
                    [--threads <n>] [--max-tokens <n>] [--prompt <s>] [--stream]
                    [--npu-dir <d>]

    Every flag takes a value, and an equals sign works too. --stream is the one
    exception: it takes none.

    Loads a .litertlm through the LiteRT-LM C API and generates one turn. Prints
    one JSON object per phase: device, load, then either one 'token' per chunk
    (--stream) or a single 'answer', then 'done' with TTFT, throughput and peak
    RSS. Needs liblitert-lm.so reachable at runtime -- for an adb shell run, set
    LD_LIBRARY_PATH to the directory holding it.

GLOBAL:
    -h, --help
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(code) => code,
        Err(msg) => {
            eprintln!("mobilelm-bench: {msg}");
            ExitCode::from(2)
        }
    }
}

fn run(args: &[String]) -> Result<ExitCode, String> {
    if args.is_empty() || args.iter().any(|a| a == "-h" || a == "--help") {
        print!("{USAGE}");
        return Ok(ExitCode::SUCCESS);
    }

    let mode = args[0].as_str();
    let opts = Opts::parse(&args[1..])?;
    match mode {
        "--probe" => probe_mode(&opts),
        "--bench" => bench_mode(&opts),
        other => Err(format!("unknown mode {other:?}; try --help")),
    }
}

fn probe_mode(opts: &Opts) -> Result<ExitCode, String> {
    // Two candidate names for the same thing: whatever the user points at, and
    // the conventional drop location inside an app's native library dir. The
    // second is a guess, so it is only tried when the first is absent.
    let mut targets: Vec<(String, &[&str])> = Vec::new();
    match opts.value("litertlm") {
        Some(p) => targets.push((p, LITERT_LM_C_API_SYMBOLS)),
        None => {
            if let Some(dir) = opts.value("npu-dir") {
                targets.push((format!("{dir}/liblitert-lm.so"), LITERT_LM_C_API_SYMBOLS));
            }
        }
    }

    if targets.is_empty() {
        eprintln!(
            "note: no --litertlm given, so only CPU and RAM are reported.\n\
             hint: pass --litertlm /data/local/tmp/litert-lm/lib/android_arm64/liblitert-lm.so"
        );
    }

    let report = DeviceReport::collect(&targets, opts.value("npu-dir").as_deref());
    println!("{}", report.to_json());

    // A library that failed to load is information, not a crash: the point of the
    // probe is to find out. But a caller scripting this wants a signal, so the
    // exit code says "something you asked for is not there".
    let all_loaded = report.libraries.iter().all(|(_, r)| r.is_ok());
    Ok(if all_loaded {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}

/// Load a `.litertlm` and generate one turn, printing one JSON object per phase.
///
/// Output is line-delimited JSON on purpose: the caller is a human reading a
/// terminal over `adb shell`, and `jq` can pull any single field out of it without
/// a parser. Phases come in order — device, load, then either one `token` per
/// chunk or a single `answer`, then `done`.
fn bench_mode(opts: &Opts) -> Result<ExitCode, String> {
    let Some(model) = opts.value("model") else {
        return Err("--bench needs a model path".into());
    };
    let Some(runtime) = opts.value("runtime") else {
        return Err("--bench needs --runtime <path to liblitert-lm.so>".into());
    };
    let backend = opts
        .value("backend")
        .as_deref()
        .map(|b| mobilelm_core::Backend::parse(b).ok_or_else(|| format!("unknown backend {b:?}")))
        .transpose()?
        .unwrap_or(mobilelm_core::Backend::Cpu);

    // Device context first, even if the model then fails: the point of the run is
    // usually "why is this slow on *this* phone", and a load error without the CPU
    // and RAM next to it is half an answer.
    let report = DeviceReport::collect(&[], opts.value("npu-dir").as_deref());
    println!("{}", report.to_json());

    let cfg = mobilelm_core::EngineConfig {
        model_path: model.clone(),
        mmproj_path: opts.value("mmproj"),
        backend,
        n_ctx: opts.value("ctx").and_then(|v| v.parse().ok()),
        n_threads: opts.value("threads").and_then(|v| v.parse().ok()),
    };
    let prompt = opts
        .value("prompt")
        .unwrap_or_else(|| "Explique em uma frase o que e um token.".to_string());
    let max_tokens: usize = opts
        .value("max-tokens")
        .and_then(|v| v.parse().ok())
        .unwrap_or(96);

    let load_started = std::time::Instant::now();
    let mut engine = LiteRt::load(&runtime, &cfg, None).map_err(|e| e.to_string())?;
    let load_ms = load_started.elapsed().as_millis() as u64;
    println!(
        "{{\"phase\":\"load\",\"backend_requested\":\"{}\",\"actual\":\"{}\",\
          \"load_ms\":{},\"model_bytes\":{}}}",
        backend,
        engine.load_report().actual,
        load_ms,
        engine.load_report().model_bytes
    );
    for note in &engine.load_report().notes {
        println!("{{\"note\":{}}}", quote(note));
    }

    // --stream prints every chunk as it lands, which is the whole point on a
    // phone: you can see the first token arrive seconds before the last one, and
    // a run that hangs is obvious rather than silent.
    let streaming = opts.value("stream").is_some();
    let req = mobilelm_core::GenRequest {
        prompt: prompt.clone(),
        max_tokens,
        stream: streaming,
    };
    let mut printed = 0usize;
    let mut collected = String::new();
    let outcome = engine
        .generate(&req, &mut |piece| {
            if streaming {
                printed += 1;
                println!("{{\"token\":{}}}", quote(piece));
            } else {
                collected.push_str(piece);
            }
        })
        .map_err(|e| format!("generation failed: {e}"))?;

    if !streaming {
        println!("{{\"answer\":{}}}", quote(&collected));
    }
    println!(
        "{{\"phase\":\"done\",\"ttft_ms\":{},\"total_ms\":{},\"chunks\":{},\
          \"prefill_tps\":{:.2},\"decode_tps\":{:.2},\"peak_rss_kib\":{},\
          \"printed_chunks\":{},\"bytes_out\":{}}}",
        outcome.ttft_ms,
        outcome.total_ms,
        outcome.decode_tokens,
        outcome.prefill_tps(),
        outcome.decode_tps(),
        mobilelm_core::probe::peak_rss_kib().unwrap_or(0),
        printed,
        collected.len()
    );
    Ok(ExitCode::SUCCESS)
}

/// Quote a string as a JSON string literal. Duplicated from `mobilelm_core::json`
/// on purpose: the harness prints its own line format and does not want to grow a
/// dependency for one function, and the two are pinned by the same tests.
fn quote(s: &str) -> String {
    mobilelm_core::json::escape(s)
}

/// `--key value` and `--key=value`, with unknown keys rejected rather than
/// ignored: a typo in a benchmark flag produces a number that looks real and
/// measures the wrong thing.
#[derive(Debug)]
struct Opts {
    pairs: Vec<(String, String)>,
}

impl Opts {
    /// Every key `parse` accepts, each taking one value.
    const KNOWN: &'static [&'static str] = &[
        "probe",
        "bench",
        "model",
        "backend",
        "mmproj",
        "ctx",
        "threads",
        "max-tokens",
        "prompt",
        "litertlm",
        "npu-dir",
        "runtime",
    ];

    /// Keys that carry no value. Everything else takes one, and a value-taking
    /// flag at the end of the line is an error rather than a silent default.
    const BARE: &'static [&'static str] = &["stream"];

    /// Re-exported for the usage-drift test, which lives in `tests` below and so
    /// cannot see private items of the same module without this.
    #[cfg(test)]
    const KNOWN_FOR_TESTS: &'static [&'static str] = Self::KNOWN;
    #[cfg(test)]
    const BARE_FOR_TESTS: &'static [&'static str] = Self::BARE;

    fn parse(args: &[String]) -> Result<Self, String> {
        let known = Self::KNOWN;
        let bare = Self::BARE;
        let mut pairs = Vec::new();
        let mut i = 0;
        while i < args.len() {
            let a = &args[i];
            let Some(rest) = a.strip_prefix("--") else {
                return Err(format!("expected a --flag, got {a:?}"));
            };
            let (key, value) = match rest.split_once('=') {
                Some((k, v)) => (k.to_string(), v.to_string()),
                None if bare.contains(&rest) => (rest.to_string(), String::new()),
                None => {
                    i += 1;
                    let v = args
                        .get(i)
                        .ok_or_else(|| format!("--{rest} needs a value"))?
                        .clone();
                    (rest.to_string(), v)
                }
            };
            if !known.contains(&key.as_str()) && !bare.contains(&key.as_str()) {
                return Err(format!(
                    "unknown flag --{key}; known: {}",
                    known
                        .iter()
                        .map(|k| format!("--{k}"))
                        .collect::<Vec<_>>()
                        .join(" ")
                ));
            }
            pairs.push((key, value));
            i += 1;
        }
        Ok(Self { pairs })
    }

    fn value(&self, key: &str) -> Option<String> {
        self.pairs
            .iter()
            .rev()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opts(args: &[&str]) -> Opts {
        Opts::parse(&args.iter().map(|s| s.to_string()).collect::<Vec<_>>()).unwrap()
    }

    #[test]
    fn both_flag_spellings_work() {
        let o = opts(&["--litertlm", "/a/b.so"]);
        assert_eq!(o.value("litertlm").as_deref(), Some("/a/b.so"));
        let o = opts(&["--litertlm=/c/d.so"]);
        assert_eq!(o.value("litertlm").as_deref(), Some("/c/d.so"));
    }

    #[test]
    fn a_typo_is_an_error_not_a_silently_ignored_flag() {
        let args: Vec<String> = ["--litertm", "/a"].iter().map(|s| s.to_string()).collect();
        let err = Opts::parse(&args).unwrap_err();
        assert!(err.contains("unknown flag"), "{err}");
    }

    #[test]
    fn a_flag_without_a_value_is_an_error() {
        let args: Vec<String> = vec!["--ctx".into()];
        assert!(Opts::parse(&args).is_err());
    }

    #[test]
    fn the_last_occurrence_wins() {
        let o = opts(&["--ctx", "4096", "--ctx", "8192"]);
        assert_eq!(o.value("ctx").as_deref(), Some("8192"));
    }

    #[test]
    fn a_bare_word_is_rejected() {
        let args: Vec<String> = vec!["litertm".into()];
        assert!(Opts::parse(&args).is_err());
    }

    #[test]
    fn a_bare_flag_parses_and_reads_as_present() {
        // `--stream` is the only flag that takes no value. It went missing from
        // KNOWN once and the symptom was "unknown flag --stream" on a phone,
        // with the generation itself already working -- so the pair is pinned
        // together here instead of by hand.
        let o = opts(&["--stream"]);
        assert!(o.value("stream").is_some());
        assert!(Opts::parse(&["--streem".to_string()]).is_err());
    }

    #[test]
    fn the_usage_text_lists_exactly_the_flags_the_parser_accepts() {
        // USAGE is the only documentation this binary has, and it drifted twice
        // in one sitting: `--bench <model>` implied a positional the parser
        // rejects, and `--stream` was missing from KNOWN. Compare the two lists
        // instead of trusting either to stay put.
        //
        // -h/--help are handled before the parser ever sees the line.
        const ALSO: &[&str] = &["h", "help"];
        let accepted = |f: &str| {
            Opts::KNOWN_FOR_TESTS.contains(&f)
                || Opts::BARE_FOR_TESTS.contains(&f)
                || ALSO.contains(&f)
        };

        for flag in Opts::KNOWN_FOR_TESTS.iter().chain(Opts::BARE_FOR_TESTS) {
            assert!(
                USAGE.contains(&format!("--{flag}")),
                "--{flag} is accepted but undocumented in USAGE"
            );
        }
        for line in USAGE.lines() {
            for token in line.split_whitespace() {
                let Some(flag) = token.strip_prefix("--") else {
                    continue;
                };
                let flag = flag
                    .trim_end_matches(|c: char| !c.is_ascii_alphanumeric() && c != '-' && c != '=');
                if flag.is_empty() {
                    continue;
                }
                assert!(
                    accepted(flag),
                    "USAGE mentions --{flag}, which is not accepted"
                );
            }
        }
    }
}
