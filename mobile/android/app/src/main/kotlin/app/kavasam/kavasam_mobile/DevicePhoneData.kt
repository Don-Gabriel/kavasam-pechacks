package app.kavasam.kavasam_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CallLog
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone

object DevicePhoneData {
    private const val MAX_CONTACT_NUMBERS = 1_000
    private const val MAX_CALLS = 100

    fun contacts(context: Context): List<Map<String, Any>> {
        if (!granted(context, Manifest.permission.READ_CONTACTS)) return emptyList()

        val projection = arrayOf(
            Phone.CONTACT_ID,
            Phone.DISPLAY_NAME_PRIMARY,
            Phone.NUMBER,
            Phone.TYPE,
            Phone.LABEL,
            Phone.PHOTO_THUMBNAIL_URI,
            Phone.STARRED,
        )
        val results = mutableListOf<Map<String, Any>>()
        val seenNumbers = linkedSetOf<String>()
        runCatching {
            context.contentResolver.query(
                Phone.CONTENT_URI,
                projection,
                null,
                null,
                "${Phone.SORT_KEY_PRIMARY} COLLATE LOCALIZED ASC",
            )?.use { cursor ->
                while (cursor.moveToNext() && results.size < MAX_CONTACT_NUMBERS) {
                    val rawNumber = cursor.getString(2).orEmpty()
                    val normalized = CallerIdentityStore.normalize(rawNumber)
                    if (normalized == "Unknown number" || !seenNumbers.add(normalized)) continue
                    val typeLabel = Phone.getTypeLabel(
                        context.resources,
                        cursor.getInt(3),
                        cursor.getString(4),
                    ).toString()
                    results += mapOf(
                        "contactId" to cursor.getLong(0),
                        "displayName" to cursor.getString(1).orEmpty().ifBlank { normalized },
                        "number" to rawNumber.ifBlank { normalized },
                        "normalizedNumber" to normalized,
                        "typeLabel" to typeLabel,
                        "photoUri" to cursor.getString(5).orEmpty(),
                        "starred" to (cursor.getInt(6) == 1),
                    )
                }
            }
        }
        return results
    }

    fun callHistory(context: Context): List<Map<String, Any>> {
        if (!granted(context, Manifest.permission.READ_CALL_LOG)) {
            return PhoneCallController.history(context)
        }

        val uri = CallLog.Calls.CONTENT_URI.buildUpon()
            .appendQueryParameter(CallLog.Calls.LIMIT_PARAM_KEY, MAX_CALLS.toString())
            .build()
        val projection = arrayOf(
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
            CallLog.Calls.GEOCODED_LOCATION,
            CallLog.Calls.IS_READ,
        )
        val results = mutableListOf<Map<String, Any>>()
        runCatching {
            context.contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${CallLog.Calls.DATE} DESC",
            )?.use { cursor ->
                while (cursor.moveToNext() && results.size < MAX_CALLS) {
                    val number = cursor.getString(0).orEmpty().ifBlank { "Unknown number" }
                    val cachedName = cursor.getString(1).orEmpty()
                    val callType = callType(cursor.getInt(2))
                    val startedAt = cursor.getLong(3)
                    val endedAt = startedAt + (cursor.getLong(4) * 1_000L)
                    val assessed = CallerIdentityStore.assess(context, number, "history")
                    val identity = if (
                        cachedName.isNotBlank() &&
                        assessed.riskScore < 45 &&
                        !assessed.isBlocked
                    ) {
                        assessed.copy(
                            displayName = cachedName,
                            riskScore = 0,
                            riskLabel = "Trusted",
                            isContact = true,
                            isTrusted = true,
                            reasons = listOf("Saved in contacts"),
                        )
                    } else {
                        assessed
                    }
                    results += identity.toMap() + mapOf(
                        "number" to number,
                        "direction" to direction(callType),
                        "callType" to callType,
                        "startedAt" to startedAt,
                        "endedAt" to endedAt,
                        "location" to cursor.getString(5).orEmpty(),
                        "isRead" to (cursor.getInt(6) == 1),
                        "source" to "system",
                    )
                }
            }
        }
        return results
    }

    private fun callType(value: Int): String = when (value) {
        CallLog.Calls.INCOMING_TYPE -> "incoming"
        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
        CallLog.Calls.MISSED_TYPE -> "missed"
        CallLog.Calls.VOICEMAIL_TYPE -> "voicemail"
        CallLog.Calls.REJECTED_TYPE -> "rejected"
        CallLog.Calls.BLOCKED_TYPE -> "blocked"
        CallLog.Calls.ANSWERED_EXTERNALLY_TYPE -> "answered_elsewhere"
        else -> "unknown"
    }

    private fun direction(callType: String): String = when (callType) {
        "outgoing" -> "outgoing"
        else -> "incoming"
    }

    private fun granted(context: Context, permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
}
