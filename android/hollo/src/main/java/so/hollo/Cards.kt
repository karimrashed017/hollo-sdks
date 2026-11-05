package so.hollo

// Pure helpers for the cards the team sends (review requests, offers and
// links), kept apart from the UI so they can be unit-tested.

/** The store page to leave a review on, per platform. */
internal fun reviewUrl(os: String, payload: Map<String, String>): String? {
    val ios = payload["appStoreId"].orEmpty()
    val android = payload["playStorePackage"].orEmpty()
    if (os == "android" && android.isNotEmpty()) return "market://details?id=$android"
    if (os == "ios" && ios.isNotEmpty()) {
        return "itms-apps://itunes.apple.com/app/id$ios?action=write-review"
    }
    if (ios.isNotEmpty()) return "https://apps.apple.com/app/id$ios?action=write-review"
    if (android.isNotEmpty()) return "https://play.google.com/store/apps/details?id=$android"
    return null
}

/** The web Play Store page, for phones with no Play Store app to take market:// links. */
internal fun playStoreWebUrl(payload: Map<String, String>): String? =
    payload["playStorePackage"]?.takeIf { it.isNotEmpty() }
        ?.let { "https://play.google.com/store/apps/details?id=$it" }

/** What tapping a link card does: open a URL, or one of the app's screens. */
internal sealed interface LinkAction {
    data class Url(val url: String) : LinkAction

    data class Screen(val screen: String, val value: String?) : LinkAction
}

// Never opened from a card, whatever the server sends. intent: and content:
// are Android-specific ways to reach into other apps' components and files.
private val BLOCKED = Regex("^(javascript|data|file|vbscript|blob|intent|content):", RegexOption.IGNORE_CASE)

internal fun linkAction(payload: Map<String, String>): LinkAction? {
    val url = payload["url"]?.trim().orEmpty()
    if (url.isNotEmpty()) return if (BLOCKED.containsMatchIn(url)) null else LinkAction.Url(url)
    val screen = payload["screen"].orEmpty()
    if (screen.isEmpty()) return null
    return LinkAction.Screen(screen, payload["value"])
}

// The review button in the languages the dashboard writes review requests in
// (src/lib/reviews.ts). Cards normally carry it as payload.cta; this covers
// older cards sent before that field existed.
private val REVIEW_BUTTONS = mapOf(
    "en" to "Leave a review",
    "es" to "Dejar una reseña",
    "fr" to "Laisser un avis",
    "de" to "Bewertung schreiben",
    "it" to "Lascia una recensione",
    "pt" to "Deixar uma avaliação",
    "nl" to "Review schrijven",
    "ar" to "اكتب تقييمًا",
    "tr" to "Değerlendir",
    "ru" to "Оставить отзыв",
    "ja" to "レビューを書く",
    "ko" to "리뷰 남기기",
    "zh" to "写评价",
    "hi" to "रिव्यू लिखें",
)

/** "de-AT" or "zh_Hant_TW" from the device, as the review button's language. */
internal fun reviewButton(language: String?): String {
    val code = language.orEmpty().lowercase().split('-', '_').first()
    return REVIEW_BUTTONS[code] ?: REVIEW_BUTTONS.getValue("en")
}

internal const val KIND_REVIEW = "review_request"
internal const val KIND_OFFER = "offer"
internal const val KIND_LINK = "link"

internal fun isCard(kind: String) = kind == KIND_REVIEW || kind == KIND_OFFER || kind == KIND_LINK

/** What a card shows: an optional title and text, and its one button. */
internal data class CardContent(val title: String, val text: String, val cta: String)

internal fun cardContent(message: HolloMessage, language: String?): CardContent? {
    val p = message.payload
    return when (message.kind) {
        // Review requests carry the team's wording in the user's language.
        KIND_REVIEW -> CardContent(
            title = "",
            text = message.body.ifEmpty { "Enjoying the app? A quick review helps us a lot." },
            cta = p["cta"]?.takeIf { it.isNotBlank() } ?: reviewButton(language),
        )
        KIND_LINK -> CardContent(
            title = "",
            text = message.body,
            cta = p["label"]?.takeIf { it.isNotBlank() } ?: "Open",
        )
        KIND_OFFER -> CardContent(
            title = p["title"].orEmpty(),
            text = p["description"].orEmpty(),
            cta = p["cta"]?.takeIf { it.isNotBlank() } ?: "See offer",
        )
        else -> null
    }
}

/** The offer a tapped card stands for, passed to Hollo.onOffer. */
internal fun offerFrom(message: HolloMessage) =
    HolloOffer(ref = message.payload["ref"].orEmpty(), title = message.payload["title"].orEmpty())

// Action confirm cards: the AI asks before it changes something (F-42). Drawn
// apart from the one-button cards above, with Confirm and Cancel.

internal const val KIND_ACTION_CONFIRM = "action_confirm"
internal const val CONFIRM_PENDING = "pending"
internal const val CONFIRM_CONFIRMED = "confirmed"
internal const val CONFIRM_CANCELLED = "cancelled"

/** Set on the phone when the server answers 409: answered elsewhere, or expired. */
internal const val CONFIRM_UNAVAILABLE = "unavailable"

/** What an action confirm card shows instead of its buttons, or [PENDING] for the buttons. */
internal enum class ConfirmState(val label: String) {
    PENDING(""),
    CONFIRMED("Confirmed"),
    CANCELLED("Cancelled"),
    EXPIRED("Expired"),
    UNAVAILABLE("No longer available"),
}

internal fun confirmState(confirm: ActionConfirm, nowMs: Long): ConfirmState = when (confirm.status) {
    CONFIRM_CONFIRMED -> ConfirmState.CONFIRMED
    CONFIRM_CANCELLED -> ConfirmState.CANCELLED
    CONFIRM_UNAVAILABLE -> ConfirmState.UNAVAILABLE
    else -> {
        // An unreadable time doesn't lock the card; the server still checks.
        val expires = confirm.expiresAt?.let { parseIsoMillis(it) }
        if (expires != null && expires <= nowMs) ConfirmState.EXPIRED else ConfirmState.PENDING
    }
}

/** "label: value" for each input, skipping the colon when there's no value. */
internal fun confirmLines(confirm: ActionConfirm): List<String> =
    confirm.inputs.map { if (it.value.isEmpty()) it.label else "${it.label}: ${it.value}" }

private val ISO_TIME = Regex(
    """(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|z|[+-]\d{2}(?::?\d{2})?)?""",
)

/**
 * An ISO 8601 time (as Postgres and JavaScript write it) in epoch
 * milliseconds, or null. By hand because java.time needs API 26 and the SDK
 * supports 24. No offset is read as UTC.
 */
internal fun parseIsoMillis(text: String): Long? {
    val m = ISO_TIME.matchEntire(text.trim()) ?: return null
    val g = m.groupValues
    val calendar = java.util.GregorianCalendar(java.util.TimeZone.getTimeZone("UTC"))
    calendar.clear()
    calendar.set(g[1].toInt(), g[2].toInt() - 1, g[3].toInt(), g[4].toInt(), g[5].toInt(), g[6].ifEmpty { "0" }.toInt())
    val millis = g[7].take(3).padEnd(3, '0').toInt()
    val offset = g[8]
    val offsetMinutes = if (offset.isEmpty() || offset == "Z" || offset == "z") {
        0
    } else {
        val digits = offset.substring(1).replace(":", "")
        val minutes = digits.take(2).toInt() * 60 + digits.drop(2).ifEmpty { "0" }.toInt()
        if (offset[0] == '-') -minutes else minutes
    }
    return calendar.timeInMillis + millis - offsetMinutes * 60_000L
}
