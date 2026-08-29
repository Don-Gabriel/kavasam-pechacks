package app.kavasam.kavasam_mobile

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.sqrt

data class SafetySignal(
    val key: String,
    val label: String,
    val reason: String,
    val weight: Int,
)

object CallSafetyTracker {
    private const val PREFS = "kavasam_call_safety"
    private const val ACTIVE = "active_session"
    private const val HISTORY = "session_history"
    private const val HIGH_RISK_HISTORY = "high_risk_analysis_history"
    private const val MAX_HISTORY = 30
    private const val MAX_HIGH_RISK_HISTORY = 100
    private const val HIGH_RISK_RETENTION_MS = 7L * 24L * 60L * 60L * 1000L

    private val definitions = linkedMapOf(
        "otp_pin" to SafetySignal(
            "otp_pin",
            "Asked for OTP or PIN",
            "Legitimate support staff should not ask for an OTP, PIN, or password.",
            34,
        ),
        "payment_transfer" to SafetySignal(
            "payment_transfer",
            "Urgent payment request",
            "The caller is pressuring you to transfer money immediately.",
            30,
        ),
        "remote_access" to SafetySignal(
            "remote_access",
            "Install or share screen",
            "Remote-access and screen-sharing requests are common scam tactics.",
            38,
        ),
        "impersonation" to SafetySignal(
            "impersonation",
            "Claims to be authority",
            "The caller claims to represent a bank, police, government, or employer.",
            22,
        ),
        "secrecy_urgency" to SafetySignal(
            "secrecy_urgency",
            "Secrecy or extreme urgency",
            "Pressure to act secretly or immediately reduces time to verify the claim.",
            24,
        ),
        "threats" to SafetySignal(
            "threats",
            "Threats or fear",
            "Threats of arrest, account closure, or harm are strong manipulation signals.",
            28,
        ),
    )

    private data class Session(
        val number: String,
        val startedAt: Long,
        val baseRisk: Int,
        val baseReasons: List<String>,
        val signals: LinkedHashSet<String> = linkedSetOf(),
    )

    private var active: Session? = null
    private var currentNumber: String = "Unknown number"

    @Synchronized
    fun onCallStarted(context: Context, number: String) {
        if (active != null) finish(context, "replaced_by_new_call")
        currentNumber = CallerIdentityStore.normalize(number)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(ACTIVE)
            .apply()
    }

    @Synchronized
    fun setEnabled(
        context: Context,
        enabled: Boolean,
        identity: CallerIdentity,
    ): Boolean {
        if (enabled) {
            if (active == null) {
                active = Session(
                    number = currentNumber,
                    startedAt = System.currentTimeMillis(),
                    baseRisk = identity.riskScore,
                    baseReasons = identity.reasons,
                )
                persistActive(context)
            }
        } else {
            finish(context, "stopped_by_user")
        }
        return active != null
    }

    @Synchronized
    fun addSignal(context: Context, key: String): Boolean {
        val session = active ?: return false
        if (!definitions.containsKey(key)) return false
        session.signals += key
        persistActive(context)
        return true
    }

    @Synchronized
    fun finishCall(context: Context) {
        finish(context, "call_ended")
        currentNumber = "Unknown number"
    }

    @Synchronized
    fun snapshot(): Map<String, Any> {
        val session = active ?: return mapOf(
            "trackingEnabled" to false,
            "trackingRiskScore" to 0,
            "trackingRiskLabel" to "Tracking off",
            "trackingSimilarity" to 0.0,
            "trackingSignals" to emptyList<String>(),
            "trackingReasons" to emptyList<String>(),
            "trackingStartedAt" to 0L,
            "audioCaptured" to false,
        )
        val score = score(session)
        return mapOf(
            "trackingEnabled" to true,
            "trackingRiskScore" to score,
            "trackingRiskLabel" to riskLabel(score),
            "trackingSimilarity" to similarity(session),
            "trackingSignals" to session.signals.toList(),
            "trackingReasons" to reasons(session),
            "trackingStartedAt" to session.startedAt,
            "audioCaptured" to false,
        )
    }

    fun availableSignals(): List<Map<String, Any>> = definitions.values.map { signal ->
        mapOf(
            "key" to signal.key,
            "label" to signal.label,
            "reason" to signal.reason,
            "weight" to signal.weight,
        )
    }

    fun analytics(context: Context): Map<String, Any> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(HISTORY, "[]") ?: "[]"
        val history = runCatching { JSONArray(raw) }.getOrDefault(JSONArray())
        var suspicious = 0
        for (index in 0 until history.length()) {
            if ((history.optJSONObject(index)?.optInt("riskScore", 0) ?: 0) >= 50) {
                suspicious += 1
            }
        }
        return mapOf(
            "trackedCalls" to history.length(),
            "suspiciousTrackedCalls" to suspicious,
            "dangerousAnalysesStored" to highRiskAnalyses(context).size,
        )
    }

    @Synchronized
    fun saveHighRiskAnalysis(context: Context, value: Map<String, Any?>): Boolean {
        val risk = (value["risk"] as? Number)?.toInt() ?: return false
        if (risk <= 80) return false
        val now = System.currentTimeMillis()
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = retainedHighRiskArray(preferences.getString(HIGH_RISK_HISTORY, "[]"), now)
        val reportId = value["reportId"]?.toString().orEmpty()
        val updated = JSONArray()
        if ((0 until existing.length()).none {
                existing.optJSONObject(it)?.optString("reportId") == reportId
            }) {
            updated.put(
                JSONObject()
                    .put("reportId", reportId)
                    .put("callSessionId", value["callSessionId"]?.toString().orEmpty())
                    .put("number", value["number"]?.toString().orEmpty())
                    .put("displayName", value["displayName"]?.toString().orEmpty())
                    .put("occurredAt", (value["occurredAt"] as? Number)?.toLong() ?: now)
                    .put("risk", risk.coerceIn(81, 100))
                    .put("riskLabel", value["riskLabel"]?.toString().orEmpty())
                    .put("summary", value["summary"]?.toString().orEmpty().take(360))
                    .put("source", value["source"]?.toString().orEmpty())
                    .put("vectorDatabase", value["vectorDatabase"]?.toString().orEmpty())
                    .put("signals", JSONArray((value["signals"] as? List<*>) ?: emptyList<Any>()))
                    .put("expiresAt", now + HIGH_RISK_RETENTION_MS),
            )
        }
        for (index in 0 until minOf(existing.length(), MAX_HIGH_RISK_HISTORY - updated.length())) {
            updated.put(existing.get(index))
        }
        preferences.edit().putString(HIGH_RISK_HISTORY, updated.toString()).apply()
        return true
    }

    @Synchronized
    fun highRiskAnalyses(context: Context): List<Map<String, Any>> {
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val retained = retainedHighRiskArray(
            preferences.getString(HIGH_RISK_HISTORY, "[]"),
            System.currentTimeMillis(),
        )
        preferences.edit().putString(HIGH_RISK_HISTORY, retained.toString()).apply()
        return (0 until retained.length()).mapNotNull { index ->
            retained.optJSONObject(index)?.let { item ->
                mapOf(
                    "reportId" to item.optString("reportId"),
                    "callSessionId" to item.optString("callSessionId"),
                    "number" to item.optString("number"),
                    "displayName" to item.optString("displayName"),
                    "occurredAt" to item.optLong("occurredAt"),
                    "risk" to item.optInt("risk"),
                    "riskLabel" to item.optString("riskLabel"),
                    "summary" to item.optString("summary"),
                    "source" to item.optString("source"),
                    "vectorDatabase" to item.optString("vectorDatabase"),
                    "signals" to item.optJSONArray("signals").toStringList(),
                    "expiresAt" to item.optLong("expiresAt"),
                )
            }
        }
    }

    private fun retainedHighRiskArray(raw: String?, now: Long): JSONArray {
        val source = runCatching { JSONArray(raw ?: "[]") }.getOrDefault(JSONArray())
        val retained = JSONArray()
        for (index in 0 until source.length()) {
            val item = source.optJSONObject(index) ?: continue
            if (item.optInt("risk", 0) > 80 && item.optLong("expiresAt", 0L) > now) {
                retained.put(item)
            }
        }
        return retained
    }

    private fun finish(context: Context, status: String) {
        val session = active ?: return
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val history = runCatching {
            JSONArray(preferences.getString(HISTORY, "[]") ?: "[]")
        }.getOrDefault(JSONArray())
        val updated = JSONArray().put(
            JSONObject()
                .put("number", session.number)
                .put("startedAt", session.startedAt)
                .put("endedAt", System.currentTimeMillis())
                .put("riskScore", score(session))
                .put("riskLabel", riskLabel(score(session)))
                .put("similarity", similarity(session))
                .put("signals", JSONArray(session.signals.toList()))
                .put("status", status)
                .put("audioCaptured", false),
        )
        for (index in 0 until minOf(history.length(), MAX_HISTORY - 1)) {
            updated.put(history.get(index))
        }
        preferences.edit()
            .putString(HISTORY, updated.toString())
            .remove(ACTIVE)
            .apply()
        active = null
    }

    private fun persistActive(context: Context) {
        val session = active ?: return
        val value = JSONObject()
            .put("number", session.number)
            .put("startedAt", session.startedAt)
            .put("baseRisk", session.baseRisk)
            .put("signals", JSONArray(session.signals.toList()))
            .put("audioCaptured", false)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(ACTIVE, value.toString())
            .apply()
    }

    private fun score(session: Session): Int {
        val signalWeight = session.signals.sumOf { key -> definitions[key]?.weight ?: 0 }
        val vectorBonus = if (session.signals.size >= 2) {
            (similarity(session) * 12.0).toInt()
        } else {
            0
        }
        return (session.baseRisk + signalWeight + vectorBonus).coerceIn(0, 100)
    }

    private fun riskLabel(score: Int): String = when {
        score > 80 -> "Dangerous"
        score >= 75 -> "High scam risk"
        score >= 50 -> "Suspicious"
        score >= 25 -> "Use caution"
        else -> "No strong signals"
    }

    private fun reasons(session: Session): List<String> {
        val signalReasons = session.signals.mapNotNull { key -> definitions[key]?.reason }
        val callerReasons = if (session.baseRisk > 0) session.baseReasons else emptyList()
        return (callerReasons + signalReasons).distinct()
    }

    private fun similarity(session: Session): Double {
        val observed = definitions.keys.map { key ->
            if (session.signals.contains(key)) 1.0 else 0.0
        }
        val scamPrototype = listOf(1.0, 0.9, 1.0, 0.75, 0.8, 0.85)
        var dot = 0.0
        var observedLength = 0.0
        var prototypeLength = 0.0
        for (index in observed.indices) {
            dot += observed[index] * scamPrototype[index]
            observedLength += observed[index] * observed[index]
            prototypeLength += scamPrototype[index] * scamPrototype[index]
        }
        if (observedLength == 0.0) return 0.0
        return (dot / (sqrt(observedLength) * sqrt(prototypeLength))).coerceIn(0.0, 1.0)
    }

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).map { index -> optString(index) }
    }
}
