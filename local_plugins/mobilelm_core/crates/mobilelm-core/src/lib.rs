//! Engine abstraction for mobileLM-rs, plus the device probe that decides which
//! backend is real.
//!
//! The two rules that shape this crate, both learned the hard way in the Flutter
//! app (`mobileLM-app/AGENTS.md`):
//!
//! 1. **Report the backend that actually ran, never the one that was requested.**
//!    A tier that silently fell back is a bug, and the only way to catch it is to
//!    make it impossible to construct an `Engine` whose `backend()` lies.
//! 2. **Accelerator decisions belong here, not in the UI.** Nothing above this
//!    crate may branch on SoC name, GPU brand, or a hardcoded allowlist. Memory
//!    decides, and the probe is where memory is read.

pub mod dynlib;
pub mod json;
pub mod plan;
pub mod probe;

/// Which compute backend an engine is running on.
///
/// Ordered by *preference*, not by declaration: `Npu` is the most preferred tier
/// and `Cpu` the guaranteed fallback. The `Ord` impl is written by hand because
/// the derived one orders the variants by declaration and would therefore rank
/// CPU above the NPU — a silent reversal of the fallback chain, which is the kind
/// of bug that only shows up as "it got slower and nobody knows why".
///
/// `Npu` exists in the enum even where the probe says it is unreachable, so that
/// "unreachable" is a *runtime answer* and not a missing variant.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Backend {
    /// Plain CPU, with the per-ISA-variant dispatch llama.cpp picks via HWCAP.
    Cpu,
    /// GPU through OpenCL / OpenGL ES (the LiteRT-LM GPU backend).
    Gpu,
    /// GPU through Vulkan (llama.cpp's ggml-vulkan backend).
    GpuVulkan,
    /// MediaTek NeuroPilot APU, reached through a vendor dispatch library.
    Npu,
}

impl PartialOrd for Backend {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Backend {
    /// `Npu < GpuVulkan < Gpu < Cpu`, matching [`Backend::LADDER`]. So `min()`
    /// is the tier to try first and `max()` is the one that always works.
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        fn rank(b: Backend) -> u8 {
            match b {
                Backend::Npu => 0,
                Backend::GpuVulkan => 1,
                Backend::Gpu => 2,
                Backend::Cpu => 3,
            }
        }
        rank(*self).cmp(&rank(*other))
    }
}

impl Backend {
    pub const LADDER: [Backend; 4] = [Backend::Npu, Backend::GpuVulkan, Backend::Gpu, Backend::Cpu];

    pub fn as_str(self) -> &'static str {
        match self {
            Backend::Cpu => "cpu",
            Backend::Gpu => "gpu",
            Backend::GpuVulkan => "gpu-vulkan",
            Backend::Npu => "npu",
        }
    }

    /// Accepts what the CLI and the settings UI pass around: `cpu`, `gpu`,
    /// `vulkan`, `npu`.
    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "cpu" => Some(Backend::Cpu),
            "gpu" | "opencl" | "opengl" => Some(Backend::Gpu),
            "vulkan" | "gpu-vulkan" | "vkan" => Some(Backend::GpuVulkan),
            "npu" | "apu" => Some(Backend::Npu),
            _ => None,
        }
    }
}

impl std::fmt::Display for Backend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// What the caller asked for. Deliberately not a promise: an implementation is
/// free to land on a lower tier, and must then say so in [`LoadReport`].
#[derive(Debug, Clone)]
pub struct EngineConfig {
    /// Path to a GGUF (`model.gguf`), a `.litertlm` AOT bundle, or an SD checkpoint.
    pub model_path: String,
    /// Path to the multimodal projector that pairs with a GGUF vision model.
    /// `None` for text-only. Reported as a capability bitmask after load, never
    /// assumed from the catalogue.
    pub mmproj_path: Option<String>,
    pub backend: Backend,
    /// Context window. `None` means "whatever the model was trained with",
    /// clamped to `llama_model_n_ctx_train()`. LiteRT-LM stays capped at 4096
    /// by its own driver regardless of what is asked for.
    pub n_ctx: Option<u32>,
    /// CPU threads. 4 is the measured optimum on the Edge 60 (4xA78 + 4xA55);
    /// 8 regresses because the A55s contend with the A78s.
    pub n_threads: Option<u32>,
}

/// What a load actually produced, as opposed to what was requested.
#[derive(Debug, Clone)]
pub struct LoadReport {
    /// The tier that was asked for.
    pub requested: Backend,
    /// The tier that is live. Equal to `requested` unless a fallback happened.
    pub actual: Backend,
    /// Why it differs, in one line, or `None` when it did not.
    pub fallback_reason: Option<String>,
    pub load_ms: u64,
    pub model_bytes: u64,
    /// 1 = vision, 2 = audio, 0 = text only.
    pub capabilities: u8,
    pub n_ctx: u32,
    /// Free-form notes worth keeping in a log: "dispatch lib found at …",
    /// "npu driver rejected by linker namespace", and so on.
    pub notes: Vec<String>,
}

impl LoadReport {
    /// True when the requested tier survived. Anything else is a silent
    /// downgrade and belongs in the log, loudly.
    pub fn is_exact(&self) -> bool {
        self.actual == self.requested
    }
}

#[derive(Debug, Clone)]
pub struct GenRequest {
    pub prompt: String,
    pub max_tokens: usize,
    /// Emit a token callback per piece, so the UI can stream and the harness can
    /// timestamp the first one.
    pub stream: bool,
}

#[derive(Debug, Clone, Default)]
pub struct GenOutcome {
    /// Wall time to the first emitted token. Zero when the model emitted nothing.
    pub ttft_ms: u64,
    pub prefill_tokens: u32,
    pub decode_tokens: u32,
    pub total_ms: u64,
}

impl GenOutcome {
    pub fn prefill_tps(&self) -> f64 {
        if self.prefill_tokens == 0 || self.ttft_ms == 0 {
            return 0.0;
        }
        self.prefill_tokens as f64 / (self.ttft_ms as f64 / 1000.0)
    }

    /// Decode throughput excludes TTFT: on a phone the prefill and the decode
    /// behave differently enough that averaging them hides which one regressed.
    pub fn decode_tps(&self) -> f64 {
        let decode_ms = self.total_ms.saturating_sub(self.ttft_ms);
        if self.decode_tokens == 0 || decode_ms == 0 {
            return 0.0;
        }
        self.decode_tokens as f64 / (decode_ms as f64 / 1000.0)
    }
}

/// A loaded model. `Send` because inference runs on a worker thread and the UI
/// owns the handle; deliberately not `Sync`, because no engine here is safe to
/// call from two threads at once and pretending otherwise is how the LiteRT-LM
/// C API gets corrupted.
pub trait Engine: Send {
    /// The tier that is actually live. Never the requested one.
    fn backend(&self) -> Backend;
    fn load_report(&self) -> &LoadReport;
    /// Which sampler the open conversation is actually using, when this engine
    /// has the notion. `None` for an engine that does not sample (llama.cpp reads
    /// its own GGUF sampler settings), and that is the answer — not a default.
    fn sampler_choice(&self) -> Option<&SamplerChoice> {
        None
    }
    fn generate(
        &mut self,
        req: &GenRequest,
        on_token: &mut dyn FnMut(&str),
    ) -> Result<GenOutcome, EngineError>;
    fn unload(&mut self);
}

/// Which sampler type the open conversation is actually sampling with.
///
/// The type is not a detail. It decides which of the knobs the API exposes are
/// consulted at all — on a `greedy` sampler a temperature of 0.8 and one of 0.2
/// are the same reply — so a runtime that does not implement the type the caller
/// asked for has not honoured the request, and the difference between the two
/// cases is invisible from the chat.
///
/// It exists because the v0.16.0 runtime refuses `kLiteRtLmSamplerTypeTopK`, the
/// type the app's own plugin requests: `UNIMPLEMENTED: Sampler type: 1 not
/// implemented yet.` The core now probes for a type the runtime does implement,
/// and this is how the substitution is reported instead of absorbed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SamplerChoice {
    /// What the caller asked for, by name. `"engine default"` when it asked for
    /// nothing at all.
    pub requested: &'static str,
    /// The type in force, or `None` when the engine's own default applies.
    pub actual: Option<&'static str>,
    /// True only when every knob the caller set is consulted by `actual`.
    pub full: bool,
}

impl SamplerChoice {
    /// One line, for a log. Deliberately says which knobs are ignored rather
    /// than reporting the type alone, because the type is the part nobody can
    /// act on and the ignored knobs are the part they can.
    pub fn describe(&self) -> String {
        match self.actual {
            None => format!(
                "sampler: the engine default is in use — {} has nothing to say about the \
                 temperature, top_k or top_p the app set",
                self.requested
            ),
            Some(actual) if self.full => {
                format!("sampler: {actual}, which consults every knob the app set")
            }
            Some(actual) => format!(
                "sampler: {actual}, substituted for {} — this runtime does not implement the \
                 type the app asked for, so not every knob it set is consulted",
                self.requested
            ),
        }
    }
}

#[derive(Debug)]
pub enum EngineError {
    /// The model file is missing, truncated, or not the format this engine takes.
    Model(String),
    /// The backend was asked for and is genuinely not there. Carries the probe's
    /// reason, because "NPU not available" on its own is unactionable.
    BackendUnavailable {
        backend: Backend,
        reason: String,
    },
    /// The engine is linked but this build has no implementation for it yet.
    NotImplemented(&'static str),
    Io(String),
    Runtime(String),
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EngineError::Model(m) => write!(f, "model: {m}"),
            EngineError::BackendUnavailable { backend, reason } => {
                write!(f, "backend {backend} unavailable: {reason}")
            }
            EngineError::NotImplemented(what) => write!(f, "not implemented: {what}"),
            EngineError::Io(m) => write!(f, "io: {m}"),
            EngineError::Runtime(m) => write!(f, "runtime: {m}"),
        }
    }
}

impl std::error::Error for EngineError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_round_trips_through_its_string_form() {
        for b in Backend::LADDER {
            assert_eq!(Backend::parse(b.as_str()), Some(b), "{b}");
        }
    }

    #[test]
    fn parse_accepts_the_aliases_the_ui_and_cli_actually_pass() {
        assert_eq!(Backend::parse("Vulkan"), Some(Backend::GpuVulkan));
        assert_eq!(Backend::parse(" opencl "), Some(Backend::Gpu));
        assert_eq!(Backend::parse("APU"), Some(Backend::Npu));
        assert_eq!(Backend::parse("cuda"), None);
    }

    #[test]
    fn ladder_starts_at_npu_and_ends_at_cpu() {
        assert_eq!(Backend::LADDER[0], Backend::Npu);
        assert_eq!(Backend::LADDER[Backend::LADDER.len() - 1], Backend::Cpu);
        // Ord must agree with LADDER order, or a sort silently reverses the
        // fallback chain. This is the assertion that catches a derived Ord.
        let mut sorted = Backend::LADDER;
        sorted.sort();
        assert_eq!(sorted, Backend::LADDER);
        assert_eq!(Backend::LADDER.iter().min(), Some(&Backend::Npu));
        assert_eq!(Backend::LADDER.iter().max(), Some(&Backend::Cpu));
    }

    #[test]
    fn decode_rate_excludes_ttft() {
        // 2 s of prefill, then 10 tokens in 1 s: 10 tok/s, not 3.3.
        let o = GenOutcome {
            ttft_ms: 2000,
            prefill_tokens: 40,
            decode_tokens: 10,
            total_ms: 3000,
        };
        assert!((o.decode_tps() - 10.0).abs() < 1e-9);
        assert!((o.prefill_tps() - 20.0).abs() < 1e-9);
    }

    #[test]
    fn a_fallback_is_never_reported_as_exact() {
        let r = LoadReport {
            requested: Backend::Npu,
            actual: Backend::GpuVulkan,
            fallback_reason: Some("dispatch lib absent".into()),
            load_ms: 1,
            model_bytes: 1,
            capabilities: 0,
            n_ctx: 4096,
            notes: vec![],
        };
        assert!(!r.is_exact());
    }
}
