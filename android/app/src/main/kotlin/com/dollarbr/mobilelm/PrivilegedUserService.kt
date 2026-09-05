package com.dollarbr.mobilelm

import android.os.Process
import java.util.concurrent.TimeUnit
import kotlin.system.exitProcess

/**
 * Runs in Shizuku's process, so under uid 2000 (or 0 when the user started
 * Shizuku as root). Executes an argv array directly — no shell is spawned, so
 * a metacharacter in an argument is only ever a literal. That is the property
 * the Dart-side validation is written to preserve; do not "simplify" this into
 * sh -c.
 */
class PrivilegedUserService : IPrivilegedService.Stub() {

    override fun exec(argv: List<String>?, timeoutMs: Long): List<String> {
        val args = argv ?: emptyList()
        if (args.isEmpty()) return listOf("", "empty argv", "-1")
        return try {
            val process = ProcessBuilder(args).redirectErrorStream(false).start()
            val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            if (!finished) {
                process.destroyForcibly()
                return listOf("", "timed out after ${timeoutMs}ms", "-1")
            }
            listOf(
                process.inputStream.bufferedReader().readText(),
                process.errorStream.bufferedReader().readText(),
                process.exitValue().toString(),
            )
        } catch (t: Throwable) {
            listOf("", t.message ?: t.javaClass.simpleName, "-1")
        }
    }

    override fun callerUid(): Int = Process.myUid()

    override fun destroy() {
        exitProcess(0)
    }
}
