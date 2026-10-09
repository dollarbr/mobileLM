package com.write4me.llama_flutter_android

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicBoolean

class LlamaFlutterAndroidPlugin : FlutterPlugin, LlamaHostApi, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var flutterApi: LlamaFlutterApi
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var generationJob: Job? = null
    private val isModelLoaded = AtomicBoolean(false)
    private val isStopping = AtomicBoolean(false)
    private var currentModelPath: String? = null
    private var nativeLoadError: Throwable? = null
    private var nativeLoaded = false

    // The multimodal calls ride a plain MethodChannel rather than the Pigeon
    // API: the schema that generated LlamaHostApi is not in the repository, so
    // adding fields there would mean reconstructing it. Loading a projector
    // and queueing media is a small, self-contained surface anyway.
    private var mtmdChannel: MethodChannel? = null
    private var metaChannel: MethodChannel? = null
    // Not a Pigeon call either, and for a different reason: this has to arrive
    // BEFORE the load that it steers, and the Pigeon load takes its arguments
    // positionally in one message, so there is nowhere to put a "and also do
    // this first" without changing the generated schema -- which is not in the
    // repository. One integer, one call, one ordering requirement.
    private var affinityChannel: MethodChannel? = null

    companion object {
        private const val TAG = "LlamaFlutterPlugin"
        private const val MTMD_CHANNEL = "llama_flutter_android/mtmd"
        private const val META_CHANNEL = "llama_flutter_android/model_meta"
        private const val AFFINITY_CHANNEL = "llama_flutter_android/affinity"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.i(TAG, "Attaching llama Flutter plugin")
        context = binding.applicationContext
        flutterApi = LlamaFlutterApi(binding.binaryMessenger)
        LlamaHostApi.setUp(binding.binaryMessenger, this)
        mtmdChannel = MethodChannel(binding.binaryMessenger, MTMD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        metaChannel = MethodChannel(binding.binaryMessenger, META_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        affinityChannel = MethodChannel(binding.binaryMessenger, AFFINITY_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // scope.cancel() cannot interrupt nativeGenerate: it is a blocking JNI
        // call with no suspension point to cancel at. Raise the native stop
        // flag first so a generation in flight actually unwinds, then free --
        // nativeFreeModel waits for it rather than pulling the context out
        // from under a running decode.
        if (nativeLoaded) {
            isStopping.set(true)
            nativeStop()
        }
        scope.cancel()
        if (isModelLoaded.get()) {
            nativeFreeModel()
        }
        LlamaHostApi.setUp(binding.binaryMessenger, null)
        mtmdChannel?.setMethodCallHandler(null)
        mtmdChannel = null
        metaChannel?.setMethodCallHandler(null)
        metaChannel = null
        affinityChannel?.setMethodCallHandler(null)
        affinityChannel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Which cores the next load's compute threads get. 0 means leave them
            // where the scheduler puts them, which is the honest answer when the
            // topology could not be read -- better than a guessed mask that pins
            // work to the wrong cores.
            //
            // Deliberately not gated on the native library being loaded: this has
            // to be set before the load, and demanding the .so first would make
            // the ordering a cycle.
            "setComputeAffinity" -> {
                val mask = call.argument<Int>("mask") ?: 0
                if (ensureNativeLoaded() != null) {
                    // The load itself will fail the same way, with a message the
                    // user can act on. Not an error here.
                    result.success(null)
                } else {
                    nativeSetComputeAffinity(mask)
                    result.success(null)
                }
            }

            "getMeta" -> {
                ensureNativeLoaded()?.let {
                    result.error("NATIVE_LOAD", it.message, null); return
                }
                val key = call.argument<String>("key")
                result.success(if (key.isNullOrEmpty()) "" else nativeGetMeta(key))
            }

            "probeFile" -> {
                ensureNativeLoaded()?.let {
                    result.error("NATIVE_LOAD", it.message, null); return
                }
                val path = call.argument<String>("path")
                result.success(if (path.isNullOrEmpty()) "" else nativeProbeGgufFile(path))
            }

            "mediaMarker" -> {
                ensureNativeLoaded()?.let {
                    result.error("NATIVE_LOAD", it.message, null); return
                }
                result.success(nativeMediaMarker())
            }

            // What the loaded GGUF can do as an encoder, as a JSON string.
            // Cheap and safe before any model is loaded: the native side
            // answers "{}" rather than throwing, so asking is how you find out.
            "encoderInfo" -> {
                ensureNativeLoaded()?.let {
                    result.error("NATIVE_LOAD", it.message, null); return
                }
                result.success(nativeEncoderInfo())
            }

            // Pool one sequence. `query` is optional and only meaningful for a
            // cross-encoder: with one, the pair is joined at the SEP boundary
            // the model was trained on; without it, the text is embedded alone.
            //
            // Launched off the platform thread because nativeEncode blocks in
            // llama_decode for as long as the sequence takes — a few hundred ms
            // for a cross-encoder, but a document on a phone is seconds, and the
            // platform thread is where a MethodChannel result has to land.
            "encode" -> {
                ensureNativeLoaded()?.let {
                    result.error("NATIVE_LOAD", it.message, null); return
                }
                if (!isModelLoaded.get()) {
                    result.error("NO_MODEL", "No model loaded", null); return
                }
                val text = call.argument<String>("text")
                if (text.isNullOrEmpty()) {
                    result.error("BAD_ARGS", "text is required", null); return
                }
                val query = call.argument<String>("query") ?: ""
                scope.launch {
                    val started = System.nanoTime()
                    val out = try {
                        nativeEncode(text, query)
                    } catch (e: Throwable) {
                        withContext(Dispatchers.Main) {
                            result.error("ENCODE_FAILED", e.message ?: e.toString(), null)
                        }
                        return@launch
                    }
                    val elapsedMs = (System.nanoTime() - started) / 1_000_000
                    withContext(Dispatchers.Main) {
                        if (out == null) {
                            result.error("ENCODE_FAILED", "The encoder returned nothing", null)
                        } else {
                            result.success(mapOf(
                                "values" to out.toList(),
                                "elapsedMs" to elapsedMs,
                            ))
                        }
                    }
                }
            }

            // The one token id for a short string, for a decision readout.
            //
            // Synchronous and cheap: it is tokenization, not a forward pass,
            // and the answer decides whether the caller can build a valid
            // prompt at all. Turning it into a coroutine would mean the caller
            // awaits N of them before it can send anything.
            "tokenizeSingle" -> {
                ensureNativeLoaded()?.let {
                    result.error("NATIVE_LOAD", it.message, null); return
                }
                if (!isModelLoaded.get()) {
                    result.error("NO_MODEL", "No model loaded", null); return
                }
                val text = call.argument<String>("text")
                if (text == null) {
                    result.error("BAD_ARGS", "text is required", null); return
                }
                val outN = IntArray(1)
                val id = nativeTokenizeSingle(text, outN)
                result.success(mapOf(
                    "id" to id,
                    "tokenCount" to outN[0],
                ))
            }

            // One forward pass, then the raw logit of each requested token at
            // each answer slot. Slot-major: slot 0's candidates, then slot 1's.
            //
            // Off the platform thread for the reason nativeEncode is: this
            // blocks in llama_decode, and on a phone a decision prompt with a
            // long state is hundreds of milliseconds to seconds.
            "decisionScores" -> {
                ensureNativeLoaded()?.let {
                    result.error("NATIVE_LOAD", it.message, null); return
                }
                if (!isModelLoaded.get()) {
                    result.error("NO_MODEL", "No model loaded", null); return
                }
                val prompt = call.argument<String>("prompt")
                if (prompt == null) {
                    result.error("BAD_ARGS", "prompt is required", null); return
                }
                val ids = call.argument<List<Int>>("tokenIds")
                if (ids == null || ids.isEmpty()) {
                    result.error("BAD_ARGS", "tokenIds is required and cannot be empty", null); return
                }
                // -1 is the last token, and it is what a caller that knows its
                // prompt ends at the answer slot should send: computing the
                // index from the token count on the Dart side would be a second
                // source of truth about the same prompt.
                val slots = call.argument<List<Int>>("slotIndices") ?: listOf(-1)
                if (slots.isEmpty()) {
                    result.error("BAD_ARGS", "slotIndices cannot be empty", null); return
                }
                scope.launch {
                    val started = System.nanoTime()
                    val out = try {
                        nativeDecisionScores(prompt, slots.toIntArray(), ids.toIntArray())
                    } catch (e: Throwable) {
                        withContext(Dispatchers.Main) {
                            result.error("DECISION_FAILED", e.message ?: e.toString(), null)
                        }
                        return@launch
                    }
                    val elapsedMs = (System.nanoTime() - started) / 1_000_000
                    withContext(Dispatchers.Main) {
                        if (out == null) {
                            result.error("DECISION_FAILED", "The decision pass returned nothing", null)
                        } else {
                            result.success(mapOf(
                                "scores" to out.toList(),
                                "slots" to slots.size,
                                "candidates" to ids.size,
                                "elapsedMs" to elapsedMs,
                            ))
                        }
                    }
                }
            }

            // Hand over whatever ggml/llama.cpp has logged since the last
            // call. Empty before the library is loaded, which is not an
            // error: the poller starts before the first model does.
            "drainNativeLog" -> {
                // Deliberately not ensureNativeLoaded(): polling for logs
                // must not be what maps libllama_jni and its Vulkan backend
                // into a process that has not asked for inference yet.
                if (!nativeLoaded) {
                    result.success(emptyList<String>()); return
                }
                result.success(nativeDrainLog().toList())
            }

            "loadMmproj" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("BAD_ARGS", "path is required", null); return
                }
                if (!isModelLoaded.get()) {
                    result.error("NO_MODEL", "Load the model before its projector", null)
                    return
                }
                val useGpu = call.argument<Boolean>("useGpu") ?: true
                val nThreads = call.argument<Int>("nThreads") ?: 4
                scope.launch {
                    // Loading a projector reads a few hundred MB off disk and
                    // builds a graph; keep it off the platform thread.
                    val caps = nativeLoadMmproj(path, useGpu, nThreads)
                    withContext(Dispatchers.Main) {
                        if (caps < 0) {
                            result.error("MMPROJ_LOAD", "Failed to load projector: $path", null)
                        } else {
                            result.success(mapOf(
                                "vision" to (caps and 1 != 0),
                                "audio" to (caps and 2 != 0),
                                "audioSampleRate" to nativeAudioSampleRate(),
                            ))
                        }
                    }
                }
            }

            "freeMmproj" -> {
                if (isModelLoaded.get()) nativeFreeMmproj()
                result.success(null)
            }

            "setMedia" -> {
                if (!isModelLoaded.get()) {
                    result.error("NO_MODEL", "No model loaded", null); return
                }
                nativeSetMedia((call.argument<List<String>>("paths") ?: emptyList()).toTypedArray())
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun loadModel(config: ModelConfig, callback: (Result<Unit>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        scope.launch {
            try {
                // Start foreground service for long-running task
                val intent = Intent(context, InferenceService::class.java)
                ContextCompat.startForegroundService(context, intent)

                // Load model with progress callback
                nativeLoadModel(
                    config.modelPath,
                    config.nThreads,
                    config.contextSize,
                    config.nGpuLayers ?: 0L
                ) { progress ->
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onLoadProgress(progress) { result ->
                                // Handle result if needed
                            }
                        }
                    }
                }

                currentModelPath = config.modelPath
                isModelLoaded.set(true)
                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                scope.launch {
                    withContext(Dispatchers.Main) {
                        flutterApi.onError(e.message ?: "Failed to load model") { result ->
                            // Handle result if needed
                        }
                        callback(Result.failure(e))
                    }
                }
            }
        }
    }

    override fun generate(request: GenerateRequest, callback: (Result<Unit>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        if (!isModelLoaded.get()) {
            callback(Result.failure(IllegalStateException("Model not loaded")))
            return
        }

        isStopping.set(false)
        generationJob = scope.launch {
            try {
                nativeGenerate(
                    request.prompt,
                    request.maxTokens,
                    request.temperature,
                    request.topP,
                    request.topK,
                    request.minP,
                    request.typicalP,
                    request.repeatPenalty,
                    request.frequencyPenalty,
                    request.presencePenalty,
                    request.repeatLastN,
                    request.mirostat,
                    request.mirostatTau,
                    request.mirostatEta,
                    request.seed ?: -1L,  // Use -1 for random seed
                    request.penalizeNewline
                ) { token ->
                    if (!isStopping.get()) {
                        scope.launch {
                            withContext(Dispatchers.Main) {
                                flutterApi.onToken(token) { result ->
                                    // Handle result if needed
                                }
                            }
                        }
                    }
                }

                if (!isStopping.get()) {
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onDone { result ->
                                // Handle result if needed
                            }
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                if (!isStopping.get()) {
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onError(e.message ?: "Generation failed") { result ->
                                // Handle result if needed
                            }
                            callback(Result.failure(e))
                        }
                    }
                }
            }
        }
    }

    override fun stop(callback: (Result<Unit>) -> Unit) {
        isStopping.set(true)
        generationJob?.cancel()
        if (nativeLoadError == null) {
            nativeStop()
        }
        callback(Result.success(Unit))
    }

    override fun dispose(callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                stop { }
                if (isModelLoaded.get()) {
                    nativeFreeModel()
                    isModelLoaded.set(false)
                }
                
                // Stop foreground service
                val intent = Intent(context, InferenceService::class.java)
                context.stopService(intent)
                
                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun generateChat(request: ChatRequest, callback: (Result<Unit>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        if (!isModelLoaded.get()) {
            callback(Result.failure(IllegalStateException("Model not loaded")))
            return
        }

        isStopping.set(false)
        generationJob = scope.launch {
            try {
                // Prefer the template embedded in the model's GGUF — it is the
                // vendor's own prompt shape and needs no per-model guessing.
                // ChatTemplateManager stays as the fallback for models that
                // ship no tokenizer.chat_template metadata.
                val messages = request.messages.map { msg -> TemplateChatMessage(msg.role, msg.content) }
                val formattedPrompt: String = if (request.template == null) {
                    try {
                        val native = nativeApplyChatTemplate(
                            messages.map { it.role }.toTypedArray(),
                            messages.map { it.content }.toTypedArray()
                        )
                        if (native.isNotBlank()) native
                        else ChatTemplateManager.formatMessages(messages, null, currentModelPath)
                    } catch (t: Throwable) {
                        Log.w(TAG, "Native chat template failed; falling back to name sniffing", t)
                        ChatTemplateManager.formatMessages(messages, request.template, currentModelPath)
                    }
                } else {
                    ChatTemplateManager.formatMessages(messages, request.template, currentModelPath)
                }

                nativeGenerate(
                    formattedPrompt,
                    request.maxTokens.toLong(),
                    request.temperature.toDouble(),
                    request.topP.toDouble(),
                    request.topK.toLong(),
                    request.minP.toDouble(),
                    request.typicalP.toDouble(),
                    request.repeatPenalty.toDouble(),
                    request.frequencyPenalty.toDouble(),
                    request.presencePenalty.toDouble(),
                    request.repeatLastN.toLong(),
                    request.mirostat.toLong(),
                    request.mirostatTau.toDouble(),
                    request.mirostatEta.toDouble(),
                    request.seed ?: -1L,  // Use -1 for random seed
                    request.penalizeNewline
                ) { token ->
                    if (!isStopping.get()) {
                        scope.launch {
                            withContext(Dispatchers.Main) {
                                flutterApi.onToken(token) { result ->
                                    // Handle result if needed
                                }
                            }
                        }
                    }
                }

                if (!isStopping.get()) {
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onDone { result ->
                                // Handle result if needed
                            }
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                if (!isStopping.get()) {
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onError(e.message ?: "Generation failed") { result ->
                                // Handle result if needed
                            }
                            callback(Result.failure(e))
                        }
                    }
                }
            }
        }
    }

    override fun getSupportedTemplates(): List<String> {
        return ChatTemplateManager.getSupportedTemplates()
    }

    override fun isModelLoaded(): Boolean {
        return isModelLoaded.get()
    }

    override fun getContextInfo(): ContextInfo {
        ensureNativeLoaded()?.let { throw it }

        val tokensUsed = nativeGetTokensUsed().toLong()
        val contextSize = nativeGetContextSize().toLong()
        val usagePercentage = if (contextSize > 0) {
            (tokensUsed.toDouble() / contextSize.toDouble() * 100.0)
        } else {
            0.0
        }
        
        return ContextInfo(
            tokensUsed = tokensUsed,
            contextSize = contextSize,
            usagePercentage = usagePercentage
        )
    }

    override fun clearContext(callback: (Result<Unit>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        scope.launch {
            try {
                nativeClearContext()
                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun setSystemPromptLength(length: Long) {
        ensureNativeLoaded()?.let { throw it }
        nativeSetSystemPromptLength(length.toInt())
    }

    /**
     * Register a custom chat template
     * Allows users to provide their own template format at runtime
     */
    override fun registerCustomTemplate(name: String, content: String) {
        ChatTemplateManager.registerCustomTemplate(name, content)
    }

    /**
     * Unregister a custom chat template
     * Removes a previously registered custom template
     */
    override fun unregisterCustomTemplate(name: String) {
        ChatTemplateManager.unregisterCustomTemplate(name)
    }

    override fun detectGpu(callback: (Result<GpuInfo>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        scope.launch {
            try {
                val outStats = LongArray(2) { -1L }
                val gpuName: String? = nativeDetectGpu(outStats)
                val vulkanSupported = gpuName != null
                val apiVersion = outStats[0]
                val deviceLocalMemory = outStats[1]

                val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val memInfo = ActivityManager.MemoryInfo()
                activityManager.getMemoryInfo(memInfo)
                val freeRamBytes = memInfo.availMem

                val recommendedGpuLayers = computeRecommendedLayers(
                    vulkanSupported = vulkanSupported,
                    freeRamBytes = freeRamBytes,
                    deviceLocalMemoryBytes = deviceLocalMemory
                )

                withContext(Dispatchers.Main) {
                    callback(Result.success(GpuInfo(
                        vulkanSupported = vulkanSupported,
                        gpuName = gpuName ?: "None",
                        vulkanApiVersion = apiVersion,
                        deviceLocalMemoryBytes = deviceLocalMemory,
                        freeRamBytes = freeRamBytes,
                        recommendedGpuLayers = recommendedGpuLayers.toLong()
                    )))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.success(GpuInfo(
                        vulkanSupported = false,
                        gpuName = "None",
                        vulkanApiVersion = -1L,
                        deviceLocalMemoryBytes = -1L,
                        freeRamBytes = -1L,
                        recommendedGpuLayers = 0L
                    )))
                }
            }
        }
    }

    private fun ensureNativeLoaded(): Throwable? {
        nativeLoadError?.let { return it }

        return try {
            System.loadLibrary("llama_jni")
            nativeLoaded = true
            null
        } catch (t: Throwable) {
            nativeLoadError = t
            Log.e(TAG, "Failed to load llama native library", t)
            IllegalStateException("Failed to load llama native library: ${t.message}", t)
        }
    }

    private fun computeRecommendedLayers(
        vulkanSupported: Boolean,
        freeRamBytes: Long,
        deviceLocalMemoryBytes: Long
    ): Int {
        val GB = 1_073_741_824L
        val safeRam = (freeRamBytes * 0.7).toLong()
        // No blanket vendor ban. A "Mali -> 0" rule used to live here, which zeroed
        // every ARM GPU (a Mali-G615 on a Dimensity 7300 included) before the caller
        // ever saw a number. Memory is what actually decides how many layers fit;
        // whether the offload is worth it on a given GPU is the caller's call, and
        // the user can always override the tier from Settings.
        return when {
            !vulkanSupported -> 0
            safeRam < GB -> 0                                          // < 1 GB — truly too low
            safeRam < 2 * GB && deviceLocalMemoryBytes < 3 * GB -> 0  // low RAM + low VRAM
            safeRam < 3 * GB || deviceLocalMemoryBytes < 2 * GB -> 16 // partial offload
            else -> 99                                                  // full offload
        }
    }

    // Native methods
    private external fun nativeSetComputeAffinity(mask: Int)

    private external fun nativeLoadModel(
        path: String,
        nThreads: Long,
        contextSize: Long,
        nGpuLayers: Long,
        progressCallback: (Double) -> Unit
    )

    private external fun nativeGenerate(
        prompt: String,
        maxTokens: Long,
        temperature: Double,
        topP: Double,
        topK: Long,
        minP: Double,
        typicalP: Double,
        repeatPenalty: Double,
        frequencyPenalty: Double,
        presencePenalty: Double,
        repeatLastN: Long,
        mirostat: Long,
        mirostatTau: Double,
        mirostatEta: Double,
        seed: Long,
        penalizeNewline: Boolean,
        tokenCallback: (String) -> Unit
    )

    private external fun nativeStop()
    private external fun nativeFreeModel()
    private external fun nativeGetTokensUsed(): Int
    private external fun nativeGetContextSize(): Int
    private external fun nativeClearContext()
    private external fun nativeSetSystemPromptLength(length: Int)
    private external fun nativeDetectGpu(outStats: LongArray): String?
    private external fun nativeMediaMarker(): String
    private external fun nativeDrainLog(): Array<String>
    private external fun nativeLoadMmproj(path: String, useGpu: Boolean, nThreads: Int): Int
    private external fun nativeFreeMmproj()
    private external fun nativeAudioSampleRate(): Int
    private external fun nativeSetMedia(paths: Array<String>)
    // Applies the chat template embedded in the loaded model's GGUF. Returns ""
    // when the model ships none, so callers can fall back to name sniffing.
    private external fun nativeApplyChatTemplate(roles: Array<String>, contents: Array<String>): String
    private external fun nativeGetMeta(key: String): String
    // Header-only GGUF read (no model load) for the model-card spec line.
    private external fun nativeProbeGgufFile(path: String): String
    // Encoder surface. nativeEncoderInfo returns a JSON string describing the
    // loaded model's pooling type and class labels; nativeEncode pools one
    // sequence and returns the resulting values, blocking in llama_decode.
    // DoubleArray and not FloatArray: the model computes in float, but every
    // API on the other end of this speaks double and the stdlib has no
    // FloatArray.toDoubleArray() to convert with.
    private external fun nativeEncoderInfo(): String
    private external fun nativeEncode(text: String, query: String): DoubleArray?
    // Decision surface. nativeDecisionScores runs one forward pass over `prompt`
    // and returns the raw logit of each id in `tokenIds`, at the last position,
    // in the order asked. No softmax here on purpose: temperature and bucket
    // choice are policy, and policy in C++ cannot be tested without a device.
    private external fun nativeDecisionScores(prompt: String, slotIndices: IntArray, tokenIds: IntArray): DoubleArray?
    // nativeTokenizeSingle returns the one token id for `text`, or -1 when it is
    // not a single token, writing the token count to outN[0] so the caller can
    // say which of "two tokens" and "no tokens" it hit. Needed because a
    // decision readout is defined over token ids and the caller cannot invent
    // them: "A" is one token in one vocabulary and two in another.
    private external fun nativeTokenizeSingle(text: String, outN: IntArray): Int
    // outStats[0] = vulkanApiVersion, outStats[1] = deviceLocalMemoryBytes
}
