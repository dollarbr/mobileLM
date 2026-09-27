//! What this device can actually do, measured rather than assumed.
//!
//! The Flutter app learned this the expensive way: a SoC can sit on Google's
//! supported-NPU list and still have no reachable APU, because reaching one takes
//! *two* independent things lining up. The same shape of trap is waiting for
//! every other capability, so the probe exists to turn each claim into something
//! a device run can settle.
//!
//! No dependencies on purpose. This module is the one that must build and run on
//! a bare `adb shell` with nothing alongside it, and it is what a future UI calls
//! during startup to decide the ladder.

use std::ffi::CString;
use std::fmt::Write as _;

// --- dlopen/dlsym, declared by hand so this crate needs no libc --------------

extern "C" {
    fn dlopen(
        filename: *const std::os::raw::c_char,
        flags: std::os::raw::c_int,
    ) -> *mut std::os::raw::c_void;
    fn dlsym(
        handle: *mut std::os::raw::c_void,
        symbol: *const std::os::raw::c_char,
    ) -> *mut std::os::raw::c_void;
    fn dlerror() -> *const std::os::raw::c_char;
}

/// `RTLD_NOW | RTLD_LOCAL`, so a missing symbol fails here instead of at the
/// first inference call, on a phone, with a model half-loaded.
const RTLD_NOW: std::os::raw::c_int = 2;

fn last_dl_error() -> String {
    // Safety: dlerror returns either NULL or a NUL-terminated string owned by
    // the loader, valid until the next dl* call on this thread.
    unsafe {
        let p = dlerror();
        if p.is_null() {
            String::new()
        } else {
            std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned()
        }
    }
}

/// A library that was opened successfully, with the symbols resolved.
#[derive(Debug)]
pub struct LoadedLib {
    handle: *mut std::os::raw::c_void,
    path: String,
}

// The handle is an owned resource; nothing here is shared across threads.
unsafe impl Send for LoadedLib {}

impl LoadedLib {
    /// Resolve one symbol. `Ok(())` means the symbol exists in this library.
    pub fn symbol(&self, name: &str) -> Result<(), String> {
        let c = CString::new(name).map_err(|_| "symbol name has a NUL".to_string())?;
        // Safety: `self.handle` came from a successful dlopen and is kept alive
        // by the struct; dlsym on a valid handle with a NUL-terminated name is
        // the documented use.
        let p = unsafe { dlsym(self.handle, c.as_ptr()) };
        if p.is_null() {
            Err(last_dl_error())
        } else {
            Ok(())
        }
    }

    /// Resolve many, returning only the ones that are missing. A missing symbol
    /// is a version mismatch worth reporting in full, not a first-failure exit.
    pub fn missing_symbols(&self, names: &[&str]) -> Vec<String> {
        names
            .iter()
            .filter(|n| self.symbol(n).is_err())
            .map(|n| n.to_string())
            .collect()
    }

    pub fn path(&self) -> &str {
        &self.path
    }
}

impl Drop for LoadedLib {
    fn drop(&mut self) {
        // Intentionally not dlclose: unloading a 39 MB inference runtime while a
        // model handle is still alive is a use-after-free waiting to happen, and
        // the process is about to move on anyway. The OS reclaims it.
    }
}

#[derive(Debug, Clone)]
pub struct ProbeError {
    pub path: String,
    pub reason: String,
}

impl std::fmt::Display for ProbeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.path, self.reason)
    }
}

/// Open a shared library and check that it carries the symbols we expect.
///
/// This is the whole point of the probe: it answers "would inference even start"
/// without a model file, a UI, or an APK.
pub fn probe_library(path: &str, expect: &[&str]) -> Result<LoadedLib, ProbeError> {
    let c = CString::new(path).map_err(|_| ProbeError {
        path: path.to_string(),
        reason: "path has an interior NUL".into(),
    })?;
    // Safety: `c` is a valid NUL-terminated string for the duration of the call.
    let handle = unsafe { dlopen(c.as_ptr(), RTLD_NOW) };
    if handle.is_null() {
        let reason = last_dl_error();
        return Err(ProbeError {
            path: path.to_string(),
            // A bare "not found" and a "found but the linker namespace forbids
            // it" are completely different verdicts. The loader's own wording is
            // the only thing that separates them, so keep it verbatim.
            reason: if reason.is_empty() {
                "dlopen returned null with no error".into()
            } else {
                reason
            },
        });
    }
    let lib = LoadedLib {
        handle,
        path: path.to_string(),
    };
    let missing = lib.missing_symbols(expect);
    if !missing.is_empty() {
        return Err(ProbeError {
            path: path.to_string(),
            reason: format!("loaded but missing {}", missing.join(", ")),
        });
    }
    Ok(lib)
}

/// The LiteRT-LM 0.16+ C API surface the engine actually calls. Kept short on
/// purpose: these are the symbols whose absence means "wrong build", as opposed
/// to a feature we do not use.
pub const LITERT_LM_C_API_SYMBOLS: &[&str] = &[
    "litert_lm_engine_settings_create",
    "litert_lm_engine_create",
    "litert_lm_engine_delete",
    "litert_lm_conversation_create",
    "litert_lm_conversation_send_message",
    "litert_lm_conversation_send_message_stream",
    "litert_lm_conversation_delete",
    "litert_lm_engine_settings_set_num_threads",
    "litert_lm_engine_settings_set_litert_dispatch_lib_dir",
];

// --- /proc readers -----------------------------------------------------------

fn read_proc(path: &str) -> Option<String> {
    std::fs::read_to_string(path).ok()
}

/// The CPU feature letters Linux reports in `/proc/cpuinfo` under `Features`.
///
/// These are what pick the llama.cpp CPU variant: the vendored build compiles one
/// shared object per feature set and scores them against `getauxval(AT_HWCAP)` at
/// load time. A model that silently runs the baseline variant instead of dotprod
/// is the single biggest CPU-side performance mistake available, so the letters
/// are worth having in a log next to every measurement.
///
/// ARM spells the line `Features` and x86 spells it `flags`; only the ARM form is
/// read, so this returns an empty list off-ARM rather than mixing two
/// incompatible feature vocabularies.
pub fn cpu_features() -> Vec<String> {
    match read_proc("/proc/cpuinfo") {
        Some(text) => cpu_features_from(&text),
        None => Vec::new(),
    }
}

/// Parse the `Features` line out of `/proc/cpuinfo` text.
pub fn cpu_features_from(cpuinfo: &str) -> Vec<String> {
    for line in cpuinfo.lines() {
        if let Some(rest) = line.strip_prefix("Features") {
            return split_proc_value(rest)
                .into_iter()
                .filter(|s| !s.is_empty() && *s != ":")
                .map(|s| s.to_ascii_lowercase())
                .collect();
        }
    }
    Vec::new()
}

/// Split the value part of a `key\t: value` line.
///
/// /proc/cpuinfo and /proc/meminfo both pad the value under a tab and put a colon
/// in front of it (`Features\t: fp asimd ...`). `split_whitespace` alone therefore
/// yields a bare ":" as the first "feature", which is worse than useless: it looks
/// like a capability letter and would be compared against real ones forever.
fn split_proc_value(rest: &str) -> Vec<&str> {
    let rest = rest.trim_start_matches(|c: char| c.is_whitespace() || c == ':');
    rest.split_whitespace().collect()
}

/// What `/proc/cpuinfo` says about the cores, as distinct from what the kernel
/// calls them.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CpuId {
    /// ARM implementer: 0x41 is ARM Ltd.
    pub implementer: Option<u32>,
    /// ARM part ID, e.g. 0xd41.
    pub part: Option<u32>,
    pub variant: Option<u32>,
    /// How many logical CPUs the kernel reports.
    pub cores: usize,
    /// Part ID per logical CPU, in kernel order. More useful than an average when
    /// the SoC is heterogeneous, which is the normal case on a phone.
    pub parts: Vec<u32>,
}

impl CpuId {
    /// Decode an ARM part ID to a core name.
    ///
    /// Table transcribed from `arch/arm64/include/asm/cputype.h` in the Linux
    /// tree. Read the file rather than trusting a list like this one to stay
    /// right: a mis-transcribed digit here names the wrong core, and the mistake
    /// is invisible in a benchmark that merely looks plausible.
    ///
    /// The two that matter for this project, verified against a real Edge 60:
    /// 0xd05 is Cortex-A55 and 0xd41 is Cortex-A78.
    pub fn core_name(part: u32) -> Option<&'static str> {
        Some(match part {
            0xd03 => "Cortex-A53",
            0xd04 => "Cortex-A35",
            0xd05 => "Cortex-A55",
            0xd07 => "Cortex-A57",
            0xd08 => "Cortex-A72",
            0xd09 => "Cortex-A73",
            0xd0a => "Cortex-A75",
            0xd0b => "Cortex-A76",
            0xd0c => "Neoverse-N1",
            0xd0d => "Cortex-A77",
            0xd0e => "Cortex-A76AE",
            0xd40 => "Neoverse-V1",
            0xd41 => "Cortex-A78",
            0xd42 => "Cortex-A78AE",
            0xd44 => "Cortex-X1",
            0xd46 => "Cortex-A510",
            0xd47 => "Cortex-A710",
            0xd48 => "Cortex-X2",
            0xd49 => "Neoverse-N2",
            0xd4b => "Cortex-A78C",
            0xd4c => "Cortex-X1C",
            0xd4d => "Cortex-A715",
            0xd4e => "Cortex-X3",
            0xd4f => "Neoverse-V2",
            0xd80 => "Cortex-A520",
            0xd81 => "Cortex-A720",
            0xd82 => "Cortex-X4",
            0xd84 => "Neoverse-V3",
            0xd87 => "Cortex-A725",
            0xd8e => "Neoverse-N3",
            _ => return None,
        })
    }

    /// `"4x Cortex-A78 + 4x Cortex-A55"`, collapsing repeats.
    ///
    /// Heterogeneous clusters are the reason this exists: a single averaged name
    /// hides that half the cores are a different microarchitecture, which is
    /// exactly the fact that makes a thread count a tuning decision instead of a
    /// guess.
    pub fn topology(&self) -> String {
        if self.parts.is_empty() {
            return "unknown".to_string();
        }
        let mut runs: Vec<(u32, usize)> = Vec::new();
        for p in &self.parts {
            match runs.last_mut() {
                Some((last, n)) if last == p => *n += 1,
                _ => runs.push((*p, 1)),
            }
        }
        runs.iter()
            .map(|(part, n)| {
                let name = Self::core_name(*part).unwrap_or("unknown-core");
                format!("{n}x {name}")
            })
            .collect::<Vec<_>>()
            .join(" + ")
    }
}

/// Parse a hex value as /proc spells it, i.e. with the `0x` prefix.
///
/// `u32::from_str_radix` rejects the prefix outright -- it would read the `0`,
/// stop at the `x`, and return an error -- so the prefix has to come off by
/// hand. Getting this wrong returns `None` for a value that is present, which
/// reads as "this device does not say" rather than "we failed to parse it".
fn parse_hex(rest: &str) -> Option<u32> {
    let rest = rest.trim();
    let digits = rest
        .strip_prefix("0x")
        .or_else(|| rest.strip_prefix("0X"))
        .unwrap_or(rest);
    if digits.is_empty() {
        return None;
    }
    u32::from_str_radix(digits, 16).ok()
}

/// Read implementer/part/variant and the per-core part list.
pub fn cpu_id() -> CpuId {
    match read_proc("/proc/cpuinfo") {
        Some(text) => parse_cpu_id(&text),
        None => CpuId::default(),
    }
}

/// Parse `/proc/cpuinfo` text into a [`CpuId`].
///
/// Split out from [`cpu_id`] so the parsing is testable against a captured
/// device dump rather than only against whatever machine the tests happen to run
/// on. That matters more than usual here: the decoded core names decide a thread
/// count, and a silently wrong name still produces a plausible-looking number.
pub fn parse_cpu_id(cpuinfo: &str) -> CpuId {
    let mut id = CpuId::default();
    for line in cpuinfo.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let value = value.trim();
        let Some(first_value) = split_proc_value(value).first().copied() else {
            continue;
        };
        match key.trim() {
            "CPU implementer" => id.implementer = parse_hex(first_value),
            "CPU variant" => id.variant = parse_hex(first_value),
            "CPU part" => {
                if let Some(p) = parse_hex(first_value) {
                    id.part.get_or_insert(p);
                    id.parts.push(p);
                }
            }
            "processor" => id.cores += 1,
            _ => {}
        }
    }
    id
}

/// Pull the leading integer out of a `Key:   1234 kB` line.
///
/// The value is right-aligned under a tab in /proc, so the remainder starts with
/// whitespace. Trimming first is not cosmetic: skipping it yields an empty digit
/// run and a silent `None`, which reads exactly like "this device has no RAM
/// information" rather than "the parser is wrong".
fn parse_kib_after_prefix<'a>(lines: impl Iterator<Item = &'a str>, prefix: &str) -> Option<u64> {
    for line in lines {
        if let Some(rest) = line.strip_prefix(prefix) {
            let digits: String = rest
                .trim_start()
                .chars()
                .take_while(char::is_ascii_digit)
                .collect();
            if digits.is_empty() {
                return None;
            }
            return digits.parse().ok();
        }
    }
    None
}

/// Total RAM in kibibytes, or `None` where /proc is not available.
pub fn mem_total_kib() -> Option<u64> {
    parse_kib_after_prefix(read_proc("/proc/meminfo")?.lines(), "MemTotal:")
}

/// Peak resident set of this process in kibibytes (`VmHWM`).
///
/// Worth logging next to every throughput number: a faster engine that also
/// eats 2x the RAM is not a win on a phone, and tok/s alone cannot tell them
/// apart.
pub fn peak_rss_kib() -> Option<u64> {
    parse_kib_after_prefix(read_proc("/proc/self/status")?.lines(), "VmHWM:")
}

/// Files in a directory whose name looks like a vendor NPU library.
///
/// Scans for the whole `libneuron*` family, not only the sonames LiteRT's
/// dispatch happens to try, because the interesting fact on a real device turned
/// out to be the inverse: several neuron libraries are present on disk while
/// *none* of them is one an app may link. A narrower filter would report "nothing
/// here" and hide that. Deciding what is loadable is the linker's business, and
/// only the OEM's `public.libraries*.txt` draws that line.
pub fn npu_candidates(dir: &str) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut found: Vec<String> = entries
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|n| {
            n.starts_with("libLiteRtDispatch")
                || n.starts_with("libneuron")
                || n.starts_with("libneuronusdk")
                || n.starts_with("libQnnHtp")
        })
        .collect();
    found.sort();
    found
}

// --- the report --------------------------------------------------------------

#[derive(Debug, Clone, Default)]
pub struct DeviceReport {
    pub cpu: CpuId,
    pub cpu_features: Vec<String>,
    pub mem_total_kib: Option<u64>,
    pub peak_rss_kib: Option<u64>,
    /// Path -> Ok(number of symbols verified) or the loader's own complaint.
    pub libraries: Vec<(String, Result<usize, String>)>,
    /// Vendor NPU libraries visible in the scanned directory. Presence is not
    /// reachability: see [`npu_candidates`].
    pub npu_files: Vec<String>,
}

impl DeviceReport {
    /// Probe each `(path, expected_symbols)` pair, and scan `npu_dir` for vendor
    /// dispatch libraries. Takes owned paths so a caller can build the list from
    /// owned strings without borrowing gymnastics.
    pub fn collect(lib_paths: &[(String, &[&str])], npu_dir: Option<&str>) -> Self {
        let libraries = lib_paths
            .iter()
            .map(|(path, expect)| {
                // probe_library already verified every symbol, so a success means
                // all `expect.len()` of them resolved. The handle is dropped
                // without dlclose on purpose (see LoadedLib::drop), so the
                // library stays mapped for the rest of the run.
                let r = probe_library(path, expect).map(|_| expect.len());
                (path.clone(), r.map_err(|e| e.reason))
            })
            .collect();
        Self {
            cpu: cpu_id(),
            cpu_features: cpu_features(),
            mem_total_kib: mem_total_kib(),
            peak_rss_kib: peak_rss_kib(),
            libraries,
            npu_files: npu_dir.map(npu_candidates).unwrap_or_default(),
        }
    }

    /// One JSON object per line, no serde. The harness output is read by humans
    /// and by `jq`; a flat object does not justify a dependency in a crate whose
    /// job is to have none.
    pub fn to_json(&self) -> String {
        let feats: Vec<String> = self
            .cpu_features
            .iter()
            .map(|f| format!("\"{f}\""))
            .collect();
        let libs: Vec<String> = self
            .libraries
            .iter()
            .map(|(path, r)| match r {
                Ok(n) => format!("{{\"path\":\"{path}\",\"loaded\":true,\"symbols_ok\":{n}}}"),
                Err(e) => format!(
                    "{{\"path\":\"{path}\",\"loaded\":false,\"error\":{}}}",
                    json_string(e)
                ),
            })
            .collect();
        let npu: Vec<String> = self.npu_files.iter().map(|n| json_string(n)).collect();
        let mut s = String::from("{");
        let _ = write!(
            s,
            "\"cpu\":{{\"implementer\":{},\"part\":{},\"cores\":{},\"topology\":{}}}",
            opt_hex(self.cpu.implementer),
            opt_hex(self.cpu.part),
            self.cpu.cores,
            json_string(&self.cpu.topology())
        );
        let _ = write!(s, ",\"cpu_features\":[{}]", feats.join(","));
        let _ = write!(
            s,
            ",\"mem_total_kib\":{}",
            self.mem_total_kib.map_or("null".into(), |v| v.to_string())
        );
        let _ = write!(
            s,
            ",\"peak_rss_kib\":{}",
            self.peak_rss_kib.map_or("null".into(), |v| v.to_string())
        );
        let _ = write!(s, ",\"libraries\":[{}]", libs.join(","));
        let _ = write!(s, ",\"npu_files\":[{}]", npu.join(","));
        s.push('}');
        s
    }
}

fn opt_hex(v: Option<u32>) -> String {
    match v {
        // The quotes live here, inside the format string. They were briefly
        // dropped, which emitted bare `0x41` into the JSON -- valid-looking Rust,
        // invalid JSON, and nothing in the build would have said so. That is the
        // whole argument for hand-rolling JSON only where a test asserts the
        // quoted form.
        Some(v) => format!("\"{v:#x}\""),
        None => "null".to_string(),
    }
}

fn json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_string_escapes_what_would_break_the_line() {
        assert_eq!(json_string("a\"b"), "\"a\\\"b\"");
        assert_eq!(json_string("a\\b"), "\"a\\\\b\"");
        assert_eq!(json_string("a\nb"), "\"a\\nb\"");
        assert_eq!(json_string("a\u{1}b"), "\"a\\u0001b\"");
        // Non-ASCII stays literal: the report is read by humans, and the tool
        // that reads it is UTF-8 anyway.
        assert_eq!(json_string("olá"), "\"olá\"");
    }

    #[test]
    fn report_is_one_line_of_valid_looking_json() {
        let r = DeviceReport {
            cpu: CpuId {
                implementer: Some(0x41),
                part: Some(0xd41),
                variant: Some(2),
                cores: 8,
                parts: vec![0xd41, 0xd41, 0xd41, 0xd41, 0xd05, 0xd05, 0xd05, 0xd05],
            },
            cpu_features: vec!["asimd".into(), "atomics".into()],
            mem_total_kib: Some(8_000_000),
            peak_rss_kib: Some(1234),
            libraries: vec![
                ("/data/x.so".into(), Ok(9)),
                ("/data/y.so".into(), Err("not found".into())),
            ],
            npu_files: vec!["libLiteRtDispatch_MediaTek.so".into()],
        };
        let j = r.to_json();
        assert!(!j.contains('\n'), "report must stay on one line");
        assert!(j.starts_with('{') && j.ends_with('}'));
        assert!(
            j.contains(r#""cpu":{"implementer":"0x41","part":"0xd41","cores":8"#),
            "{j}"
        );
        assert!(
            j.contains(r#""topology":"4x Cortex-A78 + 4x Cortex-A55""#),
            "{j}"
        );
        assert!(j.contains(r#""cpu_features":["asimd","atomics"]"#));
        assert!(j.contains(r#""loaded":false,"error":"not found""#));
    }

    // Captured from the target device (Motorola Edge 60, MT6878) on 2026-09-27,
    // abridged to the first core. The part IDs are the whole point: 0xd05 is a
    // Cortex-A55 and 0xd41 is a Cortex-A78, which is the opposite of what a
    // careless reading of the hex suggests (0xd41 looks like it should be the
    // newer, bigger part -- it is, but 0xd05 is not an A78). Verified against
    // arch/arm64/include/asm/cputype.h in the Linux tree, not from memory.
    const EDGE60_CPUINFO: &str = "\
processor\t: 0
BogoMIPS\t: 26.00
Features\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp
CPU implementer\t: 0x41
CPU architecture: 8
CPU variant\t: 0x2
CPU part\t: 0xd05
CPU revision\t: 0
";

    #[test]
    fn proc_values_are_tab_indented_with_a_colon_and_the_colon_is_not_a_feature() {
        // `Features\t: fp asimd ...` — naive whitespace splitting yields ":" as
        // the first feature, which then compares like a capability letter forever.
        let f = cpu_features_from(EDGE60_CPUINFO);
        assert_eq!(f.first().map(String::as_str), Some("fp"));
        assert!(
            !f.iter().any(|x| x == ":"),
            "the separator leaked in: {f:?}"
        );
        assert!(f.contains(&"asimdhp".to_string()));
        assert!(f.contains(&"asimddp".to_string()));
    }

    #[test]
    fn the_edge_60_decodes_to_four_a55_and_four_a78() {
        // This is the fact that makes 4 threads optimal on that phone, so a wrong
        // decode here would misinform thread tuning forever.
        //
        // Order is the order the device reports: four A55s (0xd05) first, then
        // four A78s (0xd41). Written out rather than generated, so the input and
        // the expectation can be read side by side -- the earlier version of this
        // test appended to a fixture that already had a core in it and counted
        // nine.
        let parts = [
            "0xd05", "0xd05", "0xd05", "0xd05", "0xd41", "0xd41", "0xd41", "0xd41",
        ];
        let cpuinfo: String = parts
            .iter()
            .enumerate()
            .map(|(i, part)| {
                format!(
                    "processor\t: {i}\nBogoMIPS\t: 26.00\n\
                     CPU implementer\t: 0x41\nCPU architecture: 8\nCPU variant\t: 0x2\n\
                     CPU part\t: {part}\nCPU revision\t: 0\n"
                )
            })
            .collect();
        let id = parse_cpu_id(&cpuinfo);
        assert_eq!(id.cores, 8);
        assert_eq!(id.implementer, Some(0x41));
        assert_eq!(id.variant, Some(0x2));
        assert_eq!(id.topology(), "4x Cortex-A55 + 4x Cortex-A78");
    }

    #[test]
    fn hex_values_are_spelled_with_the_0x_prefix_in_proc_and_must_survive_it() {
        assert_eq!(parse_hex("0x41"), Some(0x41));
        assert_eq!(parse_hex(" 0x41 "), Some(0x41));
        assert_eq!(parse_hex("0Xd41"), Some(0xd41));
        // Bare digits, in case a kernel ever drops the prefix.
        assert_eq!(parse_hex("41"), Some(0x41));
        assert_eq!(parse_hex("0x"), None);
        assert_eq!(parse_hex(""), None);
    }

    #[test]
    fn an_unknown_core_id_is_named_rather_than_guessed() {
        assert_eq!(CpuId::core_name(0xd05), Some("Cortex-A55"));
        assert_eq!(CpuId::core_name(0xd41), Some("Cortex-A78"));
        assert_eq!(CpuId::core_name(0x0000_1234), None);
        let id = CpuId {
            parts: vec![0x1234, 0x1234],
            ..Default::default()
        };
        assert_eq!(id.topology(), "2x unknown-core");
    }

    #[test]
    fn a_missing_library_reports_the_loaders_own_words() {
        let e = probe_library("/definitely/not/here.so", &["whatever"]).unwrap_err();
        assert!(!e.reason.is_empty(), "a dlopen failure must explain itself");
    }

    #[test]
    fn npu_candidates_is_empty_for_a_missing_directory() {
        assert!(npu_candidates("/definitely/not/here").is_empty());
    }

    #[test]
    fn our_own_c_api_symbol_list_is_not_empty() {
        assert!(LITERT_LM_C_API_SYMBOLS.len() >= 8);
    }

    #[test]
    fn proc_values_are_right_aligned_under_a_tab() {
        // Copied from a real /proc/meminfo. The leading whitespace is the whole
        // reason this parser trims before reading digits.
        let meminfo = "MemTotal:       16044456 kB\nMemFree:         2175128 kB\n";
        assert_eq!(
            parse_kib_after_prefix(meminfo.lines(), "MemTotal:"),
            Some(16_044_456)
        );
        let status = "Name:\tbench\nVmHWM:\t   123456 kB\nVmRSS:\t 1000 kB\n";
        assert_eq!(
            parse_kib_after_prefix(status.lines(), "VmHWM:"),
            Some(123_456)
        );
    }

    #[test]
    fn a_present_but_unparsable_line_is_none_not_zero() {
        // Zero would be a real measurement and would sail through every
        // threshold; None is the honest answer.
        assert_eq!(
            parse_kib_after_prefix(["MemTotal:  \tkB"].into_iter(), "MemTotal:"),
            None
        );
        assert_eq!(
            parse_kib_after_prefix(["Nope: 1 kB"].into_iter(), "MemTotal:"),
            None
        );
    }
}
