package app.kavasam.kavasam_mobile

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.telecom.Call
import android.telecom.VideoProfile
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

object PhoneCallController {
    private const val PREFS = "kavasam_offline_phone"
    private const val HISTORY = "history"
    private const val MAX_HISTORY = 30

    private var service: KavasamInCallService? = null
    private var appContext: Context? = null
    private var call: Call? = null
    private var number = "Unknown number"
    private var direction = "outgoing"
    private var startedAt = 0L
    private var identity: CallerIdentity? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) = emitSnapshot()
        override fun onDetailsChanged(call: Call, details: Call.Details) {
            refreshDetails(call, details)
            emitSnapshot()
        }
    }

    @Synchronized
    fun setEventSink(value: EventChannel.EventSink?) {
        eventSink = value
        emitSnapshot()
    }

    @Synchronized
    fun attach(value: KavasamInCallService) {
        service = value
    }

    @Synchronized
    fun detach(value: KavasamInCallService) {
        if (service === value) service = null
    }

    @Synchronized
    fun onCallAdded(context: Context, value: Call) {
        call?.unregisterCallback(callCallback)
        appContext = context.applicationContext
        call = value
        value.registerCallback(callCallback, mainHandler)
        number = value.details.handle?.schemeSpecificPart ?: "Unknown number"
        direction = callDirection(value.details, value.state)
        startedAt = System.currentTimeMillis()
        identity = CallerIdentityStore.assess(context, number, direction)
        CallSafetyTracker.onCallStarted(context, number)
        emitSnapshot()
    }

    @Synchronized
    fun onCallRemoved(context: Context, value: Call) {
        if (call !== value) return
        saveHistory(context, System.currentTimeMillis())
        val latestIdentity = identity
        CallerIdentityStore.recordCompletedCall(
            context = context,
            rawNumber = number,
            direction = direction,
            riskScore = latestIdentity?.riskScore ?: 0,
            isContact = latestIdentity?.isContact ?: false,
        )
        CallSafetyTracker.finishCall(context)
        value.unregisterCallback(callCallback)
        call = null
        appContext = null
        identity = null
        emitSnapshot()
    }

    fun onAudioStateChanged() = emitSnapshot()

    @Synchronized
    private fun refreshDetails(value: Call, details: Call.Details) {
        if (call !== value) return
        val updatedDirection = callDirection(details, value.state)
        val updatedNumber = details.handle?.schemeSpecificPart ?: number
        if (updatedNumber != number || updatedDirection != direction) {
            number = updatedNumber
            direction = updatedDirection
            appContext?.let { context ->
                identity = CallerIdentityStore.assess(context, number, direction)
            }
        }
    }

    private fun callDirection(details: Call.Details, state: Int): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            when (details.callDirection) {
                Call.Details.DIRECTION_INCOMING -> "incoming"
                Call.Details.DIRECTION_OUTGOING -> "outgoing"
                else -> if (state == Call.STATE_RINGING) "incoming" else "outgoing"
            }
        } else if (state == Call.STATE_RINGING) {
            "incoming"
        } else {
            "outgoing"
        }

    @Synchronized
    fun snapshot(): Map<String, Any?>? {
        val active = call ?: return null
        val inCallService = service
        val caller = identity
        return mapOf(
            "number" to (active.details.handle?.schemeSpecificPart ?: number),
            "displayName" to (caller?.displayName ?: number),
            "riskScore" to (caller?.riskScore ?: 0),
            "riskLabel" to (caller?.riskLabel ?: "Unverified"),
            "category" to (caller?.category ?: "Uncategorized"),
            "isTrusted" to (caller?.isTrusted ?: false),
            "isBlocked" to (caller?.isBlocked ?: false),
            "reasons" to (caller?.reasons ?: emptyList<String>()),
            "direction" to direction,
            "state" to stateName(active.state),
            "muted" to (inCallService?.isMutedNow() ?: false),
            "speakerOn" to (inCallService?.isSpeakerOnNow() ?: false),
            "canHold" to (
                active.details.callCapabilities and Call.Details.CAPABILITY_HOLD != 0
            ),
        ) + CallSafetyTracker.snapshot()
    }

    @Synchronized
    fun answer(): Boolean = call?.let {
        it.answer(VideoProfile.STATE_AUDIO_ONLY)
        emitSnapshot()
        true
    } ?: false

    @Synchronized
    fun reject(): Boolean = call?.let {
        it.reject(false, null)
        emitSnapshot()
        true
    } ?: false

    @Synchronized
    fun disconnect(): Boolean = call?.let {
        it.disconnect()
        emitSnapshot()
        true
    } ?: false

    @Synchronized
    fun setHeld(value: Boolean): Boolean = call?.let {
        if (value) it.hold() else it.unhold()
        emitSnapshot()
        true
    } ?: false

    @Synchronized
    fun sendDtmf(digit: String): Boolean {
        val tone = digit.singleOrNull() ?: return false
        if (tone !in "0123456789*#") return false
        return call?.let {
            it.playDtmfTone(tone)
            mainHandler.postDelayed({ it.stopDtmfTone() }, DTMF_TONE_MILLIS)
            true
        } ?: false
    }

    @Synchronized
    fun setSafetyTracking(context: Context, value: Boolean): Boolean {
        if (call == null) return false
        val caller = identity ?: CallerIdentityStore.assess(context, number, direction)
        return CallSafetyTracker.setEnabled(context, value, caller)
    }

    @Synchronized
    fun addSafetySignal(context: Context, signal: String): Boolean {
        if (call == null) return false
        return CallSafetyTracker.addSignal(context, signal)
    }

    @Synchronized
    fun setMuted(value: Boolean): Boolean = service?.setMutedSafely(value) ?: false

    @Suppress("DEPRECATION")
    @Synchronized
    fun setSpeaker(value: Boolean): Boolean = service?.setSpeakerSafely(value) ?: false

    private fun emitSnapshot() {
        // A snapshot failure must degrade to a missed UI update, never crash the
        // process: process death unbinds the InCallService and Android hands the
        // call to the system dialer UI.
        val value = runCatching { snapshot() }.getOrNull()
        val send = { eventSink?.success(value) }
        if (Looper.myLooper() == Looper.getMainLooper()) send() else mainHandler.post { send() }
    }

    fun history(context: Context): List<Map<String, Any>> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(HISTORY, "[]") ?: "[]"
        val values = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
        return (0 until values.length()).mapNotNull { index ->
            values.optJSONObject(index)?.let { item ->
                val entryNumber = item.optString("number", "Unknown number")
                val caller = CallerIdentityStore.assess(context, entryNumber, "history")
                mapOf(
                    "number" to entryNumber,
                    "displayName" to caller.displayName,
                    "riskScore" to caller.riskScore,
                    "riskLabel" to caller.riskLabel,
                    "category" to caller.category,
                    "isTrusted" to caller.isTrusted,
                    "isBlocked" to caller.isBlocked,
                    "reports" to caller.reports,
                    "similarity" to caller.similarity,
                    "reasons" to caller.reasons,
                    "direction" to item.optString("direction", "outgoing"),
                    "startedAt" to item.optLong("startedAt", 0L),
                    "endedAt" to item.optLong("endedAt", 0L),
                )
            }
        }
    }

    private fun saveHistory(context: Context, endedAt: Long) {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = runCatching {
            JSONArray(preferences.getString(HISTORY, "[]") ?: "[]")
        }.getOrDefault(JSONArray())
        val updated = JSONArray().put(
            JSONObject()
                .put("number", number)
                .put("direction", direction)
                .put("startedAt", startedAt)
                .put("endedAt", endedAt),
        )
        for (index in 0 until minOf(current.length(), MAX_HISTORY - 1)) {
            updated.put(current.get(index))
        }
        preferences.edit().putString(HISTORY, updated.toString()).apply()
    }

    private fun stateName(value: Int): String = when (value) {
        Call.STATE_NEW -> "new"
        Call.STATE_CONNECTING -> "connecting"
        Call.STATE_SELECT_PHONE_ACCOUNT -> "selecting_account"
        Call.STATE_DIALING -> "dialing"
        Call.STATE_RINGING -> "ringing"
        Call.STATE_ACTIVE -> "active"
        Call.STATE_HOLDING -> "holding"
        Call.STATE_DISCONNECTING -> "disconnecting"
        Call.STATE_DISCONNECTED -> "disconnected"
        else -> "unknown"
    }

    private const val DTMF_TONE_MILLIS = 140L
}
