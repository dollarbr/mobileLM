package com.dollarbr.mobilelm

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.TimeUnit

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED || action == "android.intent.action.QUICKBOOT_POWERON") {
            rescheduleAll(context)
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            launchIntent?.let { context.startActivity(it) }
        }
    }

    companion object {
        const val TAG = "BootReceiver"

        fun rescheduleAll(context: Context) {
            try {
                val tasksFile = File(context.filesDir, "scheduled_tasks.json")
                if (!tasksFile.exists()) return
                val raw = FileInputStream(tasksFile).bufferedReader().readText()
                if (raw.isBlank()) return
                val arr = JSONArray(raw)
                val workManager = WorkManager.getInstance(context)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    if (obj.optBoolean("enabled", true)) {
                        scheduleTaskFromJson(context, workManager, obj)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "rescheduleAll failed: $e")
            }
        }

        fun scheduleTaskFromJson(context: Context, workManager: WorkManager, obj: JSONObject) {
            val id = obj.optString("id").ifEmpty { return }
            val name = obj.optString("name").ifEmpty { return }
            val prompt = obj.optString("prompt")
            val modelPath = obj.optString("modelPath")
            val modelName = obj.optString("modelName", null)
            val hour = obj.optInt("hour", -1)
            val minute = obj.optInt("minute", -1)
            if (hour < 0 || minute < 0 || prompt.isEmpty() || modelPath.isEmpty()) return

            val trigger = computeInitialDelay(hour, minute)
            val input = androidx.work.Data.Builder()
                .putString(ScheduledTaskWorker.KEY_TASK_ID, id)
                .putString(ScheduledTaskWorker.KEY_TASK_NAME, name)
                .putString(ScheduledTaskWorker.KEY_PROMPT, prompt)
                .putString(ScheduledTaskWorker.KEY_MODEL_PATH, modelPath)
                .putString(ScheduledTaskWorker.KEY_MODEL_NAME, modelName)
                .build()

            val request = PeriodicWorkRequestBuilder<ScheduledTaskWorker>(1, TimeUnit.DAYS)
                .setInputData(input)
                .setInitialDelay(trigger, TimeUnit.MILLISECONDS)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiresBatteryNotLow(true)
                        .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                        .build(),
                )
                .build()

            workManager.enqueueUniquePeriodicWork(
                "scheduled_task_$id",
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }

        fun computeInitialDelay(hour: Int, minute: Int): Long {
            val now = java.util.Calendar.getInstance()
            val fire = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, hour)
                set(java.util.Calendar.MINUTE, minute)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
                if (before(now)) add(java.util.Calendar.DATE, 1)
            }
            return fire.timeInMillis - now.timeInMillis
        }
    }
}
