package app.kavasam.kavasam_mobile

import android.content.Context

object CallProtectionSettings {
    private const val PREFERENCES = "kavasam_call_protection"
    private const val BLOCK_PRIVATE = "block_private"
    private const val BLOCK_UNKNOWN = "block_unknown"
    private const val BLOCK_HIGH_RISK = "block_high_risk"
    private val allowed = setOf(BLOCK_PRIVATE, BLOCK_UNKNOWN, BLOCK_HIGH_RISK)

    fun snapshot(context: Context): Map<String, Boolean> {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        return mapOf(
            "blockPrivate" to preferences.getBoolean(BLOCK_PRIVATE, false),
            "blockUnknown" to preferences.getBoolean(BLOCK_UNKNOWN, false),
            "blockHighRisk" to preferences.getBoolean(BLOCK_HIGH_RISK, false),
        )
    }

    fun set(context: Context, key: String, value: Boolean): Map<String, Boolean> {
        if (key in allowed) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(key, value)
                .apply()
        }
        return snapshot(context)
    }

    fun shouldBlock(context: Context, identity: CallerIdentity): Boolean {
        if (identity.isBlocked) return true
        val settings = snapshot(context)
        if (settings["blockPrivate"] == true && identity.number == "Unknown number") return true
        if (
            settings["blockUnknown"] == true &&
            !identity.isContact &&
            !identity.isTrusted
        ) return true
        return settings["blockHighRisk"] == true && identity.riskScore >= 70
    }
}
