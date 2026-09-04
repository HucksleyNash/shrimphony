package com.thomaskleckner.shrimphony

import android.Manifest
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.media.MediaRouter2
import android.media.session.MediaSessionManager
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.thomaskleckner.shrimphony/audio_output",
        ).setMethodCallHandler { call, result ->
            if (call.method != "show") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                result.success(MediaRouter2.getInstance(this).showSystemOutputSwitcher())
            } else {
                startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                result.success(true)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.thomaskleckner.shrimphony/android_auto",
        ).setMethodCallHandler { call, result ->
            if (call.method != "configureArtwork") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val serverUrl = call.argument<String>("serverUrl")
            getSharedPreferences("android_auto", MODE_PRIVATE).edit().apply {
                if (serverUrl == null) remove("server_url") else putString("server_url", serverUrl)
            }.apply()
            result.success(null)
        }
    }
}

class ArtworkProvider : ContentProvider() {
    companion object {
        private val itemIdPattern = Regex("[A-Za-z0-9-]+")
        private val lock = Any()
        private const val maxArtworkBytes = 10 * 1024 * 1024
    }

    override fun onCreate() = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r" || !isTrustedCaller()) {
            throw FileNotFoundException("Artwork is unavailable")
        }
        val itemId = uri.lastPathSegment?.takeIf(itemIdPattern::matches)
            ?: throw FileNotFoundException("Invalid artwork ID")
        val context = context ?: throw FileNotFoundException("No app context")
        val serverUrl = context.getSharedPreferences("android_auto", 0)
            .getString("server_url", null)
            ?: throw FileNotFoundException("No Jellyfin server")
        val server = Uri.parse(serverUrl)
        if (server.scheme !in setOf("http", "https") || server.host.isNullOrEmpty() ||
            !server.userInfo.isNullOrEmpty() || server.query != null || server.fragment != null) {
            throw FileNotFoundException("Invalid Jellyfin server")
        }
        val remote = server.buildUpon()
            .appendPath("Items")
            .appendPath(itemId)
            .appendPath("Images")
            .appendPath("Primary")
            .appendQueryParameter("maxWidth", "600")
            .appendQueryParameter("quality", "88")
            .build()
        val directory = File(context.cacheDir, "android-auto-artwork").apply { mkdirs() }
        val key = UUID.nameUUIDFromBytes("$serverUrl|$itemId".toByteArray()).toString()
        val artwork = File(directory, key)

        // ponytail: one download lock; split by artwork ID if car-grid throughput becomes measurable.
        synchronized(lock) {
            if (!artwork.exists() || artwork.length() == 0L) download(URL(remote.toString()), artwork)
        }
        return ParcelFileDescriptor.open(artwork, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun isTrustedCaller(): Boolean {
        val context = context ?: return false
        val uid = Binder.getCallingUid()
        if (uid == Process.myUid()) return true
        return context.packageManager.getPackagesForUid(uid).orEmpty().any { packageName ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                context.getSystemService(MediaSessionManager::class.java).isTrustedForMediaControl(
                    MediaSessionManager.RemoteUserInfo(packageName, -1, uid),
                )
            } else {
                context.checkPermission(Manifest.permission.MEDIA_CONTENT_CONTROL, -1, uid) ==
                    PackageManager.PERMISSION_GRANTED
            }
        }
    }

    private fun download(remote: URL, artwork: File) {
        val temporary = File(artwork.parentFile, "${artwork.name}.tmp")
        val connection = remote.openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 10_000
            connection.readTimeout = 20_000
            connection.setRequestProperty("Accept", "image/*")
            if (connection.responseCode !in 200..299 ||
                !connection.contentType.orEmpty().startsWith("image/")) {
                throw FileNotFoundException("Artwork download failed")
            }
            connection.inputStream.use { input ->
                temporary.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > maxArtworkBytes) throw FileNotFoundException("Artwork is too large")
                        output.write(buffer, 0, count)
                    }
                }
            }
            if (!temporary.renameTo(artwork)) throw FileNotFoundException("Could not cache artwork")
        } finally {
            connection.disconnect()
            temporary.delete()
        }
    }

    override fun getType(uri: Uri) = "image/*"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
