package com.dollarbr.mobilelm

import android.app.AlertDialog
import android.app.AlarmManager
import android.app.DownloadManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread
import kotlin.system.exitProcess
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val importChannelName = "com.aichat.ai_chat/model_import"
    private val mediaChannelName = "com.aichat.ai_chat/media"
    private val workspaceChannelName = "com.aichat.ai_chat/workspace"
    private val schedulerChannelName = "com.aichat.ai_chat/scheduler"
    private val importRequestCode = 4207
    private val backupTreeRequestCode = 4208
    private val workspaceTreeRequestCode = 4209
    private val mainHandler = Handler(Looper.getMainLooper())

    private var importChannel: MethodChannel? = null
    private var mediaChannel: MethodChannel? = null
    private var workspaceChannel: MethodChannel? = null
    private var schedulerChannel: MethodChannel? = null
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingModelsDir: String? = null
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingWorkspaceResult: MethodChannel.Result? = null
    private val monitoredInAppDownloads = ConcurrentHashMap.newKeySet<Long>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, importChannelName)
        importChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAndImportModel" -> {
                    if (pendingImportResult != null) {
                        result.error("IMPORT_BUSY", "Another model import is already running.", null)
                        return@setMethodCallHandler
                    }
                    val modelsDir = call.argument<String>("modelsDir")
                    if (modelsDir.isNullOrBlank()) {
                        result.error("INVALID_DIR", "Models directory is missing.", null)
                        return@setMethodCallHandler
                    }
                    pendingModelsDir = modelsDir
                    pendingImportResult = result
                    openModelPicker()
                }
                "downloadToDownloads" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    if (url.isNullOrBlank() || filename.isNullOrBlank()) {
                        result.error("INVALID_DOWNLOAD", "Model URL or filename is missing.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val downloadId = enqueueDownloadToDownloads(url, filename)
                        result.success(mapOf("downloadId" to downloadId, "filename" to sanitizeFilename(filename)))
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "cancelDownloadToDownloads" -> {
                    val downloadId = (call.argument<Any>("downloadId") as? Number)?.toLong()
                    if (downloadId != null) {
                        try {
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            manager.remove(downloadId)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CANCEL_FAILED", e.message ?: e.toString(), null)
                        }
                    } else {
                        result.error("INVALID_DOWNLOAD_ID", "Download ID is missing.", null)
                    }
                }
                "downloadModelInApp" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    val modelsDir = call.argument<String>("modelsDir")
                    if (url.isNullOrBlank() || filename.isNullOrBlank() || modelsDir.isNullOrBlank()) {
                        result.error("INVALID_DOWNLOAD", "URL, filename, or modelsDir is missing.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val downloadId = enqueueDownloadInApp(url, filename, modelsDir)
                        result.success(mapOf("downloadId" to downloadId, "filename" to sanitizeFilename(filename)))
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "cancelDownloadInApp" -> {
                    val downloadId = (call.argument<Any>("downloadId") as? Number)?.toLong()
                    if (downloadId != null) {
                        try {
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            manager.remove(downloadId)
                            removeInAppDownload(downloadId)
                            val filename = call.argument<String>("filename")
                            if (!filename.isNullOrBlank()) {
                                val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), sanitizeFilename(filename))
                                if (destFile.exists()) destFile.delete()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CANCEL_FAILED", e.message ?: e.toString(), null)
                        }
                    } else {
                        result.error("INVALID_DOWNLOAD_ID", "Download ID is missing.", null)
                    }
                }
                "getActiveDownloads" -> {
                    thread(name = "download-inapp-reconcile") {
                        try {
                            val activeList = reconcileInAppDownloads()
                            mainHandler.post { result.success(activeList) }
                        } catch (e: java.lang.Exception) {
                            mainHandler.post {
                                result.error("QUERY_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                // Scoped storage: writes outside app dirs only work through a
                // SAF directory grant. The tree URI is persisted, so the user
                // picks the backup folder once and every later backup goes
                // straight to it.
                "pickBackupTree" -> {
                    if (pendingBackupResult != null) {
                        result.error("BACKUP_BUSY", "A folder pick is already running.", null)
                        return@setMethodCallHandler
                    }
                    pendingBackupResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                 Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                 Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                 Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                    }
                    startActivityForResult(intent, backupTreeRequestCode)
                }
                "copyToTree" -> {
                    val treeUri = call.argument<String>("treeUri")
                    val name = call.argument<String>("name")
                    val srcPath = call.argument<String>("sourcePath")
                    val parentDocUri = call.argument<String>("parentDocUri")
                    if (treeUri.isNullOrBlank() || name.isNullOrBlank() || srcPath.isNullOrBlank()) {
                        result.error("INVALID_BACKUP", "treeUri, name and sourcePath are required.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "backup-copy") {
                        try {
                            val parent = if (parentDocUri.isNullOrBlank()) null else Uri.parse(parentDocUri)
                            val bytes = copyFileToTree(Uri.parse(treeUri), name, srcPath, parent)
                            // -1 means an identical file is already there.
                            mainHandler.post {
                                result.success(mapOf(
                                    "bytes" to if (bytes < 0) 0 else bytes,
                                    "skipped" to (bytes < 0)
                                ))
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("COPY_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "copyFromTree" -> {
                    val treeUri = call.argument<String>("treeUri")
                    val relativePath = call.argument<String>("relativePath")
                    val name = call.argument<String>("name")
                    val destPath = call.argument<String>("destPath")
                    if (treeUri.isNullOrBlank() || name.isNullOrBlank() || destPath.isNullOrBlank()) {
                        result.error("INVALID_RESTORE", "treeUri, name and destPath are required.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "restore-copy") {
                        try {
                            val bytes = copyFromTree(Uri.parse(treeUri), relativePath, name, destPath)
                            mainHandler.post { result.success(mapOf("bytes" to bytes)) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("RESTORE_COPY_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                // Nested path creation following the user's on-disk layout,
                // e.g. LLMs/Google/Gemma3 — missing levels are created.
                "ensureTreePath" -> {
                    val treeUri = call.argument<String>("treeUri")
                    @Suppress("UNCHECKED_CAST")
                    val segments = call.argument<List<String>>("segments") ?: emptyList()
                    if (treeUri.isNullOrBlank() || segments.isEmpty()) {
                        result.error("INVALID_PATH", "treeUri and segments are required.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "backup-mkdir-path") {
                        try {
                            val doc = ensureTreePath(Uri.parse(treeUri), segments)
                            mainHandler.post { result.success(doc?.toString()) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("PATH_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "listTreeRecursive" -> {
                    val treeUri = call.argument<String>("treeUri")
                    val extensions = call.argument<List<String>>("extensions") ?: emptyList()
                    if (treeUri.isNullOrBlank()) {
                        result.error("INVALID_LIST", "treeUri is required.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "backup-walk") {
                        try {
                            val items = listTreeRecursive(
                                Uri.parse(treeUri),
                                extensions.map { it.lowercase() }.toSet(),
                                mutableListOf("settings")
                            )
                            mainHandler.post { result.success(items) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("LIST_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "restartApp" -> {
                    restartApp()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
        mediaChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // Decoding happens off the main thread: a long clip on a slow
                // hardware decoder would otherwise drop frames in the UI.
                // LiteRT-LM only reads WAV, so anything else is decoded here
                // first. Off the main thread: a long clip takes seconds.
                "audioToWav" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_AUDIO", "Audio path is missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "audio-to-wav") {
                        try {
                            val wav = AudioToWav.convert(path, File(cacheDir, "audio_wav"))
                            mainHandler.post { result.success(wav) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("AUDIO_CONVERT_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "extractVideoFrames" -> {
                    val path = call.argument<String>("path")
                    val maxFrames = (call.argument<Any>("maxFrames") as? Number)?.toInt() ?: 4
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_VIDEO", "Video path is missing.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "video-frames") {
                        try {
                            val frames = VideoFrames.extract(
                                path,
                                maxFrames,
                                File(cacheDir, "video_frames"),
                            )
                            mainHandler.post { result.success(frames) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("VIDEO_FRAMES_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Workspace channel: generic CRUD against a SAF directory tree. The
        // workspace root is chosen once via the native folder picker and kept
        // as a persisted tree URI; every project folder lives underneath it.
        workspaceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            workspaceChannelName
        )
        workspaceChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "wsPickWorkspace" -> {
                    if (pendingWorkspaceResult != null) {
                        result.error("WS_BUSY", "A folder pick is already running.", null)
                        return@setMethodCallHandler
                    }
                    pendingWorkspaceResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                 Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                 Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                 Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                    }
                    startActivityForResult(intent, workspaceTreeRequestCode)
                }
                // NOTE: this channel is used for lightweight UI + tool calls.
                // Heavy compute (list/read/write) is cheap at workspace scale, so
                // it runs directly on the platform thread for simplicity and to
                // avoid interleaving writes with the model import threads.
                "wsListDir" -> {
                    val tree = call.argument<String>("treeUri")
                    val rel = call.argument<String>("relPath") ?: ""
                    if (tree.isNullOrBlank()) {
                        result.error("WS_INVALID", "treeUri is required.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(listWorkspaceDir(Uri.parse(tree), rel))
                    } catch (e: Exception) {
                        result.error("WS_LIST_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "wsMkdir" -> {
                    val tree = call.argument<String>("treeUri")
                    val rel = call.argument<String>("relPath") ?: ""
                    if (tree.isNullOrBlank() || rel.isBlank()) {
                        result.error("WS_INVALID", "treeUri and relPath are required.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val docId = resolveWorkspacePath(Uri.parse(tree), rel, create = true, isDir = true)
                        result.success(docId)
                    } catch (e: Exception) {
                        result.error("WS_MKDIR_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "wsReadFile" -> {
                    val tree = call.argument<String>("treeUri")
                    val rel = call.argument<String>("relPath") ?: ""
                    if (tree.isNullOrBlank() || rel.isBlank()) {
                        result.error("WS_INVALID", "treeUri and relPath are required.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "ws-read") {
                        try {
                            val text = readWorkspaceFile(Uri.parse(tree), rel)
                            mainHandler.post { result.success(text) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("WS_READ_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                "wsWriteFile" -> {
                    val tree = call.argument<String>("treeUri")
                    val rel = call.argument<String>("relPath") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    if (tree.isNullOrBlank() || rel.isBlank()) {
                        result.error("WS_INVALID", "treeUri and relPath are required.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        writeWorkspaceFile(Uri.parse(tree), rel, content)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WS_WRITE_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "wsDelete" -> {
                    val tree = call.argument<String>("treeUri")
                    val rel = call.argument<String>("relPath") ?: ""
                    if (tree.isNullOrBlank() || rel.isBlank()) {
                        result.error("WS_INVALID", "treeUri and relPath are required.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val ok = deleteWorkspaceItem(Uri.parse(tree), rel)
                        result.success(ok)
                    } catch (e: Exception) {
                        result.error("WS_DELETE_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "wsRename" -> {
                    val tree = call.argument<String>("treeUri")
                    val rel = call.argument<String>("relPath") ?: ""
                    val newName = call.argument<String>("newName") ?: ""
                    if (tree.isNullOrBlank() || rel.isBlank() || newName.isBlank()) {
                        result.error("WS_INVALID", "treeUri, relPath and newName are required.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val docId = resolveWorkspacePath(Uri.parse(tree), rel, create = false, isDir = false)
                        val newUri = DocumentsContract.renameDocument(
                            contentResolver,
                            DocumentsContract.buildDocumentUriUsingTree(Uri.parse(tree), docId),
                            newName.trim()
                        )
                        if (newUri == null) {
                            result.error("WS_RENAME_FAILED", "Rename returned null.", null)
                        } else {
                            result.success(DocumentsContract.getDocumentId(newUri))
                        }
                    } catch (e: Exception) {
                        result.error("WS_RENAME_FAILED", e.message ?: e.toString(), null)
                    }
                }
                "wsListProjects" -> {
                    val tree = call.argument<String>("treeUri")
                    if (tree.isNullOrBlank()) {
                        result.error("WS_INVALID", "treeUri is required.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val projects = listWorkspaceDir(Uri.parse(tree), "")
                            .filter { it["isDir"] as? Boolean == true }
                        result.success(projects)
                    } catch (e: Exception) {
                        result.error("WS_LIST_FAILED", e.message ?: e.toString(), null)
                    }
                }
                // Copy everything under [oldTreeUri] into [newTreeUri] so the
                // user can relocate the whole workspace in Settings.
                "wsMoveWorkspace" -> {
                    val oldTree = call.argument<String>("oldTreeUri")
                    val newTree = call.argument<String>("newTreeUri")
                    if (oldTree.isNullOrBlank() || newTree.isNullOrBlank()) {
                        result.error("WS_INVALID", "oldTreeUri and newTreeUri are required.", null)
                        return@setMethodCallHandler
                    }
                    thread(name = "ws-move") {
                        try {
                            val moved = moveWorkspace(Uri.parse(oldTree), Uri.parse(newTree))
                            mainHandler.post { result.success(moved) }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error("WS_MOVE_FAILED", e.message ?: e.toString(), null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        schedulerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            schedulerChannelName
        )
        schedulerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleTask" -> {
                    val id = call.argument<String>("id")
                    val name = call.argument<String>("name")
                    val prompt = call.argument<String>("prompt")
                    val modelPath = call.argument<String>("modelPath")
                    val modelName = call.argument<String>("modelName")
                    val hour = call.argument<Int>("hour")
                    val minute = call.argument<Int>("minute")
                    if (id == null || name == null || prompt == null ||
                        modelPath == null || hour == null || minute == null) {
                        result.error("INVALID_ARGS", "Missing scheduler fields.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        requestBatteryExemptionIfNeeded()
                        val obj = org.json.JSONObject().apply {
                            put("id", id)
                            put("name", name)
                            put("prompt", prompt)
                            put("modelPath", modelPath)
                            put("modelName", modelName ?: "")
                            put("hour", hour)
                            put("minute", minute)
                            put("enabled", true)
                        }
                        BootReceiver.scheduleTaskFromJson(this, WorkManager.getInstance(this), obj)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SCHEDULE_FAILED", e.message, null)
                    }
                }
                "cancelTask" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("INVALID_ARGS", "Missing task id.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        WorkManager.getInstance(this)
                            .cancelUniqueWork("scheduled_task_$id")
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_FAILED", e.message, null)
                    }
                }
                "ensureBatteryExemption" -> {
                    requestBatteryExemptionIfNeeded()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            BootReceiver.rescheduleAll(this)
        } catch (_: Exception) {}
    }

    private fun requestBatteryExemptionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        .setData(Uri.parse("package:$packageName"))
                    startActivity(intent)
                }
            } catch (_: Exception) {}
        }
    }

    private fun restartApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent == null) {
            finishAffinity()
            return
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        val pendingIntent = PendingIntent.getActivity(
            this,
            9208,
            launchIntent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.set(
            AlarmManager.RTC,
            System.currentTimeMillis() + 350L,
            pendingIntent
        )
        finishAffinity()
        exitProcess(0)
    }

    private fun enqueueDownloadToDownloads(url: String, filename: String): Long {
        val safeName = sanitizeFilename(filename)
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle(safeName)
            setDescription("Downloading AI model")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, safeName)
            addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
            addRequestHeader("Accept", "*/*")
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = manager.enqueue(request)

        thread(name = "download-monitor-$downloadId") {
            var isFinished = false
            var lastBytes = 0L
            var lastTime = System.currentTimeMillis()
            var lastReportedSpeed = 0.0

            while (!isFinished) {
                Thread.sleep(1000)
                val query = DownloadManager.Query().setFilterById(downloadId)
                manager.query(query)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                        val bytesDownloadedIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                        val bytesTotalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)

                        if (statusIndex >= 0 && bytesDownloadedIndex >= 0 && bytesTotalIndex >= 0) {
                            val status = cursor.getInt(statusIndex)
                            val downloaded = cursor.getLong(bytesDownloadedIndex)
                            val total = cursor.getLong(bytesTotalIndex)

                            val now = System.currentTimeMillis()
                            val elapsedSeconds = (now - lastTime) / 1000.0
                            var bytesPerSecond = 0.0

                            if (downloaded > lastBytes) {
                                bytesPerSecond = if (elapsedSeconds > 0) ((downloaded - lastBytes) / elapsedSeconds) else 0.0
                                lastBytes = downloaded
                                lastTime = now
                                lastReportedSpeed = bytesPerSecond
                            } else {
                                if (elapsedSeconds > 3.0) {
                                    lastReportedSpeed = 0.0
                                }
                                bytesPerSecond = lastReportedSpeed
                            }

                            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                                isFinished = true
                                emitProgress(safeName, total, total, 0.0, "Download complete")
                            } else if (status == DownloadManager.STATUS_FAILED) {
                                isFinished = true
                                emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                            } else {
                                emitProgress(safeName, downloaded, total, bytesPerSecond, "Downloading to phone...")
                            }
                        }
                    } else {
                        isFinished = true
                        emitProgress(safeName, 0, 0, 0.0, "Download cancelled")
                    }
                } ?: run {
                    isFinished = true
                }
            }
        }
        return downloadId
    }

    private fun enqueueDownloadInApp(url: String, filename: String, modelsDir: String): Long {
        val safeName = sanitizeFilename(filename)
        val tempDownloadsDir = File(getExternalFilesDir(null), "temp_downloads")
        tempDownloadsDir.mkdirs()
        val destFile = File(tempDownloadsDir, safeName)
        if (destFile.exists()) destFile.delete()

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle(safeName)
            setDescription("Downloading local AI model")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
            setDestinationUri(Uri.fromFile(destFile))
            addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36")
            addRequestHeader("Accept", "*/*")
        }
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = manager.enqueue(request)
        persistInAppDownload(downloadId, safeName, modelsDir)
        monitorInAppDownload(downloadId, safeName, modelsDir)
        return downloadId
    }

    private fun monitorInAppDownload(downloadId: Long, safeName: String, modelsDir: String) {
        if (!monitoredInAppDownloads.add(downloadId)) return
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), safeName)
        thread(name = "download-inapp-monitor-$downloadId") {
            var isFinished = false
            var lastBytes = 0L
            var lastTime = System.currentTimeMillis()
            var lastReportedSpeed = 0.0

            while (!isFinished) {
                Thread.sleep(1000)
                val query = DownloadManager.Query().setFilterById(downloadId)
                manager.query(query)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
                        val bytesDownloadedIndex = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
                        val bytesTotalIndex = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)

                        if (statusIndex >= 0 && bytesDownloadedIndex >= 0 && bytesTotalIndex >= 0) {
                            val status = cursor.getInt(statusIndex)
                            val downloaded = cursor.getLong(bytesDownloadedIndex)
                            val total = cursor.getLong(bytesTotalIndex)

                            val now = System.currentTimeMillis()
                            val elapsedSeconds = (now - lastTime) / 1000.0
                            var bytesPerSecond = 0.0

                            if (downloaded > lastBytes) {
                                bytesPerSecond = if (elapsedSeconds > 0) ((downloaded - lastBytes) / elapsedSeconds) else 0.0
                                lastBytes = downloaded
                                lastTime = now
                                lastReportedSpeed = bytesPerSecond
                            } else {
                                if (elapsedSeconds > 3.0) {
                                    lastReportedSpeed = 0.0
                                }
                                bytesPerSecond = lastReportedSpeed
                            }

                            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                                isFinished = true
                                finalizeInAppDownload(downloadId, safeName, modelsDir, downloaded, total)
                            } else if (status == DownloadManager.STATUS_FAILED) {
                                isFinished = true
                                removeInAppDownload(downloadId)
                                emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                            } else {
                                emitProgress(safeName, downloaded, total, bytesPerSecond, "Downloading...")
                            }
                        }
                    } else {
                        isFinished = true
                        removeInAppDownload(downloadId)
                        emitProgress(safeName, 0, 0, 0.0, "Download cancelled")
                    }
                } ?: run {
                    isFinished = true
                }
            }
            monitoredInAppDownloads.remove(downloadId)
        }
    }

    private fun finalizeInAppDownload(
        downloadId: Long,
        safeName: String,
        modelsDir: String,
        downloaded: Long,
        total: Long,
    ) {
        val destFile = File(File(getExternalFilesDir(null), "temp_downloads"), safeName)
        try {
            emitProgress(safeName, downloaded, total, 0.0, "Importing to app storage...")
            val targetFile = File(modelsDir, safeName)
            targetFile.parentFile?.mkdirs()
            val partFile = File(targetFile.parentFile, "${targetFile.name}.part")
            if (partFile.exists()) partFile.delete()
            if (!destFile.exists()) {
                if (targetFile.exists() && targetFile.length() > 0L) {
                    removeInAppDownload(downloadId)
                    emitProgress(safeName, total, total, 0.0, "Download complete")
                    return
                }
                throw IllegalStateException("Downloaded temporary file is missing.")
            }
            destFile.copyTo(partFile, overwrite = true)
            if (targetFile.exists()) targetFile.delete()
            if (!partFile.renameTo(targetFile)) {
                throw IllegalStateException("Unable to finalize downloaded model.")
            }
            destFile.delete()
            removeInAppDownload(downloadId)
            emitProgress(safeName, total, total, 0.0, "Download complete")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to import downloaded model: ${e.message}", e)
            emitProgress(safeName, downloaded, total, 0.0, "Download failed: import error")
        }
    }

    private fun persistInAppDownload(downloadId: Long, filename: String, modelsDir: String) {
        val record = JSONObject()
            .put("filename", filename)
            .put("modelsDir", modelsDir)
        getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
            .edit()
            .putString(downloadId.toString(), record.toString())
            .apply()
    }

    private fun removeInAppDownload(downloadId: Long) {
        getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
            .edit()
            .remove(downloadId.toString())
            .apply()
    }

    private fun reconcileInAppDownloads(): List<Map<String, Any>> {
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val preferences = getSharedPreferences("in_app_downloads", Context.MODE_PRIVATE)
        val activeList = mutableListOf<Map<String, Any>>()
        for ((idText, rawRecord) in preferences.all) {
            val downloadId = idText.toLongOrNull() ?: continue
            val record = runCatching { JSONObject(rawRecord as String) }.getOrNull() ?: continue
            val safeName = record.optString("filename")
            val modelsDir = record.optString("modelsDir")
            if (safeName.isBlank() || modelsDir.isBlank()) {
                removeInAppDownload(downloadId)
                continue
            }
            manager.query(DownloadManager.Query().setFilterById(downloadId))?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    removeInAppDownload(downloadId)
                    return@use
                }
                val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                when (status) {
                    DownloadManager.STATUS_SUCCESSFUL ->
                        finalizeInAppDownload(downloadId, safeName, modelsDir, downloaded, total)
                    DownloadManager.STATUS_FAILED -> {
                        removeInAppDownload(downloadId)
                        emitProgress(safeName, downloaded, total, 0.0, "Download failed")
                    }
                    else -> {
                        val statusText = when (status) {
                            DownloadManager.STATUS_PAUSED -> "Paused"
                            DownloadManager.STATUS_PENDING -> "Pending"
                            else -> "Downloading..."
                        }
                        activeList.add(mapOf(
                            "downloadId" to downloadId,
                            "filename" to safeName,
                            "downloaded" to downloaded,
                            "total" to total,
                            "status" to statusText,
                        ))
                        monitorInAppDownload(downloadId, safeName, modelsDir)
                    }
                }
            }
        }
        return activeList
    }

    private fun openModelPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, importRequestCode)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == workspaceTreeRequestCode) {
            val res = pendingWorkspaceResult
            pendingWorkspaceResult = null
            val treeUri = data?.data
            if (resultCode != RESULT_OK || treeUri == null) {
                res?.success(null)
                return
            }
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                )
            } catch (_: Exception) {
                // One-shot grant on some providers; operations still work this session.
            }
            res?.success(treeUri.toString())
            return
        }
        if (requestCode == backupTreeRequestCode) {
            val res = pendingBackupResult
            pendingBackupResult = null
            val treeUri = data?.data
            if (resultCode != RESULT_OK || treeUri == null) {
                res?.success(null)
                return
            }
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                )
            } catch (_: Exception) {
                // Grant may be one-shot on some providers; copying still works this session.
            }
            res?.success(treeUri.toString())
            return
        }

        if (requestCode != importRequestCode) return

        if (resultCode != RESULT_OK || data?.data == null) {
            finishImportSuccess(mapOf("cancelled" to true))
            return
        }

        val uri = data.data!!
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Exception) {
            // Some providers do not allow persistable grants; the one-shot grant is enough here.
        }

        val filename = displayNameFor(uri)
        val lower = filename.lowercase()
        if (!lower.endsWith(".gguf") && !lower.endsWith(".litertlm") && !lower.endsWith(".safetensors")) {
            finishImportError(
                "UNSUPPORTED_MODEL",
                "Only .gguf, .litertlm, and .safetensors files can be imported."
            )
            return
        }

        val size = sizeFor(uri)
        if (size <= 0L) {
            finishImportError("EMPTY_MODEL", "The selected file is empty or unreadable.")
            return
        }

        val modelsDir = pendingModelsDir
        if (modelsDir.isNullOrBlank()) {
            finishImportError("INVALID_DIR", "Models directory is missing.")
            return
        }

        val destination = File(modelsDir, sanitizeFilename(filename))
        if (destination.exists()) {
            AlertDialog.Builder(this)
                .setTitle("Model already imported")
                .setMessage("${destination.name} already exists in app storage. Replace it?")
                .setNegativeButton("Cancel") { _, _ ->
                    finishImportSuccess(mapOf("cancelled" to true))
                }
                .setPositiveButton("Replace") { _, _ ->
                    copyUriToModel(uri, destination, size, true)
                }
                .show()
        } else {
            copyUriToModel(uri, destination, size, false)
        }
    }

    private fun copyUriToModel(uri: Uri, destination: File, totalBytes: Long, replacing: Boolean) {
        emitProgress(destination.name, 0L, totalBytes, 0.0, "Copying to app storage...")
        thread(name = "model-import-${destination.name}") {
            val partFile = File(destination.parentFile, "${destination.name}.part")
            val startedAt = System.currentTimeMillis()
            var copied = 0L
            try {
                destination.parentFile?.mkdirs()
                if (partFile.exists()) partFile.delete()

                contentResolver.openInputStream(uri).use { input ->
                    if (input == null) {
                        throw IllegalStateException("Unable to open selected file.")
                    }
                    partFile.outputStream().use { output ->
                        val buffer = ByteArray(1024 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read <= 0) break
                            output.write(buffer, 0, read)
                            copied += read
                            val elapsedSeconds =
                                (System.currentTimeMillis() - startedAt).coerceAtLeast(1) / 1000.0
                            emitProgress(
                                destination.name,
                                copied,
                                totalBytes,
                                copied / elapsedSeconds,
                                "Copying to app storage..."
                            )
                        }
                    }
                }

                if (replacing && destination.exists()) destination.delete()
                if (!partFile.renameTo(destination)) {
                    throw IllegalStateException("Unable to finalize imported model.")
                }
                emitProgress(destination.name, totalBytes, totalBytes, 0.0, "Import complete")
                finishImportSuccess(
                    mapOf(
                        "cancelled" to false,
                        "filename" to destination.name,
                        "bytes" to totalBytes,
                        "replaced" to replacing
                    )
                )
            } catch (e: Exception) {
                if (partFile.exists()) partFile.delete()
                finishImportError("IMPORT_FAILED", e.message ?: e.toString())
            }
        }
    }

    private fun emitProgress(
        filename: String,
        copiedBytes: Long,
        totalBytes: Long,
        bytesPerSecond: Double,
        status: String,
    ) {
        mainHandler.post {
            importChannel?.invokeMethod(
                "importProgress",
                mapOf(
                    "filename" to filename,
                    "copiedBytes" to copiedBytes,
                    "totalBytes" to totalBytes,
                    "bytesPerSecond" to bytesPerSecond,
                    "status" to status
                )
            )
        }
    }

    private fun finishImportSuccess(payload: Map<String, Any?>) {
        mainHandler.post {
            pendingImportResult?.success(payload)
            pendingImportResult = null
            pendingModelsDir = null
        }
    }

    private fun finishImportError(code: String, message: String) {
        mainHandler.post {
            pendingImportResult?.error(code, message, null)
            pendingImportResult = null
            pendingModelsDir = null
        }
    }

    private fun displayNameFor(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        val value = cursor.getString(index)
                        if (!value.isNullOrBlank()) return value
                    }
                }
            }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "model.gguf"
    }

    private fun sizeFor(uri: Uri): Long {
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (index >= 0) return cursor.getLong(index)
                }
            }
        return -1L
    }

    /// Copies [srcPath] into the SAF directory tree at [treeUri] under [name],
    /// replacing any previous document of the same display name.
    private fun resolveParentInTree(treeUri: Uri, parentDocUri: Uri?): Pair<Uri, String> {
        return if (parentDocUri != null) {
            parentDocUri to DocumentsContract.getDocumentId(parentDocUri)
        } else {
            val rootId = DocumentsContract.getTreeDocumentId(treeUri)
            DocumentsContract.buildDocumentUriUsingTree(treeUri, rootId) to rootId
        }
    }

    private fun listTreeSubFolder(treeUri: Uri, subFolder: String?): List<Map<String, Any>> {
        var rootId = DocumentsContract.getTreeDocumentId(treeUri)
        if (!subFolder.isNullOrBlank()) {
            // Find the child directory id by walking one level.
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, rootId)
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE),
                null, null, null
            )?.use { c ->
                while (c.moveToNext()) {
                    if (c.getString(1) == subFolder &&
                        c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        rootId = c.getString(0)
                        break
                    }
                }
            }
        }
        val out = mutableListOf<Map<String, Any>>()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, rootId)
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_SIZE),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                out.add(mapOf(
                    "documentId" to c.getString(0),
                    "name" to (c.getString(1) ?: ""),
                    "size" to (c.getLong(2))
                ))
            }
        }
        return out
    }

    private fun copyFromTree(treeUri: Uri, relativePath: String?, name: String, destPath: String): Long {
        // Walk the nested Vendor/Family folders from the walk's relative path;
        // the file itself is its path's last segment.
        var rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val folders = relativePath?.split('/')
            ?.dropLast(1)?.filter { it.isNotBlank() } ?: emptyList()
        for (folder in folders) {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, rootId)
            var next: String? = null
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE),
                null, null, null
            )?.use { c ->
                while (c.moveToNext()) {
                    if (c.getString(1) == folder &&
                        c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        next = c.getString(0)
                        break
                    }
                }
            }
            rootId = next ?: throw IllegalStateException("Folder '$folder' not found in the backup.")
        }
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, rootId)
        var docId: String? = null
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == name) {
                    docId = c.getString(0)
                    break
                }
            }
        } ?: throw IllegalStateException("$name not found in the backup.")
        val id = docId ?: throw IllegalStateException("$name not found in the backup.")
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
        val dest = File(destPath); dest.parentFile?.mkdirs()
        val part = File(dest.parentFile, dest.name + ".restore.part")
        var copied = 0L
        contentResolver.openInputStream(docUri)?.use { input ->
            part.outputStream().use { output ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val r = input.read(buffer)
                    if (r <= 0) break
                    output.write(buffer, 0, r)
                    copied += r
                }
            }
        } ?: throw IllegalStateException("Could not open the backup file.")
        if (dest.exists()) dest.delete()
        if (!part.renameTo(dest)) throw IllegalStateException("Could not finalize the restored file.")
        return copied
    }

    private fun copyFileToTree(treeUri: Uri, name: String, srcPath: String, parentDocUri: Uri?): Long {
        val (rootUri, rootId) = resolveParentInTree(treeUri, parentDocUri)

        var existingId: String? = null
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, rootId)
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) {
                    existingId = cursor.getString(0)
                    break
                }
            }
        }
        val sourceLength = File(srcPath).length()
        if (existingId != null) {
            var existingSize = -1L
            contentResolver.query(
                DocumentsContract.buildDocumentUriUsingTree(treeUri, existingId!!),
                arrayOf(DocumentsContract.Document.COLUMN_SIZE),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) existingSize = c.getLong(0)
            }
            // Same name AND same byte size: treat as already backed up.
            // Reading both sides for a real hash would cost as much as the
            // copy itself on multi-GB weights.
            if (existingSize == sourceLength && sourceLength > 0L) {
                return -1L
            }
            DocumentsContract.deleteDocument(
                contentResolver,
                DocumentsContract.buildDocumentUriUsingTree(treeUri, existingId!!)
            )
        }

        val target = DocumentsContract.createDocument(
            contentResolver, rootUri, "application/octet-stream", name
        ) ?: throw IllegalStateException("Could not create the backup file.")

        val source = File(srcPath)
        val totalBytes = source.length()
        var copied = 0L
        var lastEmit = 0L
        contentResolver.openOutputStream(target)?.use { output ->
            source.inputStream().use { input ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    output.write(buffer, 0, read)
                    copied += read
                    // Throttle: one event per 32 MiB keeps the channel quiet
                    // over a multi-gigabyte file while staying smooth enough.
                    if (copied - lastEmit >= 32L * 1024 * 1024 || copied == totalBytes) {
                        lastEmit = copied
                        emitBackupProgress(name, copied, totalBytes)
                    }
                }
            }
        } ?: throw IllegalStateException("Could not open the backup destination.")
        return copied
    }

    /// Walks/creates nested folders under the tree; returns the leaf doc URI.
    private fun ensureTreePath(treeUri: Uri, segments: List<String>): Uri? {
        var parentId = DocumentsContract.getTreeDocumentId(treeUri)
        var parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId)
        for (segment in segments) {
            var childId: String? = null
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE),
                null, null, null
            )?.use { c ->
                while (c.moveToNext()) {
                    if (c.getString(1) == segment &&
                        c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        childId = c.getString(0)
                        break
                    }
                }
            }
            if (childId == null) {
                val created = DocumentsContract.createDocument(
                    contentResolver, parentUri,
                    DocumentsContract.Document.MIME_TYPE_DIR, segment
                ) ?: throw IllegalStateException("Could not create folder '$segment'.")
                childId = DocumentsContract.getDocumentId(created)
                parentUri = created
            } else {
                parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId!!)
            }
            parentId = childId!!
        }
        return parentUri
    }

    /// Depth-first walk collecting model files anywhere in the tree, skipping
    /// [skipFolders] (by display name) so settings never look like models.
    private fun listTreeRecursive(
        treeUri: Uri,
        extensions: Set<String>,
        skipFolders: MutableList<String>,
        maxFiles: Int = 500,
    ): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        data class Node(val docId: String, val relPath: String)

        val queue = ArrayDeque<Node>()
        queue.add(Node(DocumentsContract.getTreeDocumentId(treeUri), ""))
        while (queue.isNotEmpty() && out.size < maxFiles) {
            val node = queue.removeFirst()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, node.docId)
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                        DocumentsContract.Document.COLUMN_SIZE),
                null, null, null
            )?.use { c ->
                while (c.moveToNext() && out.size < maxFiles) {
                    val id = c.getString(0)
                    val name = c.getString(1) ?: continue
                    val mime = c.getString(2) ?: ""
                    val size = c.getLong(3)
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (name !in skipFolders) {
                            queue.add(Node(id, node.relPath + name + "/"))
                        }
                    } else if (extensions.any { name.lowercase().endsWith(it) }) {
                        out.add(mapOf(
                            "name" to name,
                            "size" to size,
                            "documentId" to id,
                            "relativePath" to (node.relPath + name)
                        ))
                    }
                }
            }
        }
        return out
    }

    private fun emitBackupProgress(filename: String, copiedBytes: Long, totalBytes: Long) {
        mainHandler.post {
            importChannel?.invokeMethod(
                "backupProgress",
                mapOf(
                    "filename" to filename,
                    "copiedBytes" to copiedBytes,
                    "totalBytes" to totalBytes
                )
            )
        }
    }

    private fun sanitizeFilename(filename: String): String {
        return filename.replace(Regex("""[\\/:*?"<>|]"""), "_")
    }

    // ── Workspace: generic SAF CRUD against a persisted tree ───────────────

    private fun findChildId(treeUri: Uri, parentId: String, name: String): String? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == name) return c.getString(0)
            }
        }
        return null
    }

    private fun resolveExistingDirId(treeUri: Uri, segments: List<String>): String {
        var parentId = DocumentsContract.getTreeDocumentId(treeUri)
        for (segment in segments) {
            parentId = findChildId(treeUri, parentId, segment)
                ?: throw IllegalStateException("Folder not found: $segment")
        }
        return parentId
    }

    /// Resolves a workspace-relative path to a document id. When [isDir] the
    /// whole path is folder chain; otherwise the last segment is the item
    /// (file or folder) inside its parent chain. With [create] missing folders
    /// are created on demand, otherwise a missing folder raises.
    private fun resolveWorkspacePath(treeUri: Uri, relPath: String, create: Boolean, isDir: Boolean): String {
        val segments = relPath.split('/').filter { it.isNotBlank() }
        if (isDir) {
            if (segments.isEmpty()) return DocumentsContract.getTreeDocumentId(treeUri)
            val uri = if (create) ensureTreePath(treeUri, segments)
                else DocumentsContract.buildDocumentUriUsingTree(treeUri, resolveExistingDirId(treeUri, segments))
            return DocumentsContract.getDocumentId(uri!!)
        }
        val parentSegs = segments.dropLast(1)
        val parentId = if (parentSegs.isEmpty())
            DocumentsContract.getTreeDocumentId(treeUri)
        else if (create)
            DocumentsContract.getDocumentId(ensureTreePath(treeUri, parentSegs)!!)
        else
            resolveExistingDirId(treeUri, parentSegs)
        return findChildId(treeUri, parentId, segments.last())
            ?: throw IllegalStateException("Item not found: ${segments.last()}")
    }

    private fun listWorkspaceDir(treeUri: Uri, relPath: String): List<Map<String, Any>> {
        val parentId = resolveWorkspacePath(treeUri, relPath, create = false, isDir = true)
        val out = mutableListOf<Map<String, Any>>()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE),
            null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                out.add(mapOf(
                    "documentId" to c.getString(0),
                    "name" to (c.getString(1) ?: ""),
                    "isDir" to (c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR),
                    "size" to c.getLong(3)
                ))
            }
        }
        return out
    }

    private fun readWorkspaceFile(treeUri: Uri, relPath: String): String {
        val segments = relPath.split('/').filter { it.isNotBlank() }
        val parentSegs = segments.dropLast(1)
        val parentId = if (parentSegs.isEmpty())
            DocumentsContract.getTreeDocumentId(treeUri)
        else
            resolveExistingDirId(treeUri, parentSegs)
        val childId = findChildId(treeUri, parentId, segments.last())
            ?: throw IllegalStateException("File not found: ${segments.last()}")
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
        contentResolver.openInputStream(docUri)?.use { input ->
            return input.readBytes().toString(Charsets.UTF_8)
        } ?: throw IllegalStateException("Could not open file '${segments.last()}'")
    }

    private fun writeWorkspaceFile(treeUri: Uri, relPath: String, content: String) {
        val segments = relPath.split('/').filter { it.isNotBlank() }
        val name = segments.last()
        val parentSegs = segments.dropLast(1)
        val parentId = if (parentSegs.isEmpty())
            DocumentsContract.getTreeDocumentId(treeUri)
        else
            DocumentsContract.getDocumentId(ensureTreePath(treeUri, parentSegs)!!)
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId)
        var childId = findChildId(treeUri, parentId, name)
        val docUri: Uri
        if (childId == null) {
            docUri = DocumentsContract.createDocument(
                contentResolver, parentUri, "application/octet-stream", name
            ) ?: throw IllegalStateException("Could not create file '$name'")
        } else {
            docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
        }
        contentResolver.openOutputStream(docUri, "wt")?.use { output ->
            output.write(content.toByteArray(Charsets.UTF_8))
        } ?: throw IllegalStateException("Could not open file '$name' for writing")
    }

    private fun deleteWorkspaceItem(treeUri: Uri, relPath: String): Boolean {
        val segments = relPath.split('/').filter { it.isNotBlank() }
        val parentSegs = segments.dropLast(1)
        val parentId = if (parentSegs.isEmpty())
            DocumentsContract.getTreeDocumentId(treeUri)
        else
            resolveExistingDirId(treeUri, parentSegs)
        val childId = findChildId(treeUri, parentId, segments.last())
            ?: throw IllegalStateException("Item not found: ${segments.last()}")
        return DocumentsContract.deleteDocument(
            contentResolver,
            DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
        )
    }

    /// Copies every file/dir under the old tree into the new one. Used when the
    /// user relocates the workspace root; the new root becomes the only grant,
    /// and workspace-relative project paths stay valid afterwards.
    private fun moveWorkspace(oldTree: Uri, newTree: Uri): Int {
        var copied = 0
        fun walk(srcId: String, destId: String) {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(oldTree, srcId)
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE),
                null, null, null
            )?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getString(0)
                    val name = c.getString(1) ?: continue
                    val mime = c.getString(2) ?: ""
                    val destParentUri = DocumentsContract.buildDocumentUriUsingTree(newTree, destId)
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        val created = DocumentsContract.createDocument(
                            contentResolver, destParentUri,
                            DocumentsContract.Document.MIME_TYPE_DIR, name
                        ) ?: continue
                        walk(id, DocumentsContract.getDocumentId(created))
                    } else {
                        val target = DocumentsContract.createDocument(
                            contentResolver, destParentUri, "application/octet-stream", name
                        ) ?: continue
                        contentResolver.openInputStream(
                            DocumentsContract.buildDocumentUriUsingTree(oldTree, id)
                        )?.use { input ->
                            contentResolver.openOutputStream(target)?.use { output ->
                                input.copyTo(output)
                            }
                        }
                        copied++
                    }
                }
            }
        }
        walk(
            DocumentsContract.getTreeDocumentId(oldTree),
            DocumentsContract.getTreeDocumentId(newTree)
        )
        return copied
    }
}
