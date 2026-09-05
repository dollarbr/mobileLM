package com.dollarbr.mobilelm

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import rikka.shizuku.Shizuku

/**
 * The one privileged path. There is no interface here on purpose: a second
 * provider (root) was ruled out by product decision, and an interface with a
 * single implementation is speculative abstraction.
 */
class ShizukuShell(private val context: Context) {

    private var service: IPrivilegedService? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = IPrivilegedService.Stub.asInterface(binder)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
        }
    }

    private val userServiceArgs by lazy {
        Shizuku.UserServiceArgs(
            ComponentName(context.packageName, PrivilegedUserService::class.java.name),
        ).daemon(false).processNameSuffix("privileged").version(1)
    }

    fun probe(): Map<String, Any> {
        if (!isInstalled()) return mapOf("state" to "notInstalled", "identity" to "")
        if (!pingSafely()) return mapOf("state" to "stopped", "identity" to "")
        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
            return mapOf("state" to "needsPermission", "identity" to "")
        }
        bindIfNeeded()
        val uid = try {
            Shizuku.getUid()
        } catch (_: Throwable) {
            2000
        }
        return mapOf(
            "state" to "ready",
            "identity" to if (uid == 0) "root 0" else "shell $uid",
        )
    }

    fun requestPermission(code: Int) {
        try {
            Shizuku.requestPermission(code)
        } catch (_: Throwable) {
            // Binder died between the probe and the tap; the next probe reports it.
        }
    }

    fun run(argv: List<String>, timeoutMs: Long): Map<String, Any> {
        bindIfNeeded()
        val svc = service
            ?: return mapOf(
                "stdout" to "",
                "stderr" to "the Shizuku service is not bound yet — try again",
                "exit" to -1,
            )
        return try {
            val out = svc.exec(argv, timeoutMs)
            mapOf(
                "stdout" to (out.getOrNull(0) ?: ""),
                "stderr" to (out.getOrNull(1) ?: ""),
                "exit" to ((out.getOrNull(2) ?: "-1").toIntOrNull() ?: -1),
            )
        } catch (t: Throwable) {
            mapOf(
                "stdout" to "",
                "stderr" to (t.message ?: t.javaClass.simpleName),
                "exit" to -1,
            )
        }
    }

    private fun bindIfNeeded() {
        if (service != null) return
        try {
            Shizuku.bindUserService(userServiceArgs, connection)
        } catch (_: Throwable) {
            // Not running, or permission revoked since the probe.
        }
    }

    private fun pingSafely(): Boolean = try {
        Shizuku.pingBinder()
    } catch (_: Throwable) {
        false
    }

    private fun isInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private companion object {
        const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
    }
}
