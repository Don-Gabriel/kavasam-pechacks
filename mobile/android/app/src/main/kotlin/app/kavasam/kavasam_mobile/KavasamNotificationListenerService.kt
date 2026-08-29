package app.kavasam.kavasam_mobile

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.Locale

class KavasamNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(statusBarNotification: StatusBarNotification) {
        if (statusBarNotification.packageName == packageName) return
        val extras = statusBarNotification.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        val evidence = listOf(title, body).filter { it.isNotBlank() }.joinToString(". ")
        if (evidence.isBlank()) return
        val assessment = NotificationRiskAnalyzer.analyze(evidence)
        if (assessment.score < 35) return

        ProtectionStore.preferences(this).edit()
            .putString(ProtectionStore.NOTIFICATION_TITLE, title.ifBlank { "Suspicious message" })
            .putString(ProtectionStore.NOTIFICATION_TEXT, evidence)
            .putString(ProtectionStore.NOTIFICATION_PACKAGE, statusBarNotification.packageName)
            .putInt(ProtectionStore.NOTIFICATION_SCORE, assessment.score)
            .putString(ProtectionStore.NOTIFICATION_REASONS, assessment.reasons.joinToString("|"))
            .putLong(ProtectionStore.NOTIFICATION_TIMESTAMP, System.currentTimeMillis())
            .apply()
        KavasamAlerts.show(
            this,
            "Kavasam detected possible fraud",
            "${assessment.reasons.first()}. Tap to run the full safety check.",
            3101,
        )
    }
}

private data class NotificationRisk(val score: Int, val reasons: List<String>)

private object NotificationRiskAnalyzer {
    private val signals = listOf(
        Triple(listOf("digital arrest", "under arrest"), 55, "Digital-arrest language"),
        Triple(listOf("otp", "pin", "cvv", "password"), 35, "Request for a secret credential"),
        Triple(listOf("screen share", "remote access", "anydesk", "teamviewer"), 45, "Remote-access request"),
        Triple(listOf("cbi", "police", "customs", "court", "rbi"), 22, "Authority impersonation"),
        Triple(listOf("upi", "transfer", "pay now", "send money", "refund fee"), 25, "Payment pressure"),
        Triple(listOf("urgent", "immediately", "within 10 minutes", "account blocked"), 18, "Artificial urgency"),
        Triple(listOf("kyc", "verify account", "click here", "bit.ly", "tinyurl"), 20, "Suspicious verification request"),
        Triple(listOf("do not tell", "keep this secret", "stay on the call"), 35, "Isolation tactic"),
    )

    fun analyze(text: String): NotificationRisk {
        val normalized = text.lowercase(Locale.ROOT)
        var score = 0
        val reasons = mutableListOf<String>()
        for ((terms, weight, reason) in signals) {
            if (terms.any(normalized::contains)) {
                score += weight
                reasons += reason
            }
        }
        return NotificationRisk(score.coerceAtMost(100), reasons)
    }
}
