package app.kavasam.kavasam_mobile

import android.app.NotificationManager
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var pendingEvidence: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingEvidence = extractEvidence(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingEvidence" -> {
                    result.success(pendingEvidence)
                    pendingEvidence = null
                }
                "getProtectionStatus" -> result.success(protectionStatus())
                "openNotificationAccess" -> {
                    openNotificationAccess()
                    result.success(true)
                }
                "requestCallScreeningRole" -> result.success(requestCallScreeningRole())
                "takeNotificationEvidence" -> result.success(takeNotificationEvidence())
                "takeCallEvidence" -> result.success(takeCallEvidence())
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val evidence = extractEvidence(intent) ?: return
        pendingEvidence = evidence
        if (::channel.isInitialized) channel.invokeMethod("evidenceReceived", evidence)
    }

    private fun protectionStatus(): Map<String, Any> = mapOf(
        "notificationShield" to isNotificationAccessEnabled(),
        "callScreening" to isCallScreeningEnabled(),
        "androidVersion" to Build.VERSION.SDK_INT,
    )

    private fun isNotificationAccessEnabled(): Boolean {
        val component = ComponentName(this, KavasamNotificationListenerService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            return getSystemService(NotificationManager::class.java)
                .isNotificationListenerAccessGranted(component)
        }
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        return enabled.contains(component.flattenToString())
    }

    private fun openNotificationAccess() {
        val component = ComponentName(this, KavasamNotificationListenerService::class.java)
        val detailIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).apply {
                putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
            }
        } else {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        }
        runCatching { startActivity(detailIntent) }.onFailure {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }

    private fun isCallScreeningEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val manager = getSystemService(RoleManager::class.java)
        return manager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) &&
            manager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
    }

    private fun requestCallScreeningRole(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val manager = getSystemService(RoleManager::class.java)
        if (!manager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)) return false
        if (!manager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
            startActivity(manager.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING))
        }
        return true
    }

    private fun takeNotificationEvidence(): Map<String, Any?>? {
        val preferences = ProtectionStore.preferences(this)
        val timestamp = preferences.getLong(ProtectionStore.NOTIFICATION_TIMESTAMP, 0L)
        if (timestamp == 0L) return null
        val evidence = mapOf(
            "type" to "notification",
            "title" to preferences.getString(ProtectionStore.NOTIFICATION_TITLE, "Incoming message"),
            "text" to preferences.getString(ProtectionStore.NOTIFICATION_TEXT, ""),
            "source" to preferences.getString(ProtectionStore.NOTIFICATION_PACKAGE, "Android notification"),
            "localScore" to preferences.getInt(ProtectionStore.NOTIFICATION_SCORE, 0),
            "localReasons" to preferences.getString(ProtectionStore.NOTIFICATION_REASONS, ""),
            "receivedAt" to timestamp,
        )
        preferences.edit().remove(ProtectionStore.NOTIFICATION_TIMESTAMP).apply()
        return evidence
    }

    private fun takeCallEvidence(): Map<String, Any?>? {
        val preferences = ProtectionStore.preferences(this)
        val timestamp = preferences.getLong(ProtectionStore.CALL_TIMESTAMP, 0L)
        if (timestamp == 0L) return null
        val evidence = mapOf(
            "type" to "call",
            "text" to preferences.getString(ProtectionStore.CALL_NUMBER, "Unknown number"),
            "source" to "Android CallScreeningService",
            "verification" to preferences.getString(ProtectionStore.CALL_VERIFICATION, "not_available"),
            "direction" to preferences.getString(ProtectionStore.CALL_DIRECTION, "incoming"),
            "receivedAt" to timestamp,
        )
        preferences.edit().remove(ProtectionStore.CALL_TIMESTAMP).apply()
        return evidence
    }

    private fun extractEvidence(intent: Intent?): Map<String, Any?>? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val mimeType = intent.type.orEmpty()
        val sharedText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val source = referrer?.host ?: intent.`package` ?: "Shared from Android"
        if (mimeType.startsWith("image/")) {
            val path = sharedStream(intent)?.let { copyToCache(it, mimeType) }
            if (path != null) {
                return mapOf(
                    "type" to "image",
                    "path" to path,
                    "text" to sharedText,
                    "mimeType" to mimeType,
                    "source" to source,
                    "receivedAt" to System.currentTimeMillis(),
                )
            }
        }
        if (sharedText.isNotBlank()) {
            return mapOf(
                "type" to "text",
                "text" to sharedText,
                "mimeType" to mimeType.ifBlank { "text/plain" },
                "source" to source,
                "receivedAt" to System.currentTimeMillis(),
            )
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun sharedStream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun copyToCache(uri: Uri, mimeType: String): String? = runCatching {
        val extension = when (mimeType.lowercase()) {
            "image/png" -> "png"
            "image/webp" -> "webp"
            else -> "jpg"
        }
        val destination = File(cacheDir, "shared_evidence_${System.currentTimeMillis()}.$extension")
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Unable to read shared evidence" }
            destination.outputStream().use { output -> input.copyTo(output) }
        }
        destination.absolutePath
    }.getOrNull()

    companion object {
        private const val CHANNEL_NAME = "app.kavasam/native_guard"
    }
}
