#include <jni.h>
#include <string>
#include <vector>
#include <atomic>
#include <algorithm>
#include <ctime>
#include <cstring>
#include <cstdarg>
#include <fstream>
#include <chrono>
#include <mutex>
#include <deque>
#include <dlfcn.h>
#include <android/log.h>
#include "llama.cpp/include/llama.h"
#include "gguf.h"
#include "llama.cpp/ggml/include/ggml-backend.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#define LOG_TAG "LlamaJNI"

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static const llama_vocab* g_vocab = nullptr;
static llama_sampler* g_sampler = nullptr;
static std::atomic<bool> g_stop_flag{false};
// Serialises generation against teardown.
//
// nativeGenerate blocks inside llama_decode for as long as a prefill takes,
// and the Kotlin side frees the model from the main thread when the Flutter
// engine detaches. Coroutine cancellation cannot interrupt a JNI call that is
// already running, so without this the free ran underneath a live decode:
// "Scudo ERROR: invalid chunk state when deallocating" in llama_free.
static std::mutex g_ctx_mutex;
static int g_n_past = 0;  // Track the number of tokens already in KV cache
static std::mutex g_load_log_mutex;
static std::string g_load_error;
static bool g_capture_load_error = false;

// Multimodal state. g_mtmd holds the projector (the mmproj GGUF); it is a
// separate model from g_model and is loaded on its own.
static mtmd_context* g_mtmd = nullptr;

// Media queued by nativeSetMedia and consumed by the next nativeGenerate.
// Passing the paths through a global rather than widening nativeGenerate's
// already 18-argument signature -- the generation entry point is stateful
// anyway (g_model, g_ctx, g_n_past), so this follows the file's own grain.
static std::vector<std::string> g_pending_media;

// Everything ggml and llama.cpp print, kept for the Dart side to drain.
//
// The in-app log only ever saw Dart `print()`, so the layer that actually
// explains a bad load -- backend selection, layer offload, buffer allocation,
// Vulkan errors -- was invisible without a cable. This ring makes it
// reachable. It is polled rather than pushed because androidLlamaLog runs on
// llama.cpp worker threads, and attaching those to the JVM to call back into
// Dart mid-inference is a far worse trade than a 1s poll.
static std::mutex g_log_ring_mutex;
static std::deque<std::string> g_log_ring;
static constexpr size_t kLogRingMax = 600;

static void pushLogRing(ggml_log_level level, const char* text) {
    const char* tag = level >= GGML_LOG_LEVEL_ERROR
        ? "ERROR"
        : level == GGML_LOG_LEVEL_WARN ? "WARNING" : "INFO";
    std::string line;
    line.reserve(16 + strlen(text));
    // GGML_LOG_LEVEL_CONT continues the previous line, so glue it on instead
    // of emitting a fragment with its own level tag.
    std::lock_guard<std::mutex> lock(g_log_ring_mutex);
    if (level == GGML_LOG_LEVEL_CONT && !g_log_ring.empty()) {
        g_log_ring.back().append(text);
    } else {
        line.append(tag).append("\t").append(text);
        g_log_ring.push_back(std::move(line));
    }
    std::string& last = g_log_ring.back();
    while (!last.empty() && (last.back() == '\n' || last.back() == '\r')) {
        last.pop_back();
    }
    // A bare newline leaves nothing but the tag and its separator: drop it
    // rather than pad the log with blank lines.
    const size_t tab = last.find('\t');
    if (tab == std::string::npos || tab + 1 >= last.size()) {
        g_log_ring.pop_back();
    }
    while (g_log_ring.size() > kLogRingMax) g_log_ring.pop_front();
}

// This wrapper's own messages -- GPU detection, model and projector paths,
// load outcome -- used to exist only in logcat, which is exactly the set the
// in-app log most needs. Route them through the ring as well.
static void logRingf(ggml_log_level level, int priority, const char* fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    __android_log_write(priority, LOG_TAG, buf);
    pushLogRing(level, buf);
}

#define LOGI(...) logRingf(GGML_LOG_LEVEL_INFO, ANDROID_LOG_INFO, __VA_ARGS__)
#define LOGE(...) logRingf(GGML_LOG_LEVEL_ERROR, ANDROID_LOG_ERROR, __VA_ARGS__)

static void androidLlamaLog(ggml_log_level level, const char* text, void*) {
    if (!text) return;
    pushLogRing(level, text);

    const int priority = level >= GGML_LOG_LEVEL_ERROR
        ? ANDROID_LOG_ERROR
        : level == GGML_LOG_LEVEL_WARN
            ? ANDROID_LOG_WARN
            : level == GGML_LOG_LEVEL_DEBUG
                ? ANDROID_LOG_DEBUG
                : ANDROID_LOG_INFO;
    __android_log_write(priority, LOG_TAG, text);

    std::lock_guard<std::mutex> lock(g_load_log_mutex);
    if (!g_capture_load_error) return;
    if (level == GGML_LOG_LEVEL_ERROR) {
        g_load_error.assign(text);
    } else if (level == GGML_LOG_LEVEL_CONT && !g_load_error.empty()) {
        g_load_error.append(text);
    }
    if (g_load_error.size() > 4096) {
        g_load_error.erase(0, g_load_error.size() - 4096);
    }
}

static std::string consumeLoadError() {
    std::lock_guard<std::mutex> lock(g_load_log_mutex);
    g_capture_load_error = false;
    while (!g_load_error.empty() &&
           (g_load_error.back() == '\n' || g_load_error.back() == '\r')) {
        g_load_error.pop_back();
    }
    return g_load_error;
}

static void throwLoadError(JNIEnv* env, const std::string& message) {
    LOGE("%s", message.c_str());
    jclass exception = env->FindClass("java/lang/RuntimeException");
    env->ThrowNew(exception, message.c_str());
}

// ---------------------------------------------------------------------------
// Encoder models: BERT, ModernBERT, JinaBERT, NomicBERT, NeoBERT, EuroBERT
// and the embedding families. These do not generate, so nothing above this
// point applies to them — they pool a sequence into one vector.
// ---------------------------------------------------------------------------

// The pooling type is declared by the model, in `<arch>.pooling_type`
// (llama-model.cpp reads the very same key while loading). Iterating the
// metadata rather than assembling the key from an architecture name is what
// makes this work for every encoder family without a list to keep in sync —
// and a list is exactly what goes stale when llama.cpp adds an architecture.
//
// It is also the property that makes detection trustworthy here. A classifier
// that says what it is *in the file* cannot lie the way a runtime can: the
// LiteRT sampler reported a non-NULL pointer for a type its runtime does not
// implement, and the refusal only arrived at generation time. A GGUF's
// pooling_type is read before anything is allocated.
static bool model_declared_pooling(const llama_model* model, enum llama_pooling_type& out) {
    out = LLAMA_POOLING_TYPE_NONE;
    static const char kSuffix[] = ".pooling_type";
    const size_t kSuffixLen = sizeof(kSuffix) - 1;

    const int32_t n_keys = llama_model_meta_count(model);
    char key[256] = {0};
    char val[64]  = {0};
    for (int32_t i = 0; i < n_keys; i++) {
        if (llama_model_meta_key_by_index(model, i, key, sizeof(key) - 1) <= 0) continue;
        const std::string k(key);
        if (k.size() <= kSuffixLen) continue;
        if (k.compare(k.size() - kSuffixLen, kSuffixLen, kSuffix) != 0) continue;
        if (llama_model_meta_val_str_by_index(model, i, val, sizeof(val) - 1) <= 0) {
            return false;
        }
        out = static_cast<enum llama_pooling_type>(std::atoi(val));
        return true;
    }
    return false;
}

// Encoder-only architectures, for the case where the GGUF does not say what it is.
//
// The list is the set of encoder-only architectures in `llama-arch.cpp`, spelled
// exactly as that file spells them. That exactness is not pedantry: this list said
// `modernbert` and `llama-arch.cpp` says `modern-bert`, so
// `gte-reranker-modernbert-base` — 150 M, `cls.output.weight` e `cls.norm.weight`
// no lugar certo, o modelo de reranker mais bem formado que apareceu — carregou e
// respondia `/v1/chat` sem poolar nada. Um hífen faltando e o sintoma é o mesmo
// de um modelo quebrado.
//
// Because that will happen again, the list is only a **veto**, never the gate.
// `model_has_classification_head` is the gate: without a head in the file there
// is no logit to return, and llama.cpp would hand back one float of a pooled
// hidden state instead. So a name missing from `kEncoders` now leaves a working
// model un-inferred — it stays a generation model and `/v1/rerank` refuses with a
// message — where before it could have inferred RANK on a model that cannot
// produce a score. The failure direction is what matters: the list can only be
// too short, never too permissive.
static bool arch_is_encoder(const llama_model* model) {
    // `general.architecture` straight out of the metadata, which is the
    // canonical spelling (`llama-arch.cpp:166`). Not `llama_model_desc`: that
    // returns a human sentence built for a model card, and matching a prefix of
    // an English phrase is a way to be wrong in two languages.
    char arch[128] = {0};
    const int32_t n =
        llama_model_meta_val_str(model, "general.architecture", arch, sizeof(arch) - 1);
    if (n <= 0) return false;
    const std::string a(arch);

    static const char* kEncoders[] = {
        "bert",         "modern-bert",    "nomic-bert",   "nomic-bert-moe",
        "neo-bert",     "jina-bert-v2",   "jina-bert-v3", "eurobert",
    };
    for (const char* e : kEncoders) {
        if (a == e) return true;
    }
    return false;
}

// Whether the file carries a classification head, i.e. whether a logit exists at
// all. `llama-graph.cpp:3753` applies `cls_out` only if it is non-null, and the
// loader fills it only for the architectures that ask for it — `bert`,
// `modern-bert`, `neo-bert`, `qwen3` do, and `jina-bert-v2`, `jina-bert-v3`,
// `nomic-bert` and `eurobert` do not.
//
// This is not hypothetical, and the file that proved it is the reason this
// function exists. `jina-reranker-v1-tiny-en` is a genuine cross-encoder — the
// model card's own example ranks correctly, and through this app it scored
// NDCG@10 0.9981 on a graded set — but its GGUF has no `cls.output.*`. What
// llama.cpp computes instead is `tanh(cls · h[0] + cls_b)`, where `cls` is the
// `nn.Linear(384, 1)` the conversion *did* keep, and the 384×384 `pooler.dense`
// that `modeling_bert.py` applies before it was dropped. The result is a number
// in (-1, 1) that correlates with relevance and is not a score: 40+ measurements
// on the device never left (-1, 1), not even for a document identical to the
// query. `sigmoid` of it spans 0.496–0.561 where a calibrated reranker wants
// 0.005–0.995. So the ordering was good and the number was meaningless, and only
// a model that admits it has no head can be refused up front.
//
// Read with the ggml reader, not `llama_model_meta_val_str`: that enumerates the
// **key-value** pairs, and a tensor name is not a key-value pair. Asking it for
// `cls.output.weight` returns 0 for every model, which is how
// `gte-reranker-modernbert-base` — the best-formed reranker available, with the
// head right there in the file — was refused with "no classification head".
static bool gguf_has_tensor(const char* path, const char* name) {
    if (!path || !*path) return false;
    // `gguf_init_from_file` recebe a struct por valor, não por ponteiro.
    gguf_init_params params = {};
    params.no_alloc = true;
    gguf_context* ctx = gguf_init_from_file(path, params);
    if (!ctx) {
        LOGE("Could not reopen %s to look for tensor '%s'; treating it as absent",
             path, name);
        return false;
    }
    const bool found = gguf_find_tensor(ctx, name) >= 0;
    gguf_free(ctx);
    return found;
}

static bool model_has_classification_head(const char* model_path) {
    return gguf_has_tensor(model_path, "cls.output.weight");
}

// Whether a pooling type can be *inferred* for a model that declares none.
//
// A reranker is the one case worth inferring, and it is inferred as RANK because
// that is what the architecture is for. llama.cpp's own `--rerank` flag does the
// same thing (common/arg.cpp:3484: `params.embedding = true; params.pooling_type
// = LLAMA_POOLING_TYPE_RANK`), and the guard below is theirs, not mine — the
// same three things common.cpp:1483 requires before it will rerank: a BOS, and
// then either an EOS, a SEP, or a `rerank` chat template. A vocab with none of
// those has no way to express a document/query boundary, so a score over it
// would be a number about nothing.
//
// Returning false leaves the model as a generation model, which is the safe
// direction: it stays usable for chat, and `/v1/embeddings` refuses with a
// message instead of returning a wrong vector.
static bool infer_pooling(const llama_model* model, const char* model_path,
                          enum llama_pooling_type& out) {
    out = LLAMA_POOLING_TYPE_NONE;
    if (!arch_is_encoder(model)) return false;

    // The gate, and the only hard requirement. A head means llama.cpp can reach a
    // logit; without one it cannot, whatever the architecture claims to be.
    if (!model_has_classification_head(model_path)) {
        LOGE("Encoder architecture with no cls.output.weight in the GGUF: this "
             "conversion has no classification head, so there is no logit to "
             "return. llama.cpp would hand back one float of a pooled hidden "
             "state instead — a number in (-1, 1) that ranks plausibly and "
             "means nothing. Leaving it as a generation model.");
        return false;
    }

    const llama_vocab* vocab = llama_model_get_vocab(model);
    if (!vocab) return false;

    const bool has_bos = llama_vocab_bos(vocab) != LLAMA_TOKEN_NULL;
    const bool has_eos = llama_vocab_eos(vocab) != LLAMA_TOKEN_NULL;
    const bool has_sep = llama_vocab_sep(vocab) != LLAMA_TOKEN_NULL;
    const bool has_rerank_prompt = llama_model_chat_template(model, "rerank") != nullptr;
    if (!has_bos || (!has_eos && !has_sep && !has_rerank_prompt)) {
        LOGE("Encoder architecture with a classification head but no usable "
             "boundary (bos=%d eos=%d sep=%d rerank_prompt=%d); leaving it as a "
             "generation model",
             (int) has_bos, (int) has_eos, (int) has_sep, (int) has_rerank_prompt);
        return false;
    }

    // `n_cls_out` is deliberately not consulted. jina-reranker-v1-tiny-en reports
    // `n_cls_out: 1` and gte-reranker-modernbert-base reports 1 via
    // `classifier.output_labels = ["LABEL_0"]`; both agree, and neither is what
    // decides this. The head's presence in the file is.
    out = LLAMA_POOLING_TYPE_RANK;
    LOGI("No <arch>.pooling_type in the GGUF, but the architecture is an encoder "
         "with a classification head and a usable boundary; treating it as a "
         "reranker (RANK)");
    return true;
}

static const char* pooling_name(enum llama_pooling_type p) {
    switch (p) {
        case LLAMA_POOLING_TYPE_NONE: return "none";
        case LLAMA_POOLING_TYPE_MEAN: return "mean";
        case LLAMA_POOLING_TYPE_CLS:  return "cls";
        case LLAMA_POOLING_TYPE_LAST: return "last";
        case LLAMA_POOLING_TYPE_RANK: return "rank";
        default:                      return "unspecified";
    }
}

// How many floats llama_get_embeddings_seq hands back for the loaded model.
//
// The header says RANK returns float[n_cls_out] and everything else
// float[n_embd]; examples/embedding/embedding.cpp instead reads n_embd and
// keeps min(n_embd, n_cls_out). They agree for a reranker with a class head
// (n_cls_out == 1) and disagree for a multi-class classifier, where the header
// describes the buffer and the example does not — so the header wins, clamped by
// n_embd because reading past what was written is not a thing to do.
//
// The case they both get wrong is the one the device found:
// **jina-reranker-v1-tiny-en reports `n_cls_out == 0` while being a RANK
// model.** Neither the header nor the example has an answer, and taking
// n_embd here would return 384 floats for a one-element score — a plausible
// vector, wrong, and the first 383 of it is whatever follows in memory. A RANK
// model with no declared class count has exactly one output by definition, so
// that is what it gets.
static int32_t pooled_output_len(const llama_model* model, enum llama_pooling_type pooling) {
    const int32_t n_embd = llama_model_n_embd_out(model);
    if (pooling == LLAMA_POOLING_TYPE_RANK) {
        const int32_t n_cls = static_cast<int32_t>(llama_model_n_cls_out(model));
        if (n_cls <= 0) return 1;
        return std::min(n_embd, n_cls);
    }
    return n_embd;
}

// Helper function to validate UTF-8 strings
static bool isValidUTF8(const char* str, size_t len) {
    if (!str) return false;
    
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(str);
    size_t i = 0;
    
    while (i < len) {
        unsigned char c = bytes[i];
        
        // ASCII character (0xxxxxxx)
        if ((c & 0x80) == 0) {
            i++;
            continue;
        }
        
        // Multi-byte sequence start (110xxxxx, 1110xxxx, or 11110xxx)
        int num_bytes = 0;
        if ((c & 0xE0) == 0xC0) {
            num_bytes = 2; // 110xxxxx
        } else if ((c & 0xF0) == 0xE0) {
            num_bytes = 3; // 1110xxxx
        } else if ((c & 0xF8) == 0xF0) {
            num_bytes = 4; // 11110xxx
        } else {
            // Invalid first byte
            return false;
        }
        
        // Check if we have enough bytes left
        if (i + num_bytes > len) {
            return false;
        }
        
        // Check continuation bytes (10xxxxxx)
        for (int j = 1; j < num_bytes; j++) {
            if ((bytes[i + j] & 0xC0) != 0x80) {
                return false;
            }
        }
        
        // Check for overlong encodings and invalid code points
        if (num_bytes == 2) {
            // Overlong encoding of ASCII character
            if ((c & 0x1E) == 0) return false;
        } else if (num_bytes == 3) {
            // Invalid surrogate halves (U+D800-U+DFFF)
            if (c == 0xED && (bytes[i + 1] & 0x20) == 0x20) return false;
            // Overlong encoding
            if (c == 0xE0 && (bytes[i + 1] & 0x20) == 0) return false;
        } else if (num_bytes == 4) {
            // Out of Unicode range (> U+10FFFF)
            if (c > 0xF4) return false;
            // Overlong encoding
            if (c == 0xF0 && (bytes[i + 1] & 0x30) == 0) return false;
            // Invalid code points (> U+10FFFF)
            if (c == 0xF4 && bytes[i + 1] > 0x8F) return false;
        }
        
        i += num_bytes;
    }
    
    return true;
}

// Helper function to sanitize UTF-8 strings
static std::string sanitizeUTF8(const char* str, size_t len) {
    if (!str || len == 0) return "";
    
    // First try to validate as-is
    if (isValidUTF8(str, len)) {
        return std::string(str, len);
    }
    
    // If invalid, create a sanitized version
    std::string result;
    result.reserve(len);
    
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(str);
    size_t i = 0;
    
    while (i < len) {
        unsigned char c = bytes[i];
        
        // ASCII character (0xxxxxxx)
        if ((c & 0x80) == 0) {
            result += c;
            i++;
            continue;
        }
        
        // Multi-byte sequence start
        int num_bytes = 0;
        if ((c & 0xE0) == 0xC0) {
            num_bytes = 2;
        } else if ((c & 0xF0) == 0xE0) {
            num_bytes = 3;
        } else if ((c & 0xF8) == 0xF0) {
            num_bytes = 4;
        } else {
            // Invalid first byte, replace with replacement character
            result += "\xEF\xBF\xBD"; // 
            i++;
            continue;
        }
        
        // Check if we have enough bytes left
        if (i + num_bytes > len) {
            result += "\xEF\xBF\xBD"; // 
            break;
        }
        
        // Extract the sequence
        std::string seq(reinterpret_cast<const char*>(bytes + i), num_bytes);
        
        // Validate the sequence
        if (isValidUTF8(seq.c_str(), num_bytes)) {
            result += seq;
        } else {
            // Invalid sequence, replace with replacement character
            result += "\xEF\xBF\xBD"; // 
        }
        
        i += num_bytes;
    }
    
    return result;
}

// Installed here rather than in nativeLoadModel so that everything ggml says
// before the first load -- backend registration, device enumeration, the
// Vulkan probe in nativeDetectGpu -- reaches the ring too. Those lines are
// what explain a bad accelerator choice, and they were being lost.
extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    llama_log_set(androidLlamaLog, nullptr);
    (void)vm;
    return JNI_VERSION_1_6;
}

// Register the backends, choosing the CPU one the silicon can actually run.
//
// GGML_CPU_ALL_VARIANTS builds libggml-cpu-android_*.so once per ARM feature
// set. ggml's own picker, ggml_backend_load_all(), finds them by listing a
// directory, which is no use here: with the default packaging the libraries
// are never unpacked out of the APK, so there is no directory to list. Android
// resolves a bare soname through the app's library path either way, unpacked
// or not, so the candidates are named rather than discovered.
//
// The choice itself is still ggml's. Each variant exports ggml_backend_score(),
// which reads getauxval(AT_HWCAP) and returns 0 when the CPU is missing any
// feature that variant was compiled for -- so a variant that would SIGILL
// scores zero and is never registered, and the richest usable one wins. That
// is the whole reason the ARM baseline can stay at the NDK default.
static void loadBackendsOnce() {
    static std::once_flag once;
    std::call_once(once, [] {
        static const char* const cpu_variants[] = {
            "libggml-cpu-android_armv8.0_1.so",
            "libggml-cpu-android_armv8.2_1.so",
            "libggml-cpu-android_armv8.2_2.so",
            "libggml-cpu-android_armv8.6_1.so",
            "libggml-cpu-android_armv9.0_1.so",
            "libggml-cpu-android_armv9.2_1.so",
            "libggml-cpu-android_armv9.2_2.so",
        };

        const char* best = nullptr;
        int best_score = 0;
        for (const char* name : cpu_variants) {
            void* handle = dlopen(name, RTLD_NOW | RTLD_LOCAL);
            if (!handle) {
                LOGI("CPU variant %s not present: %s", name, dlerror());
                continue;
            }
            auto score_fn = (int (*)(void)) dlsym(handle, "ggml_backend_score");
            const int score = score_fn ? score_fn() : 0;
            LOGI("CPU variant %s scores %d", name, score);
            if (score > best_score) {
                best_score = score;
                best = name;
            }
            dlclose(handle);
        }

        // Fall back to the single-variant name so a build without
        // GGML_CPU_ALL_VARIANTS, or an architecture with no variants defined,
        // still gets a CPU backend instead of none.
        if (!best) {
            best = "libggml-cpu.so";
            LOGI("No scored CPU variant; falling back to %s", best);
        }
        if (!ggml_backend_load(best)) {
            LOGE("Failed to register the CPU backend from %s", best);
        } else {
            LOGI("CPU backend: %s (score %d)", best, best_score);
        }

        // Loaded unconditionally so nativeDetectGpu can report the GPU even
        // when the user has chosen CPU. Whether a model uses it is decided per
        // load by n_gpu_layers and model_params.devices, not here.
        if (!ggml_backend_load("libggml-vulkan.so")) {
            LOGI("Vulkan backend unavailable on this device");
        }
    });
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeDetectGpu(
        JNIEnv* env, jobject /* this */, jlongArray outStats) {

    // Zero out output array as safe default (-1 = unknown)
    jlong defaults[2] = {-1L, -1L};
    env->SetLongArrayRegion(outStats, 0, 2, defaults);

    // Ask ggml what it actually registered rather than opening a Vulkan
    // instance of our own: the backend that will run the layers is the only
    // authority on whether the offload is possible, and a device ggml did not
    // register is one llama_model_load could not use even if Vulkan answered.
    // Backends are dynamically loaded shared objects rather than statically
    // registered, so without this the registry is empty and no device is found.
    loadBackendsOnce();

    const size_t n_devices = ggml_backend_dev_count();
    LOGI("nativeDetectGpu: %zu device(s) registered", n_devices);
    for (size_t i = 0; i < n_devices; i++) {
        ggml_backend_dev_t dev = ggml_backend_dev_get(i);
        if (!dev) {
            continue;
        }
        const enum ggml_backend_dev_type type = ggml_backend_dev_type(dev);
        LOGI("nativeDetectGpu:   device %zu: %s (type %d)", i,
             ggml_backend_dev_name(dev), (int)type);
        // IGPU is not a lesser GPU, it is the only kind a phone has: ggml sorts
        // the Mali here because it shares system memory rather than owning a
        // heap. Accepting only _GPU rejects every Android device there is.
        if (type != GGML_BACKEND_DEVICE_TYPE_GPU &&
            type != GGML_BACKEND_DEVICE_TYPE_IGPU) {
            continue;
        }

        size_t free_mem = 0;
        size_t total_mem = 0;
        ggml_backend_dev_memory(dev, &free_mem, &total_mem);

        // outStats[0] stays -1: ggml does not expose the Vulkan API version and
        // nothing downstream reads it. outStats[1] is what sizes the offload --
        // on a UMA phone that is system memory, not a private heap.
        jlong stats[2] = {-1L, (jlong)total_mem};
        env->SetLongArrayRegion(outStats, 0, 2, stats);

        const char* name = ggml_backend_dev_description(dev);
        LOGI("nativeDetectGpu: %s, %zu MiB total", name ? name : "GPU",
             total_mem / (1024 * 1024));
        return env->NewStringUTF(name ? name : "GPU");
    }

    LOGI("nativeDetectGpu: no GPU backend registered");
    return nullptr;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeLoadModel(
    JNIEnv* env, jobject thiz,
    jstring path, jlong n_threads, jlong ctx_size, jlong n_gpu_layers,
    jobject progress_callback) {
    
    if (!path) {
        throwLoadError(env, "GGUF model path is missing");
        return;
    }

    const char* model_path = env->GetStringUTFChars(path, nullptr);
    if (!model_path) {
        throwLoadError(env, "Could not read the GGUF model path");
        return;
    }
    LOGI("Loading model: %s", model_path);
    // Uma cópia, porque `model_path` é devolvido ao JNI logo depois de
    // `llama_model_load_from_file` e a detecção de encoder precisa reabrir o
    // arquivo para ver se a cabeça de classificação está lá. Usar o ponteiro
    // depois do `ReleaseStringUTFChars` é use-after-free — e um use-after-free
    // que passa: a string é curta, o allocator devolve o mesmo bloco e o teste
    // passa com lixo que por acaso é o caminho certo.
    const std::string model_path_str(model_path);

    std::ifstream model_file(model_path, std::ios::binary | std::ios::ate);
    if (!model_file) {
        env->ReleaseStringUTFChars(path, model_path);
        throwLoadError(env, "GGUF model file is missing or unreadable");
        return;
    }
    const std::streamsize model_size = model_file.tellg();
    if (model_size < 4) {
        env->ReleaseStringUTFChars(path, model_path);
        throwLoadError(env, "GGUF model file is empty or incomplete");
        return;
    }
    model_file.seekg(0, std::ios::beg);
    char magic[4] = {};
    model_file.read(magic, sizeof(magic));
    if (!model_file || std::memcmp(magic, "GGUF", sizeof(magic)) != 0) {
        env->ReleaseStringUTFChars(path, model_path);
        throwLoadError(env, "Invalid GGUF model header");
        return;
    }
    model_file.close();

    // Same hazard as teardown: replacing g_model/g_ctx while a generation
    // still holds them is a use-after-free.
    g_stop_flag = true;
    std::lock_guard<std::mutex> ctx_lock(g_ctx_mutex);
    g_stop_flag = false;

    // Model parameters
    loadBackendsOnce();

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = n_gpu_layers;

    // "CPU" in Settings has to mean the CPU is the only device the model knows
    // about, not merely that no layer is offloaded to the other one.
    //
    // With devices left at NULL llama.cpp enumerates every backend it was built
    // with, so Vulkan joined ggml_backend_sched even at n_gpu_layers = 0.
    // Zeroing op_offload stopped the weights being shipped to the GPU per op,
    // but the second backend stayed in the scheduler and every batched decode
    // still paid to re-plan and re-allocate across it. Measured on this device:
    // a batched decode cost ~5.5 s before the first token of work, on top of
    // ~25 ms/token -- 55 tokens took 7.1 s, 244 took 12.1 s. Single-token
    // decode, whose graph shape never changes, cost 133 ms and showed none of
    // it. An empty (NULL-terminated) device list leaves model->devices empty,
    // which is the documented way to ask for CPU only.
    static ggml_backend_dev_t cpu_only[] = { nullptr };
    if (n_gpu_layers == 0) {
        model_params.devices = cpu_only;
        LOGI("Device list restricted to the CPU");
    }

    llama_log_set(androidLlamaLog, nullptr);
    {
        std::lock_guard<std::mutex> lock(g_load_log_mutex);
        g_load_error.clear();
        g_capture_load_error = true;
    }
    
    // Load model
    g_model = llama_model_load_from_file(model_path, model_params);
    env->ReleaseStringUTFChars(path, model_path);
    
    if (!g_model) {
        const std::string detail = consumeLoadError();
        const std::string message = detail.empty()
            ? "Failed to load GGUF model; check model compatibility and available RAM"
            : "Failed to load GGUF model: " + detail;
        throwLoadError(env, message);
        return;
    }
    consumeLoadError();

    // Context parameters with memory optimizations for low-end devices
    llama_context_params ctx_params = llama_context_default_params();

    // Ask for what the caller wants, but never for more than the model was
    // trained on: Settings lets any number be typed (a recurrent model such as
    // RWKV keeps a fixed-size state, so a big number there costs nothing), and
    // this is the one place every load funnels through, so the ceiling belongs
    // here rather than in the UI. llama_n_ctx() reports the effective value
    // back, which is what the context-usage bar already reads.
    const int n_ctx_train = llama_model_n_ctx_train(g_model);
    if (n_ctx_train > 0 && ctx_size > n_ctx_train) {
        LOGI("Requested context %d exceeds the model's trained context %d — using %d",
             (int)ctx_size, n_ctx_train, n_ctx_train);
        ctx_size = n_ctx_train;
    }
    ctx_params.n_ctx = ctx_size;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;
    
    // Memory optimization: reduce memory usage by limiting batch processing
    ctx_params.n_batch = 512;  // Process smaller batches to reduce memory spikes

    // An encoder model declares a pooling type in its own metadata. When it
    // does, this context is for pooling a sequence into one vector rather than
    // for generating, and two settings have to follow from that:
    //
    // - `embeddings` has to be on, or llama_get_embeddings_seq returns NULL and
    //   every read below comes back empty for a reason that looks like a bug.
    // - `n_batch` has to hold the whole sequence. Pooling happens once, over
    //   the batch as given; a sequence split across ubatches is pooled
    //   differently, and unlike generation there is no chunking path to fall
    //   back on for an encoder-only model. 2048 covers any cross-encoder input
    //   worth sending, and an encoder uses no KV cache, so a large ubatch costs
    //   activation memory and not a growing cache.
    enum llama_pooling_type pooling = LLAMA_POOLING_TYPE_NONE;
    bool is_encoder = model_declared_pooling(g_model, pooling);
    if (!is_encoder) {
        // The GGUF says nothing. For an encoder architecture that is a gap in
        // the file, not an absence of the capability — see infer_pooling. The
        // declared path stays first, so a model that knows what it is is never
        // second-guessed.
        is_encoder = infer_pooling(g_model, model_path_str.c_str(), pooling);
    }
    if (is_encoder) {
        ctx_params.embeddings   = true;
        ctx_params.pooling_type = pooling;
        ctx_params.n_batch      = std::max<uint32_t>(ctx_params.n_batch, 2048u);
        LOGI("Encoder model: pooling=%s, n_cls_out=%u, n_embd_out=%d",
             pooling_name(pooling),
             (unsigned) llama_model_n_cls_out(g_model),
             llama_model_n_embd_out(g_model));
    }

    // With the weights in system RAM, let them be computed there too.
    //
    // ggml's scheduler has a second, separate offload path from n_gpu_layers:
    // ggml_backend_sched_backend_id_from_cur() hands any op whose batch is at
    // least GGML_OP_OFFLOAD_MIN_BATCH (32) to a higher-priority backend that
    // claims it, even when the weights live on the host. Registering Vulkan is
    // enough to trigger it, so "CPU" in Settings never was CPU: decode (batch 1)
    // stayed put, but every prefill (batch 244 measured) shipped each layer's
    // weights over the bus to the GPU and back, once per op. Measured on a
    // Mali-G615: 244 text tokens took 63.8s to prefill, 3.8 tok/s -- slower than
    // this build decodes (4.3 tok/s), when prefill should beat decode severalfold.
    // It also pins the GPU, which is why generating froze the whole UI.
    if (n_gpu_layers == 0) {
        ctx_params.op_offload = false;
        LOGI("op_offload disabled: weights are on the host");
    }

    // Create context (using new API)
    g_ctx = llama_init_from_model(g_model, ctx_params);
    if (!g_ctx) {
        llama_model_free(g_model);
        g_model = nullptr;
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to create context");
        return;
    }

    // Get vocab for tokenization
    g_vocab = llama_model_get_vocab(g_model);
    LOGI("Vocab initialized: %p", (void*)g_vocab);
    
    if (!g_vocab) {
        llama_free(g_ctx);
        llama_model_free(g_model);
        g_ctx = nullptr;
        g_model = nullptr;
        jclass exception = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exception, "Failed to get vocab from model");
        return;
    }
    
    // Reset KV cache position counter for new model
    g_n_past = 0;

    // Report progress completion
    if (progress_callback) {
        jclass callbackClass = env->GetObjectClass(progress_callback);
        jmethodID invokeMethod = env->GetMethodID(callbackClass, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");
        
        // Create Double object for 1.0
        jclass doubleClass = env->FindClass("java/lang/Double");
        jmethodID doubleConstructor = env->GetMethodID(doubleClass, "<init>", "(D)V");
        jobject doubleObj = env->NewObject(doubleClass, doubleConstructor, 1.0);
        
        env->CallObjectMethod(progress_callback, invokeMethod, doubleObj);
        env->DeleteLocalRef(doubleObj);
        env->DeleteLocalRef(callbackClass);
    }

    LOGI("Model loaded successfully");
}

static jobject g_token_callback = nullptr;

// ---------------------------------------------------------------------------
// Multimodal (libmtmd)
// ---------------------------------------------------------------------------

// The marker the projector expects in the prompt where media should be spliced
// in. Exposed so the Dart side can place it inside the chat template rather
// than having the JNI guess where the user's turn begins.
extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeDrainLog(
        JNIEnv* env, jobject /* this */) {
    std::deque<std::string> drained;
    {
        std::lock_guard<std::mutex> lock(g_log_ring_mutex);
        drained.swap(g_log_ring);
    }
    jclass stringClass = env->FindClass("java/lang/String");
    jobjectArray out = env->NewObjectArray(
        static_cast<jsize>(drained.size()), stringClass, nullptr);
    for (jsize i = 0; i < static_cast<jsize>(drained.size()); ++i) {
        // ggml/llama.cpp logs are raw C++ strings and routinely carry bytes
        // that are not valid *Modified* UTF-8 (truncated multibyte tails,
        // embedded NULs). NewStringUTF used to reject those by returning
        // null; CheckJNI on current Android aborts the whole process instead,
        // which is exactly how a debuggable build died while loading a model
        // whose metadata logs such a byte. Sanitize first.
        const std::string clean =
            sanitizeUTF8(drained[i].c_str(), drained[i].size());
        jstring line = env->NewStringUTF(clean.c_str());
        if (line == nullptr) {
            env->ExceptionClear();
            continue;
        }
        env->SetObjectArrayElement(out, i, line);
        env->DeleteLocalRef(line);
    }
    return out;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeMediaMarker(
    JNIEnv* env, jobject thiz) {
    return env->NewStringUTF(mtmd_default_marker());
}

// Loads the multimodal projector that pairs with the already-loaded model.
// Returns a capability bitmask: 1 = vision, 2 = audio, -1 = load failed.
extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeLoadMmproj(
    JNIEnv* env, jobject thiz, jstring mmproj_path, jboolean use_gpu, jint n_threads) {

    if (!g_model) {
        LOGE("Cannot load mmproj: no model loaded");
        return -1;
    }

    if (g_mtmd) {
        mtmd_free(g_mtmd);
        g_mtmd = nullptr;
    }

    const char* path = env->GetStringUTFChars(mmproj_path, nullptr);
    LOGI("Loading mmproj: %s (gpu=%d)", path, (int)use_gpu);

    mtmd_context_params params = mtmd_context_params_default();
    params.use_gpu       = use_gpu;
    // On by default: the encoder is the slowest step of a multimodal turn by
    // an order of magnitude, and without its own timing there is no way to tell
    // an expensive image apart from a slow prefill in the log.
    params.print_timings = true;
    params.n_threads     = n_threads > 0 ? n_threads : 4;
    // The encoder runs once per image, and a warmup pass would double the cost
    // of the very first one for no benefit on a phone.
    params.warmup        = false;

    g_mtmd = mtmd_init_from_file(path, g_model, params);
    env->ReleaseStringUTFChars(mmproj_path, path);

    if (!g_mtmd) {
        LOGE("mtmd_init_from_file failed");
        return -1;
    }

    jint caps = 0;
    if (mtmd_support_vision(g_mtmd)) caps |= 1;
    if (mtmd_support_audio(g_mtmd))  caps |= 2;
    LOGI("mmproj loaded, capabilities: vision=%d audio=%d",
         (caps & 1) ? 1 : 0, (caps & 2) ? 1 : 0);
    return caps;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeFreeMmproj(
    JNIEnv* env, jobject thiz) {
    if (g_mtmd) {
        mtmd_free(g_mtmd);
        g_mtmd = nullptr;
        LOGI("mmproj freed");
    }
    g_pending_media.clear();
}

// Audio input has to be resampled to whatever rate the projector was trained
// on. Reported here so the caller can convert before handing over a file.
extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeAudioSampleRate(
    JNIEnv* env, jobject thiz) {
    return g_mtmd ? mtmd_get_audio_sample_rate(g_mtmd) : 0;
}

// Queues media for the next generate call. Each path is an image or audio file
// and must line up, in order, with the markers in that call's prompt.
extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeSetMedia(
    JNIEnv* env, jobject thiz, jobjectArray paths) {

    g_pending_media.clear();
    if (paths == nullptr) return;

    const jsize count = env->GetArrayLength(paths);
    for (jsize i = 0; i < count; i++) {
        jstring item = (jstring) env->GetObjectArrayElement(paths, i);
        if (item == nullptr) continue;
        const char* chars = env->GetStringUTFChars(item, nullptr);
        g_pending_media.emplace_back(chars);
        env->ReleaseStringUTFChars(item, chars);
        env->DeleteLocalRef(item);
    }
    LOGI("Queued %zu media file(s) for the next generation", g_pending_media.size());
}

// Chat templates embed their own BOS when the model needs one; tokenizing that
// with add_special=true produced two BOS tokens (check_double_bos_eos warning)
// and measurably degraded Llama-3.x output. Skip add_special when the prompt
// already opens with this vocab's BOS text.
static bool prompt_already_has_bos(const llama_vocab* vocab,
                                   const std::string& prompt) {
    const llama_token bos = llama_vocab_bos(vocab);
    if (bos == LLAMA_TOKEN_NULL) return false;
    char piece[64] = {0};
    const int n = llama_token_to_piece(vocab, bos, piece, sizeof(piece) - 1,
                                       /*lstrip*/ 0, /*special*/ true);
    if (n <= 0 || (size_t)n > prompt.size()) return false;
    return prompt.compare(0, (size_t)n, piece, (size_t)n) == 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGenerate(
    JNIEnv* env, jobject thiz,
    jstring prompt, jlong max_tokens, 
    jdouble temperature, jdouble top_p, jlong top_k, jdouble min_p, jdouble typical_p,
    jdouble repeat_penalty, jdouble frequency_penalty, jdouble presence_penalty, jlong repeat_last_n,
    jlong mirostat, jdouble mirostat_tau, jdouble mirostat_eta,
    jlong seed, jboolean penalize_newline,
    jobject token_callback) {
    
    if (g_token_callback != nullptr) {
        env->DeleteGlobalRef(g_token_callback);
        g_token_callback = nullptr;
    }
    g_token_callback = env->NewGlobalRef(token_callback);
    
    if (!g_model || !g_ctx || !g_vocab) {
        jclass exception = env->FindClass("java/lang/IllegalStateException");
        env->ThrowNew(exception, "Model not loaded");
        return;
    }

    // Held for the whole generation: nothing may free g_ctx underneath it.
    //
    // Logged around, not just taken: the lock is acquired before any other
    // message, so a request blocked here would otherwise look exactly like
    // one that was never made. Those need different fixes, so say which.
    LOGI("nativeGenerate: entry");
    std::unique_lock<std::mutex> ctx_lock(g_ctx_mutex, std::try_to_lock);
    if (!ctx_lock.owns_lock()) {
        LOGI("nativeGenerate: context busy, waiting for the previous generation");
        ctx_lock.lock();
    }
    LOGI("nativeGenerate: context acquired");

    // Clear memory from previous generation to start fresh
    const char* prompt_str = env->GetStringUTFChars(prompt, nullptr);
    g_stop_flag = false;
    
    const int prompt_len = strlen(prompt_str);
    LOGI("Tokenizing prompt: '%s' (length: %d)", prompt_str, prompt_len);
    LOGI("Vocab pointer: %p, Model pointer: %p", (void*)g_vocab, (void*)g_model);

    // Sanitize the UTF-8 string before tokenizing
    std::string sanitized_prompt = sanitizeUTF8(prompt_str, prompt_len);
    env->ReleaseStringUTFChars(prompt, prompt_str);

    const int n_ctx = llama_n_ctx(g_ctx);
    const int max_batch_size = 512;

    // Reused by both prefill paths below and by the generation loop.
    llama_batch batch = llama_batch_init(max_batch_size, 0, 1);
    LOGI("Context size: %d", n_ctx);

    // Shifts the KV cache when the incoming prompt would not fit, dropping the
    // oldest quarter of the context.
    auto make_room_for = [&](int incoming) {
        if (g_n_past + incoming <= n_ctx) return;
        const int n_discard = n_ctx / 4;
        LOGI("Context is full, shifting KV cache by %d tokens", n_discard);
        llama_memory_seq_rm (llama_get_memory(g_ctx), 0, 0, n_discard);
        llama_memory_seq_add(llama_get_memory(g_ctx), 0, n_discard, g_n_past, -n_discard);
        g_n_past -= n_discard;
    };

    const bool use_mtmd = (g_mtmd != nullptr) && !g_pending_media.empty();

    if (use_mtmd) {
        // --- multimodal prefill ------------------------------------------
        // libmtmd splits the prompt at each media marker, runs the vision or
        // audio encoder over the matching file, and feeds the resulting
        // embeddings to llama_decode itself. Tokenizing here by hand would
        // throw the media away, which is why this path bypasses the block
        // below entirely.
        const std::string marker = mtmd_default_marker();

        size_t marker_count = 0;
        for (size_t at = sanitized_prompt.find(marker); at != std::string::npos;
             at = sanitized_prompt.find(marker, at + marker.size())) {
            marker_count++;
        }

        // mtmd_tokenize fails outright when the counts disagree. Rather than
        // error out, normalize: strip whatever markers are there and put one
        // per file at the front. A misplaced marker degrades the answer; a
        // missing one loses the image.
        if (marker_count != g_pending_media.size()) {
            LOGI("Marker count %zu != %zu media file(s), rewriting prompt",
                 marker_count, g_pending_media.size());
            for (size_t at = sanitized_prompt.find(marker); at != std::string::npos;
                 at = sanitized_prompt.find(marker)) {
                sanitized_prompt.erase(at, marker.size());
            }
            std::string prefix;
            for (size_t i = 0; i < g_pending_media.size(); i++) {
                prefix += marker;
                prefix += "\n";
            }
            sanitized_prompt = prefix + sanitized_prompt;
        }

        std::vector<mtmd_bitmap*> bitmaps;
        std::string load_failure;
        for (const std::string& path : g_pending_media) {
            struct mtmd_helper_bitmap_wrapper bw = mtmd_helper_bitmap_init_from_file(g_mtmd, path.c_str(), false, mtmd_helper_init_opt_default());
            mtmd_bitmap* bitmap = bw.bitmap;
            if (!bitmap) {
                load_failure = path;
                break;
            }
            bitmaps.push_back(bitmap);
        }

        if (!load_failure.empty()) {
            for (mtmd_bitmap* b : bitmaps) mtmd_bitmap_free(b);
            g_pending_media.clear();
            llama_batch_free(batch);
            LOGE("Failed to load media file: %s", load_failure.c_str());
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception,
                ("Failed to read media file: " + load_failure).c_str());
            return;
        }

        mtmd_input_text text;
        text.text          = sanitized_prompt.c_str();
        text.add_special   = !prompt_already_has_bos(g_vocab, sanitized_prompt);
        text.parse_special = true;

        std::vector<const mtmd_bitmap*> bitmap_ptrs(bitmaps.begin(), bitmaps.end());
        mtmd_input_chunks* chunks = mtmd_input_chunks_init();

        const int32_t tokenize_rc = mtmd_tokenize(
            g_mtmd, chunks, &text, bitmap_ptrs.data(), bitmap_ptrs.size());

        for (mtmd_bitmap* b : bitmaps) mtmd_bitmap_free(b);
        g_pending_media.clear();

        if (tokenize_rc != 0) {
            mtmd_input_chunks_free(chunks);
            llama_batch_free(batch);
            LOGE("mtmd_tokenize failed with code %d", tokenize_rc);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception, tokenize_rc == 1
                ? "Media count does not match the markers in the prompt"
                : "Failed to preprocess the media for this model");
            return;
        }

        const size_t n_incoming = mtmd_helper_get_n_tokens(chunks);
        LOGI("Multimodal prompt: %zu tokens across %zu chunk(s)",
             n_incoming, mtmd_input_chunks_size(chunks));
        make_room_for((int) n_incoming);

        // Per chunk rather than mtmd_helper_eval_chunks() over the lot, so the
        // log says which part of a multimodal prefill the time went to. The
        // whole-list helper is a black box that can run for a minute, and the
        // encoder and the decode of its output have completely different fixes.
        // Same breakdown llama.rn prints, which makes the two directly
        // comparable on the same prompt.
        llama_pos new_n_past = g_n_past;
        int32_t eval_rc = 0;
        const size_t n_chunks = mtmd_input_chunks_size(chunks);
        for (size_t i = 0; i < n_chunks && eval_rc == 0; i++) {
            const mtmd_input_chunk* chunk = mtmd_input_chunks_get(chunks, i);
            const mtmd_input_chunk_type type = mtmd_input_chunk_get_type(chunk);
            const char* kind = type == MTMD_INPUT_CHUNK_TYPE_TEXT  ? "TEXT"
                             : type == MTMD_INPUT_CHUNK_TYPE_IMAGE ? "IMAGE"
                                                                   : "AUDIO";
            const size_t n_tok = mtmd_input_chunk_get_n_tokens(chunk);
            const auto t0 = std::chrono::steady_clock::now();
            eval_rc = mtmd_helper_eval_chunk_single(
                g_mtmd, g_ctx, chunk, new_n_past, /* seq_id */ 0,
                max_batch_size, /* logits_last */ i + 1 == n_chunks, &new_n_past);
            // Stop the clock only once the backend has actually finished. Same
            // reason as the text prefill below: without this the GPU's share of
            // a chunk gets billed to whatever runs next.
            llama_synchronize(g_ctx);
            const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - t0).count();
            LOGI("Chunk %zu/%zu: type=%s, n_tokens=%zu, %lld ms",
                 i + 1, n_chunks, kind, n_tok, (long long) ms);
        }

        mtmd_input_chunks_free(chunks);

        if (eval_rc != 0) {
            llama_batch_free(batch);
            LOGE("mtmd_helper_eval_chunks failed with code %d", eval_rc);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception, "Failed to evaluate the multimodal prompt");
            return;
        }

        g_n_past = new_n_past;
        LOGI("Multimodal prefill done, g_n_past=%d", g_n_past);

    } else {
        // --- text-only prefill -------------------------------------------
        const char* sanitized_cstr = sanitized_prompt.c_str();
        const int sanitized_len = sanitized_prompt.length();
        const bool add_special = !prompt_already_has_bos(g_vocab, sanitized_prompt);

        // Tokenize prompt - when tokens is NULL, llama_tokenize returns NEGATIVE count
        const int n_prompt_tokens = -llama_tokenize(g_vocab, sanitized_cstr, sanitized_len, nullptr, 0, add_special, true);
        LOGI("Token count: %d", n_prompt_tokens);

        if (n_prompt_tokens <= 0) {
            llama_batch_free(batch);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "Failed to tokenize prompt (got %d tokens)", n_prompt_tokens);
            env->ThrowNew(exception, error_msg);
            return;
        }
        std::vector<llama_token> tokens(n_prompt_tokens);
        const int actual_tokens = llama_tokenize(g_vocab, sanitized_cstr, sanitized_len, tokens.data(), tokens.size(), add_special, true);
        if (actual_tokens < 0) {
            llama_batch_free(batch);
            jclass exception = env->FindClass("java/lang/RuntimeException");
            env->ThrowNew(exception, "Failed to tokenize prompt");
            return;
        }
        tokens.resize(actual_tokens);

        make_room_for((int) tokens.size());

        // Process prompt in batches to handle long inputs
        int tokens_processed = 0;
        const auto t_prefill = std::chrono::steady_clock::now();

        while (tokens_processed < tokens.size() && !g_stop_flag) {
            batch.n_tokens = 0;
            int batch_size = std::min((int)tokens.size() - tokens_processed, max_batch_size);

            for (int i = 0; i < batch_size; i++) {
                batch.token[batch.n_tokens] = tokens[tokens_processed + i];
                batch.pos[batch.n_tokens] = g_n_past + tokens_processed + i;
                batch.n_seq_id[batch.n_tokens] = 1;
                batch.seq_id[batch.n_tokens][0] = 0;
                batch.logits[batch.n_tokens] = (tokens_processed + i == tokens.size() - 1);
                batch.n_tokens++;
            }

            LOGI("Decoding batch: g_n_past=%d, batch_size=%d", g_n_past + tokens_processed, batch.n_tokens);
            int decode_result = llama_decode(g_ctx, batch);
            if (decode_result != 0) {
                LOGE("❌ DECODE FAILED! Result code: %d", decode_result);
                llama_batch_free(batch);
                jclass exception = env->FindClass("java/lang/RuntimeException");
                env->ThrowNew(exception, "Failed to decode prompt");
                return;
            }
            tokens_processed += batch_size;
        }

        // llama_decode only enqueues work on an asynchronous backend; it
        // returns before the GPU has run it, so timing the loop alone measured
        // the submit rather than the prefill. On Vulkan here a 48-token prompt
        // "decoded" in 196 ms and then cost 10.7 s inside the first
        // llama_sampler_sample, which is the call that forces the sync -- the
        // prefill was being billed to sampling and the log read as though the
        // GPU were fast. Synchronise before stopping the clock. On the CPU
        // backend this is work already done, so the number does not move.
        llama_synchronize(g_ctx);
        const auto prefill_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - t_prefill).count();
        LOGI("✅ Prefill done: %d tokens in %lld ms (%.1f tok/s)",
             tokens_processed, (long long) prefill_ms,
             prefill_ms > 0 ? tokens_processed * 1000.0 / prefill_ms : 0.0);

        // Update position counter after decoding the whole prompt
        g_n_past += tokens.size();
    }

    // Create sampler chain with all parameters
    if (g_sampler) {
        llama_sampler_free(g_sampler);
    }
    
    // Use seed or current time
    uint32_t sampler_seed = (seed >= 0) ? static_cast<uint32_t>(seed) : static_cast<uint32_t>(time(nullptr));
    
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    
    // Add penalties first (applied to logits before sampling)
    if (repeat_penalty != 1.0f || frequency_penalty != 0.0f || presence_penalty != 0.0f) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_penalties(
            llama_vocab_n_tokens(g_vocab),  // n_vocab
            repeat_last_n,              // penalty_last_n
            repeat_penalty,             // penalty_repeat
            frequency_penalty,          // penalty_freq
            presence_penalty            // penalty_present
        ));
    }
    
    // Temperature sampling
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    
    // Add advanced samplers if enabled
    if (mirostat == 1) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_mirostat(
            llama_vocab_n_tokens(g_vocab),  // Use the vocab to get n_vocab
            sampler_seed,
            mirostat_tau,
            mirostat_eta,
            100  // m parameter
        ));
    } else if (mirostat == 2) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_mirostat_v2(
            sampler_seed,
            mirostat_tau,
            mirostat_eta
        ));
    } else {
        // Standard sampling chain (only if mirostat is disabled)
        if (min_p > 0.0f && min_p < 1.0f) {
            llama_sampler_chain_add(g_sampler, llama_sampler_init_min_p(min_p, 1));
        }
        
        if (typical_p < 1.0f) {
            llama_sampler_chain_add(g_sampler, llama_sampler_init_typical(typical_p, 1));
        }
        
        if (top_k > 0) {
            llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
        }
        
        if (top_p < 1.0f) {
            llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
        }
    }
    
    // Final distribution sampler
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(sampler_seed));

    // Get callback method
    jclass callbackClass = env->GetObjectClass(token_callback);
    jmethodID invokeMethod = env->GetMethodID(callbackClass, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");

    // Generation loop
    LOGI("Starting generation loop: max_tokens=%lld", max_tokens);
    for (int i = 0; i < max_tokens && !g_stop_flag; i++) {
        // Sample next token
        LOGI("Sampling token %d, g_n_past=%d", i + 1, g_n_past);
        llama_token new_token_id = llama_sampler_sample(g_sampler, g_ctx, -1);
        LOGI("Sampled token: %d", new_token_id);

        // Check for end of generation (EOS/EOD tokens)
        if (llama_vocab_is_eog(g_vocab, new_token_id)) {
            LOGI("EOS token detected, ending generation.");
            break;
        }

        // Decode token to string
        char buffer[256];
        int32_t length = llama_token_to_piece(g_vocab, new_token_id, buffer, sizeof(buffer), 0, true);
        std::string piece;
        
        if (length > 0) {
            piece = sanitizeUTF8(buffer, length);
        } else {
            piece = "";
        }
        
        // Call Kotlin callback
        jstring token_str = env->NewStringUTF(piece.c_str());
        env->CallObjectMethod(g_token_callback, invokeMethod, token_str);
        env->DeleteLocalRef(token_str);

        // Prepare next batch
        batch.n_tokens = 0;
        batch.token[batch.n_tokens] = new_token_id;
        batch.pos[batch.n_tokens] = g_n_past;  // Use the tracked position
        batch.n_seq_id[batch.n_tokens] = 1;
        batch.seq_id[batch.n_tokens][0] = 0;
        batch.logits[batch.n_tokens] = true;
        batch.n_tokens++;

        if (llama_decode(g_ctx, batch) != 0) {
            LOGE("Failed to decode after sampling token %d", i + 1);
            break;
        }
        
        // Update position counter after each generated token
        g_n_past++;
    }
    LOGI("Generation loop finished.");

    if (g_token_callback != nullptr) {
        env->DeleteGlobalRef(g_token_callback);
        g_token_callback = nullptr;
    }

    // After generation completion, ensure the KV cache is properly managed
    // In some llama.cpp versions, KV cache management may be needed between generations
    // For chat applications, we want to maintain conversation context
    
    llama_batch_free(batch);
    env->DeleteLocalRef(callbackClass);
}

// Reads one GGUF metadata key from the loaded model ("general.name",
// sampler defaults embedded by some exporters, …). Empty string when absent.
extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetMeta(
    JNIEnv* env, jobject thiz, jstring key) {
    if (!g_model) return env->NewStringUTF("");
    const char* k = env->GetStringUTFChars(key, nullptr);
    char buf[256] = {0};
    const int32_t n =
        llama_model_meta_val_str(g_model, k, buf, sizeof(buf) - 1);
    env->ReleaseStringUTFChars(key, k);
    if (n <= 0) return env->NewStringUTF("");
    const std::string clean = sanitizeUTF8(buf, (size_t) n);
    return env->NewStringUTF(clean.c_str());
}

// Reads a few header keys straight from an on-disk GGUF — no model load.
// no_alloc skips the tensor blob, so a multi-GB file answers in milliseconds
// and the model card can show facts the filename does not carry (the true
// context window especially: "Q4_0" names never mention 32k). Newline-
// separated key=value lines; empty string when the file is unreadable.
extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeProbeGgufFile(
    JNIEnv* env, jobject thiz, jstring path) {
    if (!path) return env->NewStringUTF("");
    const char* p = env->GetStringUTFChars(path, nullptr);
    const std::string file(p);
    env->ReleaseStringUTFChars(path, p);

    gguf_init_params params;
    params.no_alloc = true;
    params.ctx = nullptr;
    gguf_context* gc = gguf_init_from_file(file.c_str(), params);
    if (!gc) return env->NewStringUTF("");

    auto str_kv = [&](const char* key) -> std::string {
        const int64_t id = gguf_find_key(gc, key);
        if (id < 0 || gguf_get_kv_type(gc, id) != GGUF_TYPE_STRING) return "";
        return gguf_get_val_str(gc, id);
    };
    auto int_kv = [&](const std::string& key) -> uint64_t {
        const int64_t id = gguf_find_key(gc, key.c_str());
        if (id < 0) return 0;
        switch (gguf_get_kv_type(gc, id)) {
            case GGUF_TYPE_UINT32: return gguf_get_val_u32(gc, id);
            case GGUF_TYPE_INT32:  return (uint64_t) gguf_get_val_i32(gc, id);
            case GGUF_TYPE_UINT64: return gguf_get_val_u64(gc, id);
            case GGUF_TYPE_INT64:  return (uint64_t) gguf_get_val_i64(gc, id);
            default: return 0;
        }
    };

    const std::string arch = str_kv("general.architecture");
    std::string out = "arch=" + arch + "\n";
    // Context length is keyed per architecture ("llama.context_length").
    if (!arch.empty()) {
        const uint64_t ctx = int_kv(arch + ".context_length");
        if (ctx > 0) out += "context_length=" + std::to_string(ctx) + "\n";
    }
    const std::string label = str_kv("general.size_label");
    if (!label.empty()) out += "size_label=" + label + "\n";
    gguf_free(gc);

    const std::string clean = sanitizeUTF8(out.data(), out.size());
    return env->NewStringUTF(clean.c_str());
}

// Formats the conversation with the template embedded in the model's own GGUF
// (tokenizer.chat_template), so every family — Llama-3, ChatML, Gemma, Qwen,
// Mistral… — gets its real prompt shape instead of a name-sniffed guess.
// Returns "" when the model ships no template; the caller falls back.
// Parallel arrays rather than JSON keep a parser out of native code.
extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeApplyChatTemplate(
    JNIEnv* env, jobject thiz, jobjectArray roles, jobjectArray contents) {

    if (!g_model) {
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),
                      "Model not loaded");
        return nullptr;
    }

    const jsize n = env->GetArrayLength(roles);
    if (n == 0 || env->GetArrayLength(contents) != n) {
        env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"),
                      "roles and contents must be non-empty and same length");
        return nullptr;
    }

    const char* tmpl = llama_model_chat_template(g_model, nullptr);
    if (tmpl == nullptr || tmpl[0] == '\0') {
        LOGI("GGUF carries no chat template; caller will fall back");
        return env->NewStringUTF("");
    }

    std::vector<llama_chat_message> msgs;
    std::vector<std::string> owned;
    owned.reserve(2 * (size_t)n);
    for (jsize i = 0; i < n; i++) {
        auto grab = [&](jobjectArray arr) {
            jstring s = (jstring) env->GetObjectArrayElement(arr, i);
            const char* c = env->GetStringUTFChars(s, nullptr);
            owned.emplace_back(c ? c : "");
            env->ReleaseStringUTFChars(s, c);
            env->DeleteLocalRef(s);
        };
        grab(roles);
        grab(contents);
    }
    for (size_t i = 0; i < (size_t)n; i++) {
        msgs.push_back({owned[2 * i].c_str(), owned[2 * i + 1].c_str()});
    }

    size_t cap = 4096;
    std::vector<char> buf(cap);
    // Per the header: returns the total bytes needed when the buffer is too
    // small, so grow to exactly that once instead of guessing twice.
    int32_t rc = llama_chat_apply_template(tmpl, msgs.data(), msgs.size(),
                                           /*add_ass*/ true,
                                           buf.data(), (int32_t) buf.size());
    if (rc > (int32_t) buf.size()) {
        cap = (size_t) rc + 1;
        buf.resize(cap);
        rc = llama_chat_apply_template(tmpl, msgs.data(), msgs.size(), true,
                                       buf.data(), (int32_t) buf.size());
    }
    if (rc <= 0) {
        LOGE("llama_chat_apply_template failed with code %d", rc);
        return env->NewStringUTF("");
    }

    LOGI("Applied the model's own chat template (%zu chars)", (size_t) rc);
    const std::string out =
        sanitizeUTF8(buf.data(), (size_t) rc);
    return env->NewStringUTF(out.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeStop(
    JNIEnv* env, jobject thiz) {
    g_stop_flag = true;
    // When stopping generation, we just set the flag - KV cache management handled by llama.cpp
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeFreeModel(
    JNIEnv* env, jobject thiz) {

    // Raise the flag before queueing on the mutex, so a generation in flight
    // unwinds at its next batch instead of making this wait out the whole
    // prompt. Ordering matters: lock first and the two would deadlock the
    // caller for the length of a full prefill.
    g_stop_flag = true;
    std::lock_guard<std::mutex> ctx_lock(g_ctx_mutex);

    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_mtmd) {
        mtmd_free(g_mtmd);
        g_mtmd = nullptr;
    }
    g_pending_media.clear();
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    g_vocab = nullptr;
    g_n_past = 0;  // Reset position counter
    
    LOGI("Model freed");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetTokensUsed(
    JNIEnv* env, jobject thiz) {
    return g_n_past;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeGetContextSize(
    JNIEnv* env, jobject thiz) {
    return g_ctx ? llama_n_ctx(g_ctx) : 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeClearContext(
    JNIEnv* env, jobject thiz) {
    if (!g_ctx) {
        LOGE("Cannot clear context: context is null");
        return;
    }
    
    llama_memory_t mem = llama_get_memory(g_ctx);
    if (mem) {
        llama_memory_seq_rm(mem, 0, 0, -1);
        g_n_past = 0;
        LOGI("Context cleared, g_n_past reset to 0");
    } else {
        LOGE("Failed to get memory object from context");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeSetSystemPromptLength(
    JNIEnv* env, jobject thiz, jint length) {
    // Currently not used but available for future smart context management
    LOGI("System prompt length set to: %d tokens (currently unused)", length);
}

// ---------------------------------------------------------------------------
// Encoder surface
//
// A GGUF that declares a `<arch>.pooling_type` does not generate; it pools a
// sequence. That covers embeddings (MEAN / CLS / LAST), rerankers and
// classifiers (RANK, with labels). Two calls, deliberately: one to describe
// what the loaded model can do, one to actually run it.
//
// This is `llama_decode`, not `llama_encode`. `llama_encode` feeds the encoder
// half of an *encode-decoder* to a decoder's cross-attention — the header says
// so, and speculative.cpp uses it exactly that way. An encoder-only model has
// no decoder to feed, and examples/embedding/embedding.cpp runs one through
// `llama_decode` like this.
// ---------------------------------------------------------------------------

// What the loaded model can do as an encoder, as JSON. Labels are a list and
// this is read once per load, so a string beats a jobjectArray here.
extern "C" JNIEXPORT jstring JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeEncoderInfo(
    JNIEnv* env, jobject /* thiz */) {
    if (!g_model || !g_ctx) return env->NewStringUTF("{}");

    // The same lock nativeEncode takes. Reading g_ctx from the platform thread
    // while a generation holds it is the use-after-free this mutex exists for,
    // and llama_pooling_type is a field read — the lock is free here.
    enum llama_pooling_type pooling;
    uint32_t n_cls;
    bool inferred = false;
    {
        std::lock_guard<std::mutex> ctx_lock(g_ctx_mutex);
        pooling = llama_pooling_type(g_ctx);
        n_cls = llama_model_n_cls_out(g_model);
    }
    // Reported, because "this model was inferred to be a reranker" is a claim a
    // caller may want to distrust, and `pooling: rank` on its own does not say
    // whether the file said so or we concluded it.
    enum llama_pooling_type declared = LLAMA_POOLING_TYPE_NONE;
    inferred = !model_declared_pooling(g_model, declared) && pooling != LLAMA_POOLING_TYPE_NONE;

    std::string labels;
    for (uint32_t i = 0; i < n_cls; i++) {
        const char* label = llama_model_cls_label(g_model, i);
        if (!label) continue;
        if (!labels.empty()) labels += ",";
        // Labels come from the file and can carry anything a text key holds,
        // so they go through the same filter as a log line before they reach
        // NewStringUTF — a raw one aborts a debuggable build under CheckJNI.
        labels += "\"" + sanitizeUTF8(label, strlen(label)) + "\"";
    }

    char out[1024] = {0};
    snprintf(out, sizeof(out),
             "{\"is_encoder\":%s,\"pooling\":\"%s\",\"n_cls_out\":%u,"
             "\"n_embd_out\":%d,\"output_len\":%d,\"inferred_pooling\":%s,"
             "\"arch_is_encoder\":%s,\"labels\":[%s]}",
             (pooling != LLAMA_POOLING_TYPE_NONE) ? "true" : "false",
             pooling_name(pooling),
             (unsigned) n_cls,
             llama_model_n_embd_out(g_model),
             pooled_output_len(g_model, pooling),
             inferred ? "true" : "false",
             // Separate from `is_encoder` on purpose. A model whose architecture
             // is an encoder but whose pooling stayed NONE is not a chat model:
             // it is an encoder this build could not turn into a scorer, and
             // telling the caller "load an embedding model" sends them to fix
             // something that is already correct.
             arch_is_encoder(g_model) ? "true" : "false",
             labels.c_str());

    return env->NewStringUTF(sanitizeUTF8(out, strlen(out)).c_str());
}

// Pool one sequence.
//
// [text] alone, or [text] and [query] joined the way a cross-encoder expects
// when there is a query: the model's own `rerank` chat template with {query}
// and {document} substituted if it has one, otherwise the vocab's SEP token as
// the boundary. Joining them with a space instead would tokenize into one
// undifferentiated run and return a confident number about nothing.
//
// Returns doubles rather than floats even though the model computes in float:
// the widening is free here, it is what every embedding API on the other side
// speaks, and it keeps the conversion out of the Kotlin — where a `FloatArray`
// would have to be walked by hand, because there is no `toDoubleArray()` on the
// primitive array in the stdlib.
extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_write4me_llama_1flutter_1android_LlamaFlutterAndroidPlugin_nativeEncode(
    JNIEnv* env, jobject /* thiz */, jstring text, jstring query) {
    if (!g_model || !g_ctx || !g_vocab) {
        throwLoadError(env, "No model loaded");
        return nullptr;
    }

    const enum llama_pooling_type pooling = llama_pooling_type(g_ctx);
    if (pooling == LLAMA_POOLING_TYPE_NONE) {
        throwLoadError(env,
            "This model does not declare a pooling type, so it is a generation "
            "model. Embeddings, rerank and classify need a BERT/ModernBERT-style "
            "GGUF whose metadata carries <arch>.pooling_type.");
        return nullptr;
    }

    const char* t_raw = text ? env->GetStringUTFChars(text, nullptr) : nullptr;
    const char* q_raw = query ? env->GetStringUTFChars(query, nullptr) : nullptr;
    const std::string t = t_raw ? t_raw : "";
    const std::string q = q_raw ? q_raw : "";
    if (t_raw) env->ReleaseStringUTFChars(text, t_raw);
    if (q_raw) env->ReleaseStringUTFChars(query, q_raw);

    std::string input;
    if (!q.empty()) {
        const char* rerank_tpl = llama_model_chat_template(g_model, "rerank");
        if (rerank_tpl) {
            input = rerank_tpl;
            const std::string q_ph = "{query}";
            const std::string d_ph = "{document}";
            for (size_t at = input.find(q_ph); at != std::string::npos;
                 at = input.find(q_ph, at + q.size())) {
                input.replace(at, q_ph.size(), q);
            }
            for (size_t at = input.find(d_ph); at != std::string::npos;
                 at = input.find(d_ph, at + t.size())) {
                input.replace(at, d_ph.size(), t);
            }
        } else {
            // No template: the boundary is the SEP token itself, which is what
            // the vocab was built with. Asking for the token's *piece* is what
            // makes this a real boundary rather than the literal "[SEP]" text
            // that would then be tokenized as ordinary words.
            const llama_token sep = llama_vocab_sep(g_vocab);
            std::string sep_text = "\t";
            if (sep != LLAMA_TOKEN_NULL) {
                char buf[64] = {0};
                const int32_t n = llama_token_to_piece(g_vocab, sep, buf, sizeof(buf), 0, true);
                if (n > 0) sep_text.assign(sanitizeUTF8(buf, (size_t) n));
            }
            input = q + sep_text + t;
        }
    } else {
        input = t;
    }

    // add_special = true: a BERT-family vocab is meaningless without its [CLS]
    // and [SEP]. A SentencePiece causal vocab ignores the flag, so this is
    // safe for both kinds of model that can reach here.
    std::vector<llama_token> tokens(input.size() + 8);
    int32_t n = llama_tokenize(g_vocab, input.c_str(), (int32_t) input.size(),
                                tokens.data(), (int32_t) tokens.size(), true, false);
    if (n < 0) {
        tokens.resize(-n);
        n = llama_tokenize(g_vocab, input.c_str(), (int32_t) input.size(),
                           tokens.data(), (int32_t) tokens.size(), true, false);
    }
    if (n <= 0) {
        throwLoadError(env, "Could not tokenize the input for this encoder");
        return nullptr;
    }
    tokens.resize(n);

    // One batch, one sequence, and **every** token flagged for output. Pooling
    // aggregates over the tokens marked in `logits`; leave them false and the
    // model returns a plausible vector built from nothing but [CLS]. That is
    // the failure mode that does not look like a failure, which is why it gets
    // its own comment instead of a loop that happens to fill the array.
    llama_batch batch = llama_batch_init(n, 0, 1);
    if (!batch.token || !batch.logits) {
        llama_batch_free(batch);
        throwLoadError(env, "Could not allocate the encoder batch");
        return nullptr;
    }
    for (int32_t i = 0; i < n; i++) {
        batch.token[i]    = tokens[i];
        batch.pos[i]      = i;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        batch.logits[i]   = 1;
    }
    batch.n_tokens = n;

    const int32_t out_len = pooled_output_len(g_model, pooling);

    jdoubleArray result = nullptr;
    {
        // Same lock nativeGenerate takes, for the same reason: this blocks in
        // llama_decode, and teardown frees the context from another thread.
        std::lock_guard<std::mutex> ctx_lock(g_ctx_mutex);
        llama_memory_clear(llama_get_memory(g_ctx), true);

        const int32_t rc = llama_decode(g_ctx, batch);
        if (rc != 0) {
            llama_batch_free(batch);
            throwLoadError(env, "llama_decode failed on the encoder batch (rc=" +
                                std::to_string(rc) + ", tokens=" + std::to_string(n) + ")");
            return nullptr;
        }

        const float* pooled = llama_get_embeddings_seq(g_ctx, 0);
        if (!pooled) {
            llama_batch_free(batch);
            throwLoadError(env,
                "The model pooled nothing. That means the context was not created "
                "with embeddings enabled, which is a build problem rather than a "
                "model problem.");
            return nullptr;
        }

        std::vector<double> widened((size_t) out_len);
        for (int32_t i = 0; i < out_len; i++) widened[(size_t) i] = pooled[i];

        result = env->NewDoubleArray(out_len);
        if (result) {
            env->SetDoubleArrayRegion(result, 0, out_len, widened.data());
        }
    }

    llama_batch_free(batch);
    if (result) {
        LOGI("Encoded %d tokens -> %d floats (pooling=%s)", n, out_len, pooling_name(pooling));
    }
    return result;
}
