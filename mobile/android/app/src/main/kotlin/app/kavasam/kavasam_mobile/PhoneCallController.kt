package app.kavasam.kavasam_mobile

import android.content.Context
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.VideoProfile
import org.json.JSONArray
import org.json.JSONObject

object PhoneCallController {
    private const val PREFS = "kavasam_offline_phone"
    private const val HISTORY = "history"
    private const val MAX_HISTORY = 30

    private var service: KavasamInCallService? = null
    private var call: Call? = null
    private var number = "Unknown number"
    private var direction = "outgoing"
    private var startedAt = 0L
    private var identity: CallerIdentity? = null

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
        call = value
        number = value.details.handle?.schemeSpecificPart ?: "Unknown number"
        direction = if (value.state == Call.STATE_RINGING) "incoming" else "outgoing"
        startedAt = System.currentTimeMillis()
        identity = CallerIdentityStore.assess(context, number, direction)
        CallSafetyTracker.onCallStarted(context, number)
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
        call = null
        identity = null
    }

    @Synchronized
    fun snapshot(): Map<String, Any?>? {
        val active = call ?: return null
        val audio = service?.callAudioState
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
            "muted" to (audio?.isMuted ?: false),
            "speakerOn" to ((audio?.route ?: 0) and CallAudioState.ROUTE_SPEAKER != 0),
            "canHold" to (
                active.details.callCapabilities and Call.Details.CAPABILITY_HOLD != 0
            ),
        ) + CallSafetyTracker.snapshot()
    }

    @Synchronized
    fun answer(): Boolean = call?.let {
        it.answer(VideoProfile.STATE_AUDIO_ONLY)
        true
    } ?: false

    @Synchronized
    fun reject(): Boolean = call?.let {
        it.reject(false, null)
        true
    } ?: false

    @Synchronized
    fun disconnect(): Boolean = call?.let {
        it.disconnect()
        true
    } ?: false

    @Synchronized
    fun setHeld(value: Boolean): Boolean = call?.let {
        if (value) it.hold() else it.unhold()
        true
    } ?: false

    @Synchronized
    fun sendDtmf(digit: String): Boolean {
        val tone = digit.singleOrNull() ?: return false
        if (tone !in "0123456789*#") return false
        return call?.let {
            it.playDtmfTone(tone)
            it.stopDtmfTone()
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
    fun setMuted(value: Boolean): Boolean = service?.let {
        it.setMuted(value)
        true
    } ?: false

    @Suppress("DEPRECATION")
    @Synchronized
    fun setSpeaker(value: Boolean): Boolean = service?.let {
        it.setAudioRoute(if (value) CallAudioState.ROUTE_SPEAKER else CallAudioState.ROUTE_EARPIECE)
        true
    } ?: false

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
}
