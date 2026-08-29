package app.kavasam.kavasam_mobile

import android.content.Context
import android.content.SharedPreferences

object ProtectionStore {
    const val NOTIFICATION_TITLE = "notification_title"
    const val NOTIFICATION_TEXT = "notification_text"
    const val NOTIFICATION_PACKAGE = "notification_package"
    const val NOTIFICATION_SCORE = "notification_score"
    const val NOTIFICATION_REASONS = "notification_reasons"
    const val NOTIFICATION_TIMESTAMP = "notification_timestamp"
    const val CALL_NUMBER = "call_number"
    const val CALL_VERIFICATION = "call_verification"
    const val CALL_DIRECTION = "call_direction"
    const val CALL_TIMESTAMP = "call_timestamp"

    fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences("kavasam_protection", Context.MODE_PRIVATE)
}
