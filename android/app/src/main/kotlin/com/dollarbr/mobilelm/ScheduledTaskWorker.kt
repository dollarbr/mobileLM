package com.dollarbr.mobilelm

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID

class ScheduledTaskWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        val taskId = inputData.getString(KEY_TASK_ID) ?: return Result.failure()
        val taskName = inputData.getString(KEY_TASK_NAME) ?: "Task"
        val prompt = inputData.getString(KEY_PROMPT) ?: ""
        val modelPath = inputData.getString(KEY_MODEL_PATH) ?: ""
        val modelName = inputData.getString(KEY_MODEL_NAME)

        appendResult(
            taskId = taskId,
            output = "PENDING: ${
                if (modelName.isNullOrBlank()) modelPath else "$modelName|$modelPath"
            }|||$prompt"
        )

        return Result.success()
    }

    private fun appendResult(taskId: String, output: String) {
        @Suppress("UNCHECKED_CAST")
        try {
            val resultsFile = File(context.filesDir, "scheduled_results.json")
            val list = mutableListOf<Map<String, Any?>>()
            if (resultsFile.exists()) {
                FileInputStream(resultsFile).use { fis ->
                    val json = fis.bufferedReader().readText()
                    if (json.isNotBlank()) {
                        val raw = org.json.JSONArray(json)
                        for (i in 0 until raw.length()) {
                            val obj = raw.getJSONObject(i)
                            @Suppress("UNCHECKED_CAST")
                            list.add(obj.toMap() as Map<String, Any?>)
                        }
                    }
                }
            }
            list.add(
                mapOf(
                    "id" to UUID.randomUUID().toString(),
                    "taskId" to taskId,
                    "taskName" to inputData.getString(KEY_TASK_NAME),
                    "at" to java.time.Instant.now().toString(),
                    "output" to output,
                    "drained" to false,
                ),
            )
            FileOutputStream(resultsFile).use { fos ->
                fos.write(org.json.JSONArray(list).toString().toByteArray())
            }
        } catch (e: RuntimeException) {
            Log.w(TAG, "Failed to append scheduled result: $e")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun org.json.JSONObject.toMap(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        keys().forEach { key ->
            map[key] = when (val value = this.get(key)) {
                org.json.JSONObject.NULL -> null
                is org.json.JSONObject -> value.toMap()
                is org.json.JSONArray -> {
                    val list = mutableListOf<Any?>()
                    for (i in 0 until value.length()) {
                        val item = value.get(i)
                        list.add(
                            when (item) {
                                org.json.JSONObject.NULL -> null
                                is org.json.JSONObject -> item.toMap()
                                is org.json.JSONArray -> item.toList()
                                else -> item
                            },
                        )
                    }
                    list
                }
                else -> value
            }
        }
        return map
    }

    private fun org.json.JSONArray.toList(): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until this.length()) {
            val item = this.get(i)
            list.add(
                when (item) {
                    org.json.JSONObject.NULL -> null
                    is org.json.JSONObject -> item.toMap()
                    is org.json.JSONArray -> item.toList()
                    else -> item
                },
            )
        }
        return list
    }

    companion object {
        const val TAG = "ScheduledTaskWorker"
        const val KEY_TASK_ID = "taskId"
        const val KEY_TASK_NAME = "taskName"
        const val KEY_PROMPT = "prompt"
        const val KEY_MODEL_PATH = "modelPath"
        const val KEY_MODEL_NAME = "modelName"
    }
}
