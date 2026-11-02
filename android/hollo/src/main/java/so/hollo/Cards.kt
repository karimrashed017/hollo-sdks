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
