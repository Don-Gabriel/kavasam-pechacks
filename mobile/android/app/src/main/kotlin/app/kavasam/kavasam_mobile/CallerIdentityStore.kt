package app.kavasam.kavasam_mobile

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import android.provider.ContactsContract
import android.telephony.PhoneNumberUtils
import kotlin.math.sqrt

data class CallerIdentity(
    val number: String,
    val displayName: String,
    val category: String,
    val riskScore: Int,
    val riskLabel: String,
    val isContact: Boolean,
    val isTrusted: Boolean,
    val isBlocked: Boolean,
    val reports: Int,
    val similarity: Double,
    val reasons: List<String>,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "number" to number,
        "displayName" to displayName,
        "category" to category,
        "riskScore" to riskScore,
        "riskLabel" to riskLabel,
        "isContact" to isContact,
        "isTrusted" to isTrusted,
        "isBlocked" to isBlocked,
        "reports" to reports,
        "similarity" to similarity,
        "reasons" to reasons,
    )
}

data class LocalProfile(
    val displayName: String?,
    val category: String,
    val reports: Int,
    val trusted: Boolean,
    val blocked: Boolean,
)

object CallerIdentityStore {
    private const val DB_NAME = "kavasam_identity.db"
    private const val DB_VERSION = 1
    private const val ANALYTICS_WINDOW_MS = 30L * 24L * 60L * 60L * 1000L
    private const val BURST_WINDOW_MS = 15L * 60L * 1000L

    @Volatile
    private var helper: IdentityDb? = null

    private fun db(context: Context): SQLiteDatabase {
        val current = helper ?: synchronized(this) {
            helper ?: IdentityDb(context.applicationContext).also { helper = it }
        }
        return current.writableDatabase
    }

    fun normalize(rawNumber: String): String {
        if (rawNumber.isBlank() || rawNumber == "Unknown number") return "Unknown number"
        val stripped = PhoneNumberUtils.stripSeparators(rawNumber).trim()
        val prefix = if (stripped.startsWith('+')) "+" else ""
        val digits = stripped.filter(Char::isDigit)
        return if (digits.isEmpty()) "Unknown number" else prefix + digits
    }

    fun assess(
        context: Context,
        rawNumber: String,
        direction: String,
        verificationFailed: Boolean = false,
        recordScreening: Boolean = false,
    ): CallerIdentity {
        val number = normalize(rawNumber)
        val profile = profile(context, number)
        val contactName = contactName(context, number)
        val isContact = contactName != null
        val burstCount = recentIncomingCount(context, number)

        val reportedFeature = (profile.reports.coerceAtMost(3) / 3.0)
        val burstFeature = (burstCount.coerceAtMost(4) / 4.0)
        val unknownFeature = if (!isContact && !profile.trusted) 1.0 else 0.0
        val verificationFeature = if (verificationFailed) 1.0 else 0.0
        val blockedFeature = if (profile.blocked) 1.0 else 0.0
        val vector = doubleArrayOf(
            reportedFeature,
            burstFeature,
            unknownFeature,
            verificationFeature,
            blockedFeature,
        )
        val spamPrototype = doubleArrayOf(1.0, 0.75, 0.55, 0.8, 1.0)
        val similarity = cosine(vector, spamPrototype)

        val reasons = mutableListOf<String>()
        var risk = 0
        when {
            isContact -> reasons += "Saved in contacts"
            profile.trusted -> reasons += "Marked trusted on this phone"
            else -> {
                risk += 10
                reasons += "Unknown caller"
            }
        }
        if (profile.reports > 0) {
            risk += (profile.reports * 40).coerceAtMost(70)
            reasons += "Reported ${profile.reports} time${if (profile.reports == 1) "" else "s"} on this phone"
        }
        if (burstCount >= 2) {
            risk += ((burstCount - 1) * 12).coerceAtMost(30)
            reasons += "Repeated calls in 15 minutes"
        }
        if (verificationFailed) {
            risk += 22
            reasons += "Carrier number verification failed"
        }
        if (similarity >= 0.72 && !isContact && !profile.trusted) {
            risk += 12
            reasons += "Similar to local spam behavior"
        }
        if (profile.blocked) {
            risk = 100
            reasons += "Blocked on this phone"
        }
        if (isContact || profile.trusted) risk = 0
        risk = risk.coerceIn(0, 100)

        val label = when {
            profile.blocked -> "Blocked"
            risk >= 70 -> "Likely spam"
            risk >= 45 -> "Suspected spam"
            risk >= 25 -> "Unknown caller"
            isContact || profile.trusted -> "Trusted"
            else -> "Unverified"
        }
        val displayName = contactName
            ?: profile.displayName?.takeIf(String::isNotBlank)
            ?: if (number == "Unknown number") "Private caller" else number
        val identity = CallerIdentity(
            number = number,
            displayName = displayName,
            category = profile.category,
            riskScore = risk,
            riskLabel = label,
            isContact = isContact,
            isTrusted = isContact || profile.trusted,
            isBlocked = profile.blocked,
            reports = profile.reports,
            similarity = similarity,
            reasons = reasons.distinct(),
        )

        saveAssessment(context, identity)
        if (recordScreening) {
            recordEvent(context, number, direction, "screened", risk, isContact, profile.blocked)
        }
        return identity
    }

    fun reportSpam(context: Context, rawNumber: String, category: String): CallerIdentity {
        val number = normalize(rawNumber)
        val current = profile(context, number)
        upsertProfile(
            context = context,
            number = number,
            displayName = current.displayName,
            category = category.ifBlank { "Spam" },
            reports = current.reports + 1,
            trusted = false,
            blocked = current.blocked,
        )
        return assess(context, number, "manual")
    }

    fun setTrusted(context: Context, rawNumber: String, trusted: Boolean): CallerIdentity {
        val number = normalize(rawNumber)
        val current = profile(context, number)
        upsertProfile(
            context = context,
            number = number,
            displayName = current.displayName,
            category = if (trusted) {
                "Trusted"
            } else if (current.category == "Trusted") {
                "Uncategorized"
            } else {
                current.category
            },
            reports = if (trusted) 0 else current.reports,
            trusted = trusted,
            blocked = if (trusted) false else current.blocked,
        )
        return assess(context, number, "manual")
    }

    fun setBlocked(context: Context, rawNumber: String, blocked: Boolean): CallerIdentity {
        val number = normalize(rawNumber)
        val current = profile(context, number)
        upsertProfile(
            context = context,
            number = number,
            displayName = current.displayName,
            category = if (blocked) "Blocked spam" else current.category,
            reports = current.reports,
            trusted = if (blocked) false else current.trusted,
            blocked = blocked,
        )
        return assess(context, number, "manual")
    }

    fun setLabel(context: Context, rawNumber: String, displayName: String): CallerIdentity {
        val number = normalize(rawNumber)
        val current = profile(context, number)
        upsertProfile(
            context = context,
            number = number,
            displayName = displayName.trim().take(60),
            category = current.category,
            reports = current.reports,
            trusted = current.trusted,
            blocked = current.blocked,
        )
        return assess(context, number, "manual")
    }

    fun recordCompletedCall(
        context: Context,
        rawNumber: String,
        direction: String,
        riskScore: Int,
        isContact: Boolean,
    ) {
        recordEvent(
            context,
            normalize(rawNumber),
            direction,
            "completed",
            riskScore,
            isContact,
            false,
        )
    }

    fun analytics(context: Context): Map<String, Any> {
        val since = System.currentTimeMillis() - ANALYTICS_WINDOW_MS
        val database = db(context)
        val totals = mutableMapOf<String, Int>()
        database.rawQuery(
            """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN risk_score >= 45 THEN 1 ELSE 0 END) AS spam,
                SUM(CASE WHEN was_blocked = 1 THEN 1 ELSE 0 END) AS blocked,
                SUM(CASE WHEN is_contact = 0 THEN 1 ELSE 0 END) AS unknown
            FROM call_events
            WHERE event_type = 'screened' AND created_at >= ?
            """.trimIndent(),
            arrayOf(since.toString()),
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                totals["screened"] = cursor.getInt(0)
                totals["spam"] = cursor.getInt(1)
                totals["blocked"] = cursor.getInt(2)
                totals["unknown"] = cursor.getInt(3)
            }
        }
        var localReports = 0
        var vectorMatches = 0
        database.rawQuery(
            "SELECT COALESCE(SUM(reports), 0), SUM(CASE WHEN similarity >= 0.72 THEN 1 ELSE 0 END) FROM number_profiles",
            null,
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                localReports = cursor.getInt(0)
                vectorMatches = cursor.getInt(1)
            }
        }
        return mapOf(
            "screened" to (totals["screened"] ?: 0),
            "spam" to (totals["spam"] ?: 0),
            "blocked" to (totals["blocked"] ?: 0),
            "unknown" to (totals["unknown"] ?: 0),
            "localReports" to localReports,
            "vectorMatches" to vectorMatches,
            "windowDays" to 30,
        )
    }

    private fun profile(context: Context, number: String): LocalProfile {
        db(context).query(
            "number_profiles",
            arrayOf("display_name", "category", "reports", "trusted", "blocked"),
            "number_key = ?",
            arrayOf(number),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                return LocalProfile(
                    displayName = cursor.getString(0),
                    category = cursor.getString(1) ?: "Uncategorized",
                    reports = cursor.getInt(2),
                    trusted = cursor.getInt(3) == 1,
                    blocked = cursor.getInt(4) == 1,
                )
            }
        }
        return LocalProfile(null, "Uncategorized", 0, false, false)
    }

    private fun upsertProfile(
        context: Context,
        number: String,
        displayName: String?,
        category: String,
        reports: Int,
        trusted: Boolean,
        blocked: Boolean,
    ) {
        val values = ContentValues().apply {
            put("number_key", number)
            put("display_name", displayName)
            put("category", category)
            put("reports", reports)
            put("trusted", if (trusted) 1 else 0)
            put("blocked", if (blocked) 1 else 0)
            put("updated_at", System.currentTimeMillis())
        }
        db(context).insertWithOnConflict(
            "number_profiles",
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    private fun saveAssessment(context: Context, identity: CallerIdentity) {
        val values = ContentValues().apply {
            put("number_key", identity.number)
            put("last_risk", identity.riskScore)
            put("similarity", identity.similarity)
            put("updated_at", System.currentTimeMillis())
        }
        db(context).update(
            "number_profiles",
            values,
            "number_key = ?",
            arrayOf(identity.number),
        ).takeIf { it > 0 } ?: run {
            values.put("category", identity.category)
            values.put("reports", identity.reports)
            values.put("trusted", if (identity.isTrusted && !identity.isContact) 1 else 0)
            values.put("blocked", if (identity.isBlocked) 1 else 0)
            db(context).insert("number_profiles", null, values)
        }
    }

    private fun recordEvent(
        context: Context,
        number: String,
        direction: String,
        eventType: String,
        riskScore: Int,
        isContact: Boolean,
        wasBlocked: Boolean,
    ) {
        val values = ContentValues().apply {
            put("number_key", number)
            put("direction", direction)
            put("event_type", eventType)
            put("risk_score", riskScore)
            put("is_contact", if (isContact) 1 else 0)
            put("was_blocked", if (wasBlocked) 1 else 0)
            put("created_at", System.currentTimeMillis())
        }
        db(context).insert("call_events", null, values)
    }

    private fun recentIncomingCount(context: Context, number: String): Int {
        if (number == "Unknown number") return 0
        val since = System.currentTimeMillis() - BURST_WINDOW_MS
        db(context).rawQuery(
            """
            SELECT COUNT(*) FROM call_events
            WHERE number_key = ? AND direction = 'incoming'
              AND event_type = 'screened' AND created_at >= ?
            """.trimIndent(),
            arrayOf(number, since.toString()),
        ).use { cursor ->
            return if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }
    }

    private fun contactName(context: Context, number: String): String? {
        if (number == "Unknown number") return null
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            return null
        }
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(number),
        )
        return runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull()
    }

    private fun cosine(left: DoubleArray, right: DoubleArray): Double {
        var dot = 0.0
        var leftLength = 0.0
        var rightLength = 0.0
        for (index in left.indices) {
            dot += left[index] * right[index]
            leftLength += left[index] * left[index]
            rightLength += right[index] * right[index]
        }
        if (leftLength == 0.0 || rightLength == 0.0) return 0.0
        return (dot / (sqrt(leftLength) * sqrt(rightLength))).coerceIn(0.0, 1.0)
    }

    private class IdentityDb(context: Context) :
        SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {
        override fun onCreate(database: SQLiteDatabase) {
            database.execSQL(
                """
                CREATE TABLE number_profiles (
                    number_key TEXT PRIMARY KEY,
                    display_name TEXT,
                    category TEXT NOT NULL DEFAULT 'Uncategorized',
                    reports INTEGER NOT NULL DEFAULT 0,
                    trusted INTEGER NOT NULL DEFAULT 0,
                    blocked INTEGER NOT NULL DEFAULT 0,
                    last_risk INTEGER NOT NULL DEFAULT 0,
                    similarity REAL NOT NULL DEFAULT 0,
                    updated_at INTEGER NOT NULL
                )
                """.trimIndent(),
            )
            database.execSQL(
                """
                CREATE TABLE call_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    number_key TEXT NOT NULL,
                    direction TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    risk_score INTEGER NOT NULL DEFAULT 0,
                    is_contact INTEGER NOT NULL DEFAULT 0,
                    was_blocked INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL
                )
                """.trimIndent(),
            )
            database.execSQL(
                "CREATE INDEX call_events_number_time ON call_events(number_key, created_at)",
            )
            database.execSQL(
                "CREATE INDEX call_events_type_time ON call_events(event_type, created_at)",
            )
        }

        override fun onUpgrade(database: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
    }
}
