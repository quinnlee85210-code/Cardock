package com.localaccount.account_subscription_manager

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

internal enum class PersistablePermissionMode {
    READ,
    WRITE,
    READ_WRITE,
    NONE,
}

internal fun persistablePermissionMode(
    readGranted: Boolean,
    writeGranted: Boolean,
): PersistablePermissionMode = when {
    readGranted && writeGranted -> PersistablePermissionMode.READ_WRITE
    readGranted -> PersistablePermissionMode.READ
    writeGranted -> PersistablePermissionMode.WRITE
    else -> PersistablePermissionMode.NONE
}

/** SAF only. No network, directory scan, broad storage permission or filename deletion. */
class DocumentStorageBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object { const val REQUEST_TREE = 7341; const val REQUEST_EXPORT = 7342; const val REQUEST_IMPORT = 7343; const val REQUEST_BACKUP = 7344 }
    private val resolver get() = activity.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var picker: MethodChannel.Result? = null
    private val exports = mutableMapOf<String, Pair<Uri, OutputStream>>()
    // Only the protected Dart config supplies registered URIs for rotation. A
    // new backup may only be written through a handle created this process.
    private val created = mutableSetOf<String>()
    init { MethodChannel(messenger, "cardock/document_storage_v1").setMethodCallHandler(::handle) }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pickDirectory" || call.method == "beginExport" || call.method == "pickImport" || call.method == "pickBackup") {
            if (picker != null) { result.error("provider_refused", "", null); return }
            picker = result
            try {
                val tree = call.method == "pickDirectory"
                val importing = call.method == "pickImport" || call.method == "pickBackup"
                val intent = Intent(if (tree) Intent.ACTION_OPEN_DOCUMENT_TREE else if (importing) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT)
                if (!tree) {
                    intent.addCategory(Intent.CATEGORY_OPENABLE)
                    intent.type = if (importing) "*/*" else call.argument<String>("mime") ?: "application/octet-stream"
                    intent.putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                }
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or if (importing) 0 else Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (tree) intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                activity.startActivityForResult(intent, if (tree) REQUEST_TREE else if (call.method == "pickBackup") REQUEST_BACKUP else if (importing) REQUEST_IMPORT else REQUEST_EXPORT)
            } catch (_: Exception) { picker = null; result.error("provider_refused", "", null) }
            return
        }
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "hasPermission" -> permission(Uri.parse(call.argument<String>("tree")))
                    "createBackup" -> {
                        val tree = Uri.parse(call.argument<String>("tree")); requirePermission(tree)
                        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                        val uri = DocumentsContract.createDocument(resolver, parent, "application/octet-stream",
                            call.argument<String>("name") ?: throw IOException()) ?: throw FileNotFoundException()
                        created.add(uri.toString()); uri.toString()
                    }
                    "write" -> {
                        val uri = call.argument<String>("uri")!!
                        check(created.contains(uri))
                        val bytes = call.argument<ByteArray>("bytes")!!
                        require(bytes.size <= 16 * 1024 * 1024)
                        (resolver.openOutputStream(Uri.parse(uri), "wt") ?: throw IOException()).use { it.write(bytes); it.flush() }
                        null
                    }
                    "read" -> {
                        val uri = Uri.parse(call.argument<String>("uri"))
                        (resolver.openInputStream(uri) ?: throw FileNotFoundException()).use { input ->
                            val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(64 * 1024)
                            while (true) { val count = input.read(buffer); if (count < 0) break
                                if (output.size() + count > 16 * 1024 * 1024) throw IOException()
                                output.write(buffer, 0, count) }
                            output.toByteArray()
                        }
                    }
                    "deleteOwned" -> {
                        val tree = Uri.parse(call.argument<String>("tree")); requirePermission(tree)
                        val uri = Uri.parse(call.argument<String>("uri"))
                        require(uri.authority == tree.authority && DocumentsContract.isTreeUri(uri) &&
                            DocumentsContract.getTreeDocumentId(uri) == DocumentsContract.getTreeDocumentId(tree))
                        if (!DocumentsContract.deleteDocument(resolver, uri)) throw IOException()
                        created.remove(uri.toString()); null
                    }
                    "appendExport" -> {
                        val entry = exports[call.argument<String>("handle")] ?: throw IOException()
                        val bytes = call.argument<ByteArray>("bytes")!!; require(bytes.size <= 1024 * 1024)
                        entry.second.write(bytes); null
                    }
                    "finishExport" -> {
                        val handle = call.argument<String>("handle")
                        val entry = exports[handle] ?: throw IOException()
                        entry.second.use { it.flush() }
                        exports.remove(handle); null
                    }
                    "abortExport" -> {
                        val entry = exports.remove(call.argument<String>("handle"))
                        if (entry != null) { try { entry.second.close() } finally { DocumentsContract.deleteDocument(resolver, entry.first) } }
                        null
                    }
                    else -> { main.post { result.notImplemented() }; return@execute }
                }
                main.post { result.success(value) }
            } catch (error: Exception) { main.post { result.error(errorCode(error, call.method), "", null) } }
        }
    }
    private fun permission(tree: Uri) = resolver.persistedUriPermissions.any {
        it.uri == tree && it.isReadPermission && it.isWritePermission
    }
    private fun requirePermission(tree: Uri) { if (!permission(tree)) throw SecurityException() }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST_TREE && request != REQUEST_EXPORT && request != REQUEST_IMPORT && request != REQUEST_BACKUP) return false
        val result = picker ?: return true; picker = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        worker.execute {
            try {
                if (request == REQUEST_IMPORT || request == REQUEST_BACKUP) {
                    var name = if (request == REQUEST_BACKUP) "selected-backup.asmbackup" else "selected-document.csv"
                    var declaredSize: Long? = null
                    // A provider may omit metadata or throw for unsupported columns.
                    try {
                        resolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME,
                            android.provider.OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                                val sizeIndex = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex).take(200)
                                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) declaredSize = cursor.getLong(sizeIndex)
                            }
                        }
                    } catch (_: Exception) { /* Stream limit still applies. */ }
                    val limit = if (request == REQUEST_BACKUP) BoundedDocumentReader.BACKUP_LIMIT else BoundedDocumentReader.IMPORT_LIMIT
                    val bytes = BoundedDocumentReader.read(limit, declaredSize) {
                        resolver.openInputStream(uri) ?: throw FileNotFoundException()
                    }
                    main.post { try { result.success(mapOf("name" to name, "bytes" to bytes)) } finally { bytes.fill(0) } }
                    return@execute
                }
                val value = if (request == REQUEST_TREE) {
                    when (
                        persistablePermissionMode(
                            readGranted = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0,
                            writeGranted = data.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0,
                        )
                    ) {
                        PersistablePermissionMode.READ -> resolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                        PersistablePermissionMode.WRITE -> resolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                        )
                        PersistablePermissionMode.READ_WRITE -> resolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                        )
                        PersistablePermissionMode.NONE -> throw IllegalArgumentException()
                    }
                    requirePermission(uri)
                    uri.toString()
                } else {
                    beginTrackedExport(uri)
                }
                main.post { result.success(value) }
            } catch (error: Exception) { main.post { result.error(errorCode(error, "write"), "", null) } }
        }
        return true
    }
    @SuppressLint("Recycle")
    private fun beginTrackedExport(uri: Uri): String {
        val handle = UUID.randomUUID().toString()
        try {
            // Ownership moves to exports for a chunked MethodChannel session.
            // finishExport, abortExport, and close are the matching close paths.
            exports[handle] = uri to (
                resolver.openOutputStream(uri, "wt") ?: throw IOException()
            )
        } catch (error: Exception) {
            try { DocumentsContract.deleteDocument(resolver, uri) } catch (_: Exception) {}
            throw error
        }
        return handle
    }
    private fun errorCode(error: Exception, method: String) = when {
        error is SecurityException -> "permission_revoked"
        error is FileNotFoundException -> "directory_missing"
        error is IOException && (error.cause as? android.system.ErrnoException)?.errno == android.system.OsConstants.ENOSPC -> "storage_full"
        method == "read" -> "read_failed"
        error is IllegalArgumentException || error is IllegalStateException -> "provider_refused"
        else -> "interrupted"
    }
    fun close() {
        picker?.error("interrupted", "", null); picker = null
        worker.execute {
            exports.values.forEach {
                try { it.second.close() } catch (_: Exception) {}
                try { DocumentsContract.deleteDocument(resolver, it.first) } catch (_: Exception) {}
            }
            exports.clear()
        }
        worker.shutdown()
    }
}
