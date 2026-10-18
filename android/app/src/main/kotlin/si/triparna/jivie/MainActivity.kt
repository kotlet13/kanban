package si.triparna.jivie

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import android.content.ClipData
import androidx.core.content.FileProvider

class MainActivity : FlutterActivity() {
    private var privateFileResult: MethodChannel.Result? = null
    private var privateFileBytes: ByteArray? = null
    private var privateFileExtensions = emptyList<String>()
    private var privateFileLimit = 0
    private var privateFileGeneration = 0L
    private var privateFileReading = false
    private val privatePickRequest = 0x4A71
    private val privateSaveRequest = 0x4A72
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vsakdan/remote_push_readiness")
            .setMethodCallHandler { call, result ->
                if (call.method == "applicationId") result.success(applicationContext.packageName)
                else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jivie/private_file_io")
            .setMethodCallHandler { call, result ->
                if (call.method == "legacyPickerRoots") {
                    result.success(mapOf("androidPicker" to File(cacheDir, "file_picker").absolutePath))
                    return@setMethodCallHandler
                }
                if (call.method == "cleanup") {
                    try { cleanRecoveryShares(); result.success(true) }
                    catch (_: Exception) { result.error("file_cleanup", "Private staging cleanup is incomplete", null) }
                    return@setMethodCallHandler
                }
                if (privateFileResult != null) { result.error("file_busy", "Another file operation is active", null); return@setMethodCallHandler }
                try {
                    privateFileGeneration++
                    privateFileReading = false
                    when (call.method) {
                        "shareRecovery" -> {
                            val name = call.argument<String>("name") ?: error("name")
                            val bytes = call.argument<ByteArray>("bytes") ?: error("bytes")
                            require(Regex("^jivie-(installation|account)-[a-f0-9]{32}\\.jivie-recovery$").matches(name))
                            require(bytes.isNotEmpty() && bytes.size <= 65536)
                            val root = cleanRecoveryShares()
                            require((root.listFiles()?.size ?: 0) < 16)
                            val directory = File(root, UUID.randomUUID().toString())
                            require(directory.mkdir() && directory.canonicalFile == directory.absoluteFile)
                            require(directory.setReadable(false, false) && directory.setReadable(true, true))
                            require(directory.setWritable(false, false) && directory.setWritable(true, true))
                            require(directory.setExecutable(false, false) && directory.setExecutable(true, true))
                            val file = File(directory, name)
                            try {
                                FileOutputStream(file).use { output -> output.write(bytes); output.fd.sync() }
                                require(file.setReadable(false, false) && file.setReadable(true, true))
                                require(file.setWritable(false, false) && file.setWritable(true, true))
                                val uri = FileProvider.getUriForFile(this, "$packageName.recovery_files", file)
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = "application/octet-stream"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    clipData = ClipData.newRawUri("Recovery file", uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(Intent.createChooser(send, call.argument<String>("title")))
                                // Selection/delivery is not evidence of a preserved external copy.
                                // Keep the bounded private file for receiver reads; a later startup
                                // removes only owned entries older than 24 hours.
                                result.success("shareStarted")
                            } finally { bytes.fill(0) }
                        }
                        "pick" -> {
                            val extensions = call.argument<List<String>>("extensions") ?: error("extensions")
                            val limit = call.argument<Int>("maxBytes") ?: error("limit")
                            require(limit in 1..201326592 && extensions.isNotEmpty() && extensions.size <= 32)
                            require(extensions.all { Regex("^[a-z0-9-]{1,20}$").matches(it) })
                            privateFileExtensions = extensions
                            privateFileLimit = limit
                            privateFileResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                val mimes = extensions.mapNotNull { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it) }.distinct()
                                if (mimes.isNotEmpty() && mimes.size == extensions.size) putExtra(Intent.EXTRA_MIME_TYPES, mimes.toTypedArray())
                            }
                            startActivityForResult(intent, privatePickRequest)
                        }
                        "save" -> {
                            val name = call.argument<String>("name") ?: error("name")
                            val bytes = call.argument<ByteArray>("bytes") ?: error("bytes")
                            require(safeFileName(name) && bytes.size <= 201326592)
                            privateFileBytes = bytes
                            privateFileResult = result
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"
                                putExtra(Intent.EXTRA_TITLE, name)
                            }
                            startActivityForResult(intent, privateSaveRequest)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    privateFileResult = null
                    privateFileBytes = null
                    result.error("file_request", "The file operation could not start", null)
                }
            }
    }

    private fun cleanRecoveryShares(): File {
        val root = File(cacheDir.canonicalFile, "jivie-recovery-shares-v1")
        require(root.canonicalFile == root.absoluteFile)
        if (!root.exists()) require(root.mkdir())
        require(root.setReadable(false, false) && root.setReadable(true, true))
        require(root.setWritable(false, false) && root.setWritable(true, true))
        require(root.setExecutable(false, false) && root.setExecutable(true, true))
        val expiry = System.currentTimeMillis() - 86400000L
        for (directory in root.listFiles() ?: emptyArray()) {
            require(directory.canonicalFile == directory.absoluteFile)
            require(directory.isDirectory && UUID.fromString(directory.name).toString() == directory.name)
            val children = directory.listFiles() ?: emptyArray()
            require(children.size <= 1 && children.all { file ->
                file.canonicalFile == file.absoluteFile && file.isFile &&
                    Regex("^jivie-(installation|account)-[a-f0-9]{32}\\.jivie-recovery$").matches(file.name)
            })
            if (directory.lastModified() < expiry) {
                for (file in children) require(file.delete())
                require(directory.delete())
            }
        }
        return root
    }

    private fun safeFileName(name: String): Boolean = name.isNotEmpty() && name.length <= 255 &&
        name != "." && name != ".." && name.none { it.code < 32 || it.code == 127 || it == '/' || it == '\\' }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != privatePickRequest && requestCode != privateSaveRequest) return
        val result = privateFileResult ?: return
        if (privateFileReading) return
        val generation = privateFileGeneration
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            privateFileResult = null
            privateFileBytes = null
            result.success(if (requestCode == privateSaveRequest) "cancelled" else null)
            return
        }
        val export = privateFileBytes
        val limit = privateFileLimit
        val extensions = privateFileExtensions
        privateFileReading = true
        Thread {
            try {
                val response: Any = if (requestCode == privateSaveRequest) {
                    contentResolver.openOutputStream(uri, "wt")?.use { output ->
                        output.write(export ?: error("missing export"))
                        output.flush()
                    } ?: error("output unavailable")
                    "saved"
                } else {
                    val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (!cursor.moveToFirst()) error("missing metadata")
                        cursor.getString(0)
                    } ?: error("missing metadata")
                    require(safeFileName(name) && extensions.contains(name.substringAfterLast('.', "").lowercase()))
                    val output = ByteArrayOutputStream()
                    contentResolver.openInputStream(uri)?.use { input ->
                        val chunk = ByteArray(65536)
                        while (true) {
                            val read = input.read(chunk)
                            if (read < 0) break
                            require(read > 0)
                            require(output.size().toLong() + read <= limit.toLong())
                            output.write(chunk, 0, read)
                        }
                    } ?: error("input unavailable")
                    mapOf("name" to name, "bytes" to output.toByteArray())
                }
                runOnUiThread {
                    if (generation != privateFileGeneration || privateFileResult !== result) return@runOnUiThread
                    privateFileReading = false
                    privateFileResult = null; privateFileBytes = null
                    result.success(response)
                }
            } catch (_: Exception) {
                runOnUiThread {
                    if (generation != privateFileGeneration || privateFileResult !== result) return@runOnUiThread
                    privateFileReading = false
                    privateFileResult = null; privateFileBytes = null
                    result.error("file_io", "The selected file could not be processed", null)
                }
            }
        }.start()
    }
}
