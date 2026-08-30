package app.kavasam.kavasam_mobile

import android.Manifest
import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.telecom.TelecomManager
import android.telephony.PhoneNumberUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var pendingRoleResult: MethodChannel.Result? = null
    private var pendingScreeningRoleResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingContactsPermissionResult: MethodChannel.Result? = null
    private var pendingDataPermissionResult: MethodChannel.Result? = null
    private var pendingMicPermissionResult: MethodChannel.Result? = null
    private var pendingDialNumber: String? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_DIALER_ROLE -> {
                pendingRoleResult?.success(
                    roleResult(
                        supported = isDialerRoleSupported(),
                        granted = isDefaultDialer(),
                        grantedMessage = "Kavasam is now the default phone app.",
                        deniedMessage = "The phone role was not granted. Choose Kavasam in Android Default apps.",
                    ),
                )
                pendingRoleResult = null
            }
            REQUEST_SCREENING_ROLE -> {
                pendingScreeningRoleResult?.success(
                    roleResult(
                        supported = isCallScreeningSupported(),
                        granted = isCallScreeningApp(),
                        grantedMessage = "Caller ID and spam protection are enabled.",
                        deniedMessage = "Caller ID permission was not granted by Android.",
                    ),
                )
                pendingScreeningRoleResult = null
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_PHONE_PERMISSIONS -> {
                pendingPermissionResult?.success(hasPhonePermission())
                pendingPermissionResult = null
            }
            REQUEST_CONTACTS_PERMISSION -> {
                pendingContactsPermissionResult?.success(hasContactsPermission())
                pendingContactsPermissionResult = null
            }
            REQUEST_DATA_PERMISSIONS -> {
                pendingDataPermissionResult?.success(dialerStatus())
                pendingDataPermissionResult = null
            }
            REQUEST_MIC_PERMISSION -> {
                pendingMicPermissionResult?.success(hasMicPermission())
                pendingMicPermissionResult = null
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingDialNumber = dialNumberFrom(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALL_EVENTS_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    PhoneCallController.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    PhoneCallController.setEventSink(null)
                }
            },
        )
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LINK_EVENTS_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    LinkCallEngine.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    LinkCallEngine.setEventSink(null)
                }
            },
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDialerStatus" -> result.success(dialerStatus())
                "requestDefaultDialer" -> requestDefaultDialer(result)
                "requestCallScreening" -> requestCallScreening(result)
                "openDefaultAppsSettings" -> result.success(openDefaultAppsSettings())
                "requestPhonePermission" -> requestPhonePermission(result)
                "requestContactsPermission" -> requestContactsPermission(result)
                "requestPhoneDataPermissions" -> requestPhoneDataPermissions(result)
                "takePendingDialNumber" -> {
                    result.success(pendingDialNumber)
                    pendingDialNumber = null
                }
                "placeCall" -> result.success(
                    placeCall(call.argument<String>("number").orEmpty()),
                )
                "getCurrentCall" -> result.success(PhoneCallController.snapshot())
                "getHistory" -> result.success(DevicePhoneData.callHistory(this))
                "getContacts" -> result.success(DevicePhoneData.contacts(this))
                "getCallerIdentity" -> result.success(
                    CallerIdentityStore.assess(
                        this,
                        call.argument<String>("number").orEmpty(),
                        "lookup",
                    ).toMap(),
                )
                "getSpamAnalytics" -> result.success(
                    CallerIdentityStore.analytics(this) + CallSafetyTracker.analytics(this),
                )
                "getSafetySignals" -> result.success(CallSafetyTracker.availableSignals())
                "getHighRiskAnalyses" -> result.success(CallSafetyTracker.highRiskAnalyses(this))
                "saveHighRiskAnalysis" -> result.success(
                    CallSafetyTracker.saveHighRiskAnalysis(
                        this,
                        call.arguments<Map<String, Any?>>() ?: emptyMap(),
                    ),
                )
                "getProtectionSettings" -> result.success(CallProtectionSettings.snapshot(this))
                "setProtectionSetting" -> result.success(
                    CallProtectionSettings.set(
                        this,
                        call.argument<String>("key").orEmpty(),
                        call.argument<Boolean>("value") == true,
                    ),
                )
                "getCloudConsent" -> result.success(
                    getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE)
                        .getBoolean(CLOUD_CONSENT_KEY, false),
                )
                "setCloudConsent" -> {
                    val enabled = call.argument<Boolean>("value") == true
                    getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE)
                        .edit()
                        .putBoolean(CLOUD_CONSENT_KEY, enabled)
                        .apply()
                    result.success(enabled)
                }
                "getCommunityConsent" -> result.success(
                    getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE)
                        .getBoolean(COMMUNITY_CONSENT_KEY, false),
                )
                "setCommunityConsent" -> {
                    val enabled = call.argument<Boolean>("value") == true
                    getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE)
                        .edit()
                        .putBoolean(COMMUNITY_CONSENT_KEY, enabled)
                        .apply()
                    result.success(enabled)
                }
                "getGuardianConfig" -> result.success(guardianConfig())
                "saveGuardianConfig" -> {
                    val preferences = getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE)
                    preferences.edit()
                        .putString(GUARDIAN_PRIMARY_ALIAS_KEY, call.argument<String>("primaryAlias").orEmpty())
                        .putString(GUARDIAN_PHONE_KEY, call.argument<String>("guardianPhone").orEmpty())
                        .putString(GUARDIAN_ID_KEY, call.argument<String>("guardianId").orEmpty())
                        .putString(GUARDIAN_STATUS_KEY, call.argument<String>("status").orEmpty())
                        .apply()
                    result.success(guardianConfig())
                }
                "clearGuardianConfig" -> {
                    getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE).edit()
                        .remove(GUARDIAN_PRIMARY_ALIAS_KEY)
                        .remove(GUARDIAN_PHONE_KEY)
                        .remove(GUARDIAN_ID_KEY)
                        .remove(GUARDIAN_STATUS_KEY)
                        .apply()
                    result.success(guardianConfig())
                }
                "getGuardianViewerConfig" -> result.success(guardianViewerConfig())
                "saveGuardianViewerConfig" -> {
                    getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE).edit()
                        .putString(GUARDIAN_VIEWER_ID_KEY, call.argument<String>("guardianId").orEmpty())
                        .putString(GUARDIAN_VIEWER_ALIAS_KEY, call.argument<String>("primaryAlias").orEmpty())
                        .putString(GUARDIAN_VIEWER_TOKEN_KEY, call.argument<String>("sessionToken").orEmpty())
                        .putLong(GUARDIAN_VIEWER_EXPIRES_KEY, call.argument<Number>("expiresAt")?.toLong() ?: 0L)
                        .apply()
                    result.success(guardianViewerConfig())
                }
                "clearGuardianViewerConfig" -> {
                    getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE).edit()
                        .remove(GUARDIAN_VIEWER_ID_KEY)
                        .remove(GUARDIAN_VIEWER_ALIAS_KEY)
                        .remove(GUARDIAN_VIEWER_TOKEN_KEY)
                        .remove(GUARDIAN_VIEWER_EXPIRES_KEY)
                        .apply()
                    result.success(guardianViewerConfig())
                }
                "getCommunityReporterId" -> {
                    val preferences = getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE)
                    val existing = preferences.getString(COMMUNITY_REPORTER_ID_KEY, null)
                    if (existing != null) {
                        result.success(existing)
                    } else {
                        val generated = UUID.randomUUID().toString()
                        preferences.edit().putString(COMMUNITY_REPORTER_ID_KEY, generated).apply()
                        result.success(generated)
                    }
                }
                "reportSpam" -> result.success(
                    CallerIdentityStore.reportSpam(
                        this,
                        call.argument<String>("number").orEmpty(),
                        call.argument<String>("category").orEmpty(),
                    ).toMap(),
                )
                "setTrusted" -> result.success(
                    CallerIdentityStore.setTrusted(
                        this,
                        call.argument<String>("number").orEmpty(),
                        call.argument<Boolean>("value") == true,
                    ).toMap(),
                )
                "setBlocked" -> result.success(
                    CallerIdentityStore.setBlocked(
                        this,
                        call.argument<String>("number").orEmpty(),
                        call.argument<Boolean>("value") == true,
                    ).toMap(),
                )
                "setCallerLabel" -> result.success(
                    CallerIdentityStore.setLabel(
                        this,
                        call.argument<String>("number").orEmpty(),
                        call.argument<String>("name").orEmpty(),
                    ).toMap(),
                )
                "answer" -> result.success(PhoneCallController.answer())
                "reject" -> result.success(PhoneCallController.reject())
                "disconnect" -> result.success(PhoneCallController.disconnect())
                "setMuted" -> result.success(
                    PhoneCallController.setMuted(call.argument<Boolean>("value") == true),
                )
                "setSpeaker" -> result.success(
                    PhoneCallController.setSpeaker(call.argument<Boolean>("value") == true),
                )
                "setHeld" -> result.success(
                    PhoneCallController.setHeld(call.argument<Boolean>("value") == true),
                )
                "sendDtmf" -> result.success(
                    PhoneCallController.sendDtmf(call.argument<String>("digit").orEmpty()),
                )
                "setSafetyTracking" -> result.success(
                    PhoneCallController.setSafetyTracking(
                        this,
                        call.argument<Boolean>("value") == true,
                    ),
                )
                "requestMicPermission" -> requestMicPermission(result)
                "linkStart" -> result.success(
                    if (!hasMicPermission()) {
                        false
                    } else {
                        LinkCallEngine.start(
                            this,
                            call.argument<String>("wsUrl").orEmpty(),
                            call.argument<String>("code").orEmpty(),
                            call.argument<String>("role").orEmpty(),
                        )
                    },
                )
                "linkEnd" -> result.success(LinkCallEngine.end())
                "linkSetMuted" -> result.success(
                    LinkCallEngine.setMuted(call.argument<Boolean>("value") == true),
                )
                "linkSetSpeaker" -> result.success(
                    LinkCallEngine.setSpeaker(this, call.argument<Boolean>("value") == true),
                )
                "linkAddSignal" -> result.success(
                    LinkCallEngine.addSignal(this, call.argument<String>("signal").orEmpty()),
                )
                "linkSnapshot" -> result.success(LinkCallEngine.snapshot())
                "setAudioCapture" -> result.success(
                    if (call.argument<Boolean>("value") == true && !hasMicPermission()) {
                        false
                    } else {
                        PhoneCallController.setAudioCapture(
                            this,
                            call.argument<Boolean>("value") == true,
                        )
                    },
                )
                "addSafetySignal" -> result.success(
                    PhoneCallController.addSafetySignal(
                        this,
                        call.argument<String>("signal").orEmpty(),
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingDialNumber = dialNumberFrom(intent) ?: pendingDialNumber
    }

    private fun dialerStatus(): Map<String, Boolean> = mapOf(
        "supported" to isDialerRoleSupported(),
        "isDefault" to isDefaultDialer(),
        "screeningSupported" to isCallScreeningSupported(),
        "isScreening" to isCallScreeningApp(),
        "contactsGranted" to hasContactsPermission(),
        "callLogGranted" to hasCallLogPermission(),
    )

    private fun guardianConfig(): Map<String, String> {
        val preferences = getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE)
        return mapOf(
            "primaryAlias" to preferences.getString(GUARDIAN_PRIMARY_ALIAS_KEY, "").orEmpty(),
            "guardianPhone" to preferences.getString(GUARDIAN_PHONE_KEY, "").orEmpty(),
            "guardianId" to preferences.getString(GUARDIAN_ID_KEY, "").orEmpty(),
            "status" to preferences.getString(GUARDIAN_STATUS_KEY, "not_configured").orEmpty(),
        )
    }

    private fun guardianViewerConfig(): Map<String, Any> {
        val preferences = getSharedPreferences(PRIVACY_PREFERENCES, MODE_PRIVATE)
        return mapOf(
            "guardianId" to preferences.getString(GUARDIAN_VIEWER_ID_KEY, "").orEmpty(),
            "primaryAlias" to preferences.getString(GUARDIAN_VIEWER_ALIAS_KEY, "").orEmpty(),
            "sessionToken" to preferences.getString(GUARDIAN_VIEWER_TOKEN_KEY, "").orEmpty(),
            "expiresAt" to preferences.getLong(GUARDIAN_VIEWER_EXPIRES_KEY, 0L),
        )
    }

    private fun isDialerRoleSupported(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val manager = getSystemService(RoleManager::class.java)
            return manager.isRoleAvailable(RoleManager.ROLE_DIALER)
        }
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
    }

    private fun isDefaultDialer(): Boolean =
        getSystemService(TelecomManager::class.java).defaultDialerPackage == packageName

    private fun isCallScreeningSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val manager = getSystemService(RoleManager::class.java)
        return manager.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING)
    }

    private fun isCallScreeningApp(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val manager = getSystemService(RoleManager::class.java)
        return manager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
    }

    private fun requestDefaultDialer(result: MethodChannel.Result) {
        if (!isDialerRoleSupported()) {
            result.success(
                mapOf(
                    "supported" to false,
                    "granted" to false,
                    "message" to "This Android device has no default-phone role.",
                ),
            )
            return
        }
        if (isDefaultDialer()) {
            result.success(
                mapOf(
                    "supported" to true,
                    "granted" to true,
                    "message" to "Kavasam is already the default phone app.",
                ),
            )
            return
        }
        if (pendingRoleResult != null) {
            result.error("ROLE_REQUEST_ACTIVE", "A phone-role request is already open.", null)
            return
        }
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            getSystemService(RoleManager::class.java)
                .createRequestRoleIntent(RoleManager.ROLE_DIALER)
        } else {
            @Suppress("DEPRECATION")
            Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).apply {
                putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, packageName)
            }
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.success(
                mapOf(
                    "supported" to true,
                    "granted" to false,
                    "message" to "Android could not open the phone-role chooser. Use Default apps settings.",
                ),
            )
            return
        }
        pendingRoleResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_DIALER_ROLE)
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private fun requestCallScreening(result: MethodChannel.Result) {
        if (!isCallScreeningSupported()) {
            result.success(
                roleResult(
                    supported = false,
                    granted = false,
                    grantedMessage = "",
                    deniedMessage = "This Android device has no caller-ID screening role.",
                ),
            )
            return
        }
        if (isCallScreeningApp()) {
            result.success(
                roleResult(
                    supported = true,
                    granted = true,
                    grantedMessage = "Caller ID and spam protection are already enabled.",
                    deniedMessage = "",
                ),
            )
            return
        }
        if (pendingScreeningRoleResult != null) {
            result.error("SCREENING_ROLE_ACTIVE", "A caller-ID role request is already open.", null)
            return
        }
        val intent = getSystemService(RoleManager::class.java)
            .createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING)
        if (intent.resolveActivity(packageManager) == null) {
            result.success(
                roleResult(
                    supported = true,
                    granted = false,
                    grantedMessage = "",
                    deniedMessage = "Android could not open the caller-ID role chooser.",
                ),
            )
            return
        }
        pendingScreeningRoleResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_SCREENING_ROLE)
    }

    private fun openDefaultAppsSettings(): Boolean = runCatching {
        val intent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
        if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
        } else {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
        true
    }.getOrDefault(false)

    private fun requestPhonePermission(result: MethodChannel.Result) {
        if (hasPhonePermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_REQUEST_ACTIVE", "A permission request is already open.", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(
                Manifest.permission.CALL_PHONE,
                Manifest.permission.READ_PHONE_STATE,
                Manifest.permission.ANSWER_PHONE_CALLS,
            ),
            REQUEST_PHONE_PERMISSIONS,
        )
    }

    private fun requestContactsPermission(result: MethodChannel.Result) {
        if (hasContactsPermission()) {
            result.success(true)
            return
        }
        if (pendingContactsPermissionResult != null) {
            result.error("CONTACTS_PERMISSION_ACTIVE", "A contacts permission request is already open.", null)
            return
        }
        pendingContactsPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_CONTACTS),
            REQUEST_CONTACTS_PERMISSION,
        )
    }

    private fun requestPhoneDataPermissions(result: MethodChannel.Result) {
        val missing = listOf(
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.READ_CALL_LOG,
        ).filter { permission ->
            checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(dialerStatus())
            return
        }
        if (pendingDataPermissionResult != null) {
            result.error("DATA_PERMISSION_ACTIVE", "A phone-data permission request is already open.", null)
            return
        }
        pendingDataPermissionResult = result
        requestPermissions(missing.toTypedArray(), REQUEST_DATA_PERMISSIONS)
    }

    private fun requestMicPermission(result: MethodChannel.Result) {
        if (hasMicPermission()) {
            result.success(true)
            return
        }
        if (pendingMicPermissionResult != null) {
            result.error("MIC_PERMISSION_ACTIVE", "A microphone permission request is already open.", null)
            return
        }
        pendingMicPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            REQUEST_MIC_PERMISSION,
        )
    }

    private fun hasMicPermission(): Boolean =
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun hasPhonePermission(): Boolean =
        checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED

    private fun hasContactsPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    private fun hasCallLogPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_CALL_LOG) == PackageManager.PERMISSION_GRANTED

    private fun roleResult(
        supported: Boolean,
        granted: Boolean,
        grantedMessage: String,
        deniedMessage: String,
    ): Map<String, Any> = mapOf(
        "supported" to supported,
        "granted" to granted,
        "message" to if (granted) grantedMessage else deniedMessage,
    )

    @SuppressLint("MissingPermission")
    private fun placeCall(rawNumber: String): Map<String, Any> {
        if (!isDefaultDialer()) {
            return mapOf("ok" to false, "message" to "Kavasam is not the default phone app.")
        }
        if (!hasPhonePermission()) {
            return mapOf("ok" to false, "message" to "Phone permission is required.")
        }
        val number = PhoneNumberUtils.stripSeparators(rawNumber).trim()
        if (!Regex("^[+*#0-9]{1,32}$").matches(number)) {
            return mapOf("ok" to false, "message" to "The phone number is invalid.")
        }
        return runCatching {
            getSystemService(TelecomManager::class.java).placeCall(
                Uri.fromParts("tel", number, null),
                Bundle(),
            )
            mapOf("ok" to true, "message" to "Calling $number")
        }.getOrElse { error ->
            mapOf("ok" to false, "message" to (error.message ?: "Android rejected the call."))
        }
    }

    private fun dialNumberFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_DIAL && intent?.action != Intent.ACTION_CALL) return null
        return intent.data?.schemeSpecificPart
    }

    companion object {
        private const val CHANNEL_NAME = "app.kavasam/offline_phone"
        private const val CALL_EVENTS_CHANNEL = "app.kavasam/call_events"
        private const val LINK_EVENTS_CHANNEL = "app.kavasam/link_events"
        private const val PRIVACY_PREFERENCES = "kavasam_privacy"
        private const val CLOUD_CONSENT_KEY = "cloud_ai_consent"
        private const val COMMUNITY_CONSENT_KEY = "community_reputation_consent"
        private const val COMMUNITY_REPORTER_ID_KEY = "community_reporter_id"
        private const val GUARDIAN_PRIMARY_ALIAS_KEY = "guardian_primary_alias"
        private const val GUARDIAN_PHONE_KEY = "guardian_phone"
        private const val GUARDIAN_ID_KEY = "guardian_id"
        private const val GUARDIAN_STATUS_KEY = "guardian_status"
        private const val GUARDIAN_VIEWER_ID_KEY = "guardian_viewer_id"
        private const val GUARDIAN_VIEWER_ALIAS_KEY = "guardian_viewer_alias"
        private const val GUARDIAN_VIEWER_TOKEN_KEY = "guardian_viewer_session_token"
        private const val GUARDIAN_VIEWER_EXPIRES_KEY = "guardian_viewer_expires_at"
        private const val REQUEST_DIALER_ROLE = 4101
        private const val REQUEST_PHONE_PERMISSIONS = 4102
        private const val REQUEST_SCREENING_ROLE = 4103
        private const val REQUEST_CONTACTS_PERMISSION = 4104
        private const val REQUEST_DATA_PERMISSIONS = 4105
        private const val REQUEST_MIC_PERMISSION = 4106
    }
}
