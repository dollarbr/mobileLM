package com.dollarbr.litert_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.ai.edge.litert.Accelerator
import com.google.ai.edge.litert.CompiledModel
import com.google.ai.edge.litert.Environment
import com.google.ai.edge.litert.LiteRtException
import com.google.ai.edge.litert.TensorBuffer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * LiteRT 2.2.0 for `.tflite` models.
 *
 * ## Why a separate plugin from `flutter_litert_lm`
 *
 * They are two different runtimes that happen to share a name in Google's
 * repository. `litertlm-android` is LiteRT-**LM**: a generative engine that
 * takes a prompt and streams tokens, driven by `Backend.{cpu,gpu,npu}`. This is
 * LiteRT (formerly TensorFlow Lite): a tensor interpreter, driven by
 * `CompiledModel` and a map of named input and output buffers. A classification
 * head is the second kind and a GGUF is the first. Bundling them would mean one
 * plugin that carries 46 MB of natives to serve a 1 MB classifier.
 *
 * ## The accelerator, and the one thing this cannot report
 *
 * `CompiledModel` has **no getter for the accelerator it actually used**. The
 * class exposes `Options` (what to ask for) and nothing that reads back what
 * LiteRT did with the request, and LiteRT falls back internally when the
 * requested accelerator is unavailable.
 *
 * That matters because this project's rule is to report the backend that
 * actually ran, not the one that was asked for. The honest thing here is to
 * report what the device can do and what was requested, and to say in the
 * response that the executed accelerator is not exposed. LiteRT does log which
 * accelerator it selected (`LITERT_CL`, `CPU`), so on a device the real answer
 * comes from logcat — which is where every other measurement in this app comes
 * from too.
 */
class LiteRtPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private companion object {
        const val CHANNEL = "com.dollarbr.mobilelm/litert"
        const val TAG = "LiteRt"
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private val main = Handler(Looper.getMainLooper())

    /**
     * One thread, on purpose.
     *
     * `CompiledModel.create` and `run` are blocking native calls, so they cannot
     * run on the platform thread — the MethodChannel handler does. A pool would
     * let a load and a run overlap on the same model, and a `TensorBuffer` is
     * owned by one inference at a time; the failure would be a native crash
     * rather than an exception anyone could read. Serialising is also what the
     * server's `_busy` flag assumes.
     */
    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "litert").apply { isDaemon = true }
    }

    private var env: Environment? = null
    private var model: CompiledModel? = null
    private var loadedPath: String? = null
    private var requested: List<String> = emptyList()

    /** Set while a native call is in flight, so `unload` cannot pull the model
     * out from under it. */
    private val busy = AtomicBoolean(false)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler(this@LiteRtPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdown()
        releaseModel()
        // `Environment` extends JniHandle and its `destroy()` is protected —
        // there is no public way to free the environment, and the handle is
        // released when the process is. Not calling it is the API's choice, not
        // an oversight, so this says so rather than reaching for a subclass.
        env = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availableAccelerators" -> availableAccelerators(result)
            // Named `loadModel`, not `load`, to match the Dart side. This was
            // `load` and the Dart side called `loadModel`, so every load fell
            // through to `notImplemented()` and Flutter reported it as
            // MissingPluginException — whose message on the Dart side points at
            // plugin *registration*, which is the one thing that was fine.
            "loadModel" -> background(result) { reply -> loadModel(call, reply) }
            "run" -> background(result) { reply -> run(call, reply) }
            "unload" -> background(result) { reply -> unload(reply) }
            else -> result.notImplemented()
        }
    }

    // ── environment ────────────────────────────────────────────────────────

    /**
     * What this device can actually do.
     *
     * `Environment.getAvailableAccelerators()` is the device's own answer and it
     * is already filtered by what LiteRT could load — a GPU with no OpenCL does
     * not appear. That makes it the only accelerator fact in this plugin that is
     * not a request, and it is the one worth having in the UI: a phone that
     * lists CPU alone cannot be talked into a GPU path.
     */
    private fun availableAccelerators(result: MethodChannel.Result) {
        val e = try {
            environment()
        } catch (t: Throwable) {
            result.error(
                "environment_failed",
                "LiteRT environment could not be created: ${t.message}",
                null
            )
            return
        }
        val available = e.getAvailableAccelerators().map { it.name }
        result.success(
            mapOf(
                "available" to available,
                "hasGpu" to (Accelerator.GPU in e.getAvailableAccelerators()),
                "hasCpu" to (Accelerator.CPU in e.getAvailableAccelerators()),
            )
        )
    }

    private fun environment(): Environment {
        env?.let { return it }
        val ctx = context
            ?: throw IllegalStateException(
                "Plugin detached from the engine, so there is no Context to " +
                    "create a LiteRT environment with. Call availableAccelerators " +
                    "only after the plugin is attached."
            )
        val created = Environment.create(ctx)
        env = created
        return created
    }

    // ── load ───────────────────────────────────────────────────────────────

    private fun loadModel(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("bad_arguments", "'path' is required.", null)
            return
        }
        val file = java.io.File(path)
        if (!file.exists()) {
            result.error(
                "not_found",
                "No file at $path. A .tflite reaches the app through the model " +
                    "directory, and 'adb push' into /data/local/tmp does not get " +
                    "it there — run-as and cp, as the push guide says.",
                null
            )
            return
        }

        val accelNames = call.argument<List<String>>("accelerators")
            ?: listOf("CPU")
        val accelerators = accelNames.mapNotNull {
            try {
                Accelerator.valueOf(it)
            } catch (_: IllegalArgumentException) {
                null
            }
        }
        if (accelerators.isEmpty()) {
            result.error(
                "bad_accelerator",
                "None of $accelNames is an accelerator LiteRT knows. " +
                    "It has NONE, CPU, GPU and NPU.",
                null
            )
            return
        }

        val available = try {
            environment().getAvailableAccelerators()
        } catch (t: Throwable) {
            result.error(
                "environment_failed",
                "Could not read the device's accelerators: ${t.message}",
                null
            )
            return
        }

        // Asking for an accelerator the device does not have is not an error
        // LiteRT reports usefully — it quietly compiles for CPU. Logging the
        // request against the device is the only place the substitution becomes
        // visible before the numbers come back.
        val unavailable = accelerators.filterNot { it in available }
        if (unavailable.isNotEmpty()) {
            Log.w(
                TAG,
                "asked for ${unavailable.map { it.name }} and the device " +
                    "reports only ${available.map { it.name }}; LiteRT will " +
                    "compile for what it has. The response will not claim " +
                    "the requested accelerator ran."
            )
        }

        releaseModel()

        val options = CompiledModel.Options(*accelerators.toTypedArray())
        val numThreads = call.argument<Int>("numThreads") ?: 0
        if (numThreads > 0) {
            options.cpuOptions = CompiledModel.CpuOptions(numThreads = numThreads)
        }
        // FP32 with an explicit OpenCL backend. The precision is not a default:
        // a graph that was quantised to fp16 weights still has fp32
        // activations, and letting the runtime pick has it silently demote
        // those to fp16 on a GPU that cannot accumulate in fp32 — which is a
        // wrong answer, not a fast one.
        options.gpuOptions = CompiledModel.GpuOptions(
            backend = CompiledModel.GpuOptions.Backend.OPENCL,
            precision = CompiledModel.GpuOptions.Precision.FP32
        )

        val started = System.nanoTime()
        val compiled = try {
            CompiledModel.create(file.absolutePath, options, environment())
        } catch (e: LiteRtException) {
            result.error(
                "compile_failed",
                "LiteRT refused ${file.name}: ${e.message}",
                null
            )
            return
        } catch (t: Throwable) {
            result.error("compile_failed", "${file.name}: ${t}", null)
            return
        }
        val compileMs = (System.nanoTime() - started) / 1_000_000

        model = compiled
        loadedPath = file.absolutePath
        requested = accelerators.map { it.name }
        Log.i(
            TAG,
            "compiled ${file.name} in ${compileMs}ms; requested " +
                "${requested.joinToString()}, device reports " +
                "${available.map { it.name }}, executed accelerator NOT " +
                "exposed by the API — read LITERT_CL or CPU from logcat"
        )
        result.success(
            mapOf(
                "path" to file.absolutePath,
                "compileMillis" to compileMs,
                "requested" to requested,
                "available" to available.map { it.name },
                "requestedButUnavailable" to unavailable.map { it.name },
                // Deliberately absent: an "accelerator" key. Reporting the
                // request under that name is how a caller ends up displaying
                // "GPU" on a device that compiled for CPU.
                "executedAccelerator" to null,
                "executedAcceleratorNote" to
                    "LiteRT 2.2.0's CompiledModel does not expose the " +
                    "accelerator it used. Read LITERT_CL or CPU from logcat.",
            )
        )
    }

    // ── run ────────────────────────────────────────────────────────────────

    private fun run(call: MethodCall, result: MethodChannel.Result) {
        val m = model
        if (m == null) {
            result.error(
                "no_model",
                "No .tflite loaded. POST nothing — load one first.",
                null
            )
            return
        }
        val signature = call.argument<String>("signature") ?: "serving_default"

        val rawInputs = call.argument<Map<String, Any?>>("inputs")
        if (rawInputs == null) {
            result.error(
                "bad_arguments",
                "'inputs' is required: a map of tensor name to Float32List.",
                null
            )
            return
        }
        // Checked here rather than cast blindly, because a host that sends a
        // List<double> gets a ClassCastException inside the cast — three frames
        // below the call that caused it — instead of an error naming the tensor.
        val inputs = LinkedHashMap<String, FloatArray>(rawInputs.size)
        for ((name, value) in rawInputs) {
            val arr = when (value) {
                is FloatArray -> value
                else -> {
                    result.error(
                        "bad_input",
                        "Input '$name' arrived as ${value?.javaClass?.simpleName}, " +
                            "not a Float32List. A List<double> crosses the channel " +
                            "element by element and has to be converted first.",
                        null
                    )
                    return
                }
            }
            inputs[name!!] = arr
        }

        val outputNames = call.argument<List<String>>("outputNames")
        if (outputNames == null) {
            result.error(
                "bad_arguments",
                "'outputNames' is required. The LiteRT API has no way to list a " +
                    "signature's outputs, so the caller has to name them.",
                null
            )
            return
        }

        val inBuffers = LinkedHashMap<String, TensorBuffer>()
        val outBuffers = LinkedHashMap<String, TensorBuffer>()
        // **One `finally` for every exit from here on**, including the four error
        // `return`s in buffer preparation. The alternative is a `closeAll` before
        // each `return`, which fixes today's four and silently reopens on the
        // fifth somebody adds later.
        //
        // This is a per-run leak, not a per-load one: a run allocates one buffer
        // per named input and one per named output, and the act head has three in
        // all. A test window that runs it a hundred times leaks three hundred
        // native handles, and nothing in the app's own bookkeeping can see it.
        // The outputs are copied into `FloatArray`s inside the block below, so
        // closing on the way out cannot lose data.
        try {
            for ((name, data) in inputs) {
                val buf: TensorBuffer? = m.createInputBuffer(name, signature)
                if (buf == null) {
                    result.error(
                        "no_such_input",
                        "Signature '$signature' has no input named '$name'. " +
                            "The names come from the model's FlatBuffer; " +
                            "do not assume index order.",
                        null
                    )
                    return
                }
                buf.writeFloat(data)
                inBuffers[name] = buf
            }
            for (name in outputNames) {
                val buf: TensorBuffer? = m.createOutputBuffer(name, signature)
                if (buf == null) {
                    result.error(
                        "no_such_output",
                        "Signature '$signature' has no output named '$name'.",
                        null
                    )
                    return
                }
                outBuffers[name] = buf
            }
        } catch (e: LiteRtException) {
            result.error("buffer_failed", "Preparing buffers: ${e.message}", null)
            return
        }

        val started = System.nanoTime()
        try {
            m.run(inBuffers, outBuffers, signature)
        } catch (e: LiteRtException) {
            result.error(
                "run_failed",
                "Inference failed: ${e.message}. A shape mismatch lands here " +
                    "too, so check the declared shapes before suspecting the " +
                    "runtime.",
                null
            )
            return
        } catch (t: Throwable) {
            result.error("run_failed", "${t}", null)
            return
        }
        val runMs = (System.nanoTime() - started) / 1_000_000

        val values = HashMap<String, FloatArray>(outBuffers.size)
        try {
            for ((name, buf) in outBuffers) {
                values[name] = buf.readFloat()
            }
        } catch (e: LiteRtException) {
            result.error("read_failed", "Reading outputs: ${e.message}", null)
            return
        } finally {
            closeAll(inBuffers.values)
            closeAll(outBuffers.values)
        }

        result.success(
            mapOf(
                "outputs" to values,
                "runMillis" to runMs,
                "signature" to signature,
                "inputBytes" to inputs.values.sumOf { it.size * 4L },
            )
        )
    }

    // ── unload ─────────────────────────────────────────────────────────────

    private fun unload(result: MethodChannel.Result) {
        val was = loadedPath
        releaseModel()
        result.success(mapOf("unloaded" to (was != null), "path" to was))
    }

    /**
     * Release the compiled model **and the memory it holds**.
     *
     * The three assignments below are what this used to be, and they were a
     * silence. `CompiledModel` extends `JniHandle`, which is `AutoCloseable`,
     * and its `close()` is what calls the native `destroy()`. A nulled reference
     * does not free the graph — it defers the free to a finalizer, if the object
     * ever becomes unreachable and if that finalizer runs, which is not a promise
     * anyone should make on a phone whose low-memory killer decides what
     * survives.
     *
     * It matters more here than it looks. The LiteRT model lives in its own
     * plugin and its own `.so`, so unloading frees only what *this* plugin
     * allocated — and a caller unloading a 705 MB graph is expecting that number
     * to come back. Without the `close()`, the route answers 200 and the phone is
     * still holding the graph.
     *
     * The `try` is here because the alternative is an exception escaping during a
     * load that is already failing for some other reason, and the real failure
     * would then be reported as an unload failure.
     */
    private fun releaseModel() {
        val held = model
        model = null
        loadedPath = null
        requested = emptyList()
        if (held != null) {
            try {
                held.close()
                Log.i(TAG, "released the compiled model")
            } catch (t: Throwable) {
                // Logged, not thrown: a failed free must not look like a failed
                // load, and the reference is gone either way.
                Log.w(TAG, "CompiledModel.close() threw: ${t.message}")
            }
        }
    }

    /**
     * Close a set of buffers, never throwing.
     *
     * `TensorBuffer` is a `JniHandle` as well, so these are real native handles
     * and a run that does not close them leaks one per input and one per output.
     */
    private fun closeAll(buffers: Collection<TensorBuffer>) {
        for (b in buffers) {
            try {
                b.close()
            } catch (t: Throwable) {
                Log.w(TAG, "TensorBuffer.close() threw: ${t.message}")
            }
        }
    }

    /**
     * Run a blocking native call off the platform thread and answer on it.
     *
     * The MethodChannel handler already runs on the platform thread, and
     * `CompiledModel.create` for a 700 MB graph takes seconds. Calling it there
     * is an ANR, and the symptom an app sees is the whole UI freezing with no
     * error anywhere — so the hop is not an optimisation, it is the difference
     * between working and not.
     */
    private fun background(result: MethodChannel.Result, body: (MethodChannel.Result) -> Unit) {
        if (!busy.compareAndSet(false, true)) {
            result.error(
                "busy",
                "A LiteRT call is already running. One model, one inference at a " +
                    "time — a TensorBuffer belongs to exactly one run.",
                null
            )
            return
        }
        // Every body below answers through this, never through `result` directly.
        // A MethodChannel.Result must be called on the platform thread, and every
        // body runs on the worker; answering from the worker is what Flutter
        // throws on, and it fails as an engine-level complaint with the plugin's
        // own error nowhere in the message.
        val reply = OnPlatformThread(main, result)
        worker.execute {
            try {
                body(reply)
            } catch (t: Throwable) {
                reply.error(
                    "plugin_error",
                    "${t::class.simpleName}: ${t.message}",
                    null
                )
            } finally {
                busy.set(false)
            }
        }
    }

    /**
     * Wraps a [MethodChannel.Result] so every reply hops to the platform thread.
     *
     * Wrapping once at the boundary is cheaper than remembering the hop at each
     * of the eight call sites, and a missed hop is a confusing failure rather
     * than an obvious one.
     */
    private class OnPlatformThread(
        private val main: Handler,
        private val delegate: MethodChannel.Result,
    ) : MethodChannel.Result {
        // Block bodies, not expression bodies: `Handler.post` returns Boolean,
        // and `= main.post { ... }` would make the override's return type
        // Boolean where the interface declares Unit.
        override fun success(result: Any?) {
            main.post { delegate.success(result) }
        }

        override fun error(code: String, message: String?, details: Any?) {
            main.post { delegate.error(code, message, details) }
        }

        override fun notImplemented() {
            main.post { delegate.notImplemented() }
        }
    }
}
