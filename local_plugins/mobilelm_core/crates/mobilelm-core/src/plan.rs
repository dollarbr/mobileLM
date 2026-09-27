//! The acceleration ladder, in one place.
//!
//! This module exists because the rule was implemented twice. The Flutter app had
//! `planLiteRtTier` in `lib/services/acceleration.dart` and this crate had a
//! probe, and two implementations of one rule is two answers waiting to disagree
//! — usually on the device nobody tests on, in the one code path that decides
//! whether the user's model runs on the NPU.
//!
//! So the rule lives here, and Dart asks.
//!
//! What this does **not** do is decide whether the NPU is reachable. That is a
//! property of the device's linker namespace, and reading `/vendor/lib64` cannot
//! answer it — see `probe::npu_candidates` and the "Arm E" table in
//! `docs/BENCH.md`, where the one library an app may link does not resolve and the
//! ones that resolve are not exposed. The caller passes what it found; this turns
//! that into a choice.

use std::fmt;

use crate::json;

/// Which tier to ask the engine for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    Npu,
    Gpu,
    Cpu,
}

impl Tier {
    /// The name the LiteRT-LM C API expects. A wrong spelling does not error, it
    /// selects a different and slower path, which is why this is a single
    /// function rather than a `format!` at each call site.
    pub fn as_str(self) -> &'static str {
        match self {
            Tier::Npu => "npu",
            Tier::Gpu => "gpu",
            Tier::Cpu => "cpu",
        }
    }
}

impl fmt::Display for Tier {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// The outcome of the ladder, including the reason.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TierPlan {
    /// What the user asked for, before any reachability check.
    pub requested: Tier,
    /// What the app will ask the engine for.
    pub chosen: Tier,
    /// Why `chosen` is not `requested`, in one line, or `None`.
    pub reason: Option<String>,
    /// True when `chosen == requested`.
    pub exact: bool,
}

impl TierPlan {
    pub fn to_json(&self) -> String {
        format!(
            "{{\"requested\":{},\"chosen\":{},\"reason\":{},\"exact\":{}}}",
            json::escape(self.requested.as_str()),
            json::escape(self.chosen.as_str()),
            self.reason.as_deref().map_or("null".into(), json::escape),
            self.exact
        )
    }
}

/// What the user picked in settings.
///
/// `CpuSafe` is the explicit "do not touch the GPU" choice; `Auto` is the default
/// and means "use the best tier this device can actually reach". The distinction is
/// the user's, not ours, and a plan that quietly upgraded a CPU-safe request to
/// GPU would be the worst possible answer to it — a phone that heats up, a
/// battery that drains, and no setting that fixes it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    CpuSafe,
    Auto,
}

impl Mode {
    /// Accepts what the settings screen and the CLI actually pass.
    pub fn parse(s: &str) -> Mode {
        match s.trim().to_ascii_lowercase().as_str() {
            "cpu_safe" | "cpu-safe" | "cpu" | "safe" => Mode::CpuSafe,
            _ => Mode::Auto,
        }
    }
}

/// Decide the tier for a LiteRT-LM load.
///
/// This is the Rust half of what the app's `planLiteRtTier` did, and it is the
/// only copy now. `npu_available` is the caller's finding from the probe, not this
/// function's guess.
pub fn plan_litert_tier(mode: &str, force_cpu: bool, npu_available: bool) -> TierPlan {
    if force_cpu || Mode::parse(mode) == Mode::CpuSafe {
        return TierPlan {
            requested: Tier::Cpu,
            chosen: Tier::Cpu,
            reason: None,
            exact: true,
        };
    }
    if npu_available {
        return TierPlan {
            requested: Tier::Npu,
            chosen: Tier::Npu,
            reason: None,
            exact: true,
        };
    }
    // Auto, and no NPU. The GPU backend is OpenCL/GLES here — LiteRT-LM has no
    // Vulkan backend, so this is a different tier from llama.cpp's and the
    // measured llama.cpp conclusion about small models does not transfer to it.
    TierPlan {
        requested: Tier::Gpu,
        chosen: Tier::Gpu,
        reason: Some("no NPU driver reachable on this device".into()),
        exact: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_cpu_safe_request_is_never_upgraded() {
        // The one property that must not regress: whatever the device offers,
        // "CPU safe" means CPU. A plan that returns GPU here makes the phone hot
        // and the setting useless, and neither is visible in a log.
        for npu in [true, false] {
            for mode in ["cpu_safe", "cpu-safe", "CPU", "safe", "cpu"] {
                let p = plan_litert_tier(mode, false, npu);
                assert_eq!(p.chosen, Tier::Cpu, "{mode} npu={npu}");
                assert!(p.exact, "{mode} npu={npu}");
            }
        }
    }

    #[test]
    fn the_force_flag_beats_everything_including_a_reachable_npu() {
        let p = plan_litert_tier("gpu_fast", true, true);
        assert_eq!(p.chosen, Tier::Cpu);
        assert!(p.exact, "the user asked for CPU and got CPU");
    }

    #[test]
    fn auto_uses_the_npu_only_when_one_is_reachable() {
        let with = plan_litert_tier("gpu_fast", false, true);
        assert_eq!(with.chosen, Tier::Npu);
        assert!(with.exact);

        let without = plan_litert_tier("gpu_fast", false, false);
        assert_eq!(without.chosen, Tier::Gpu);
        assert!(
            !without.exact,
            "asked for the best tier, got the second best"
        );
        assert!(without.reason.is_some(), "a downgrade must say why");
    }

    #[test]
    fn an_unrecognised_mode_is_auto_not_cpu() {
        // A typo in a settings key must not silently pin the user to CPU. It
        // falls to the default, which is the behaviour that can still use the
        // accelerator, and it is visible as a downgrade note if it costs them.
        assert_eq!(plan_litert_tier("", false, false).chosen, Tier::Gpu);
        assert_eq!(plan_litert_tier("gup_fsat", false, false).chosen, Tier::Gpu);
    }

    #[test]
    fn tier_names_are_the_ones_the_c_api_expects() {
        // A wrong spelling is not an error; it picks a different, slower backend.
        assert_eq!(Tier::Cpu.as_str(), "cpu");
        assert_eq!(Tier::Gpu.as_str(), "gpu");
        assert_eq!(Tier::Npu.as_str(), "npu");
    }

    #[test]
    fn the_plan_serialises_to_something_the_dart_side_can_read() {
        let p = plan_litert_tier("gpu_fast", false, false);
        assert_eq!(
            p.to_json(),
            r#"{"requested":"gpu","chosen":"gpu","reason":"no NPU driver reachable on this device","exact":false}"#
        );
        let safe = plan_litert_tier("cpu_safe", false, false);
        assert_eq!(
            safe.to_json(),
            r#"{"requested":"cpu","chosen":"cpu","reason":null,"exact":true}"#
        );
    }
}
