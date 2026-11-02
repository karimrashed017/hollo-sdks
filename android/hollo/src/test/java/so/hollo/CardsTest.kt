package so.hollo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private fun message(kind: String, body: String = "", payload: Map<String, String> = emptyMap()) =
    HolloMessage(id = "m1", sender = "team", kind = kind, body = body, payload = payload, createdAt = "t")

class ReviewUrlTest {
    private val both = mapOf("appStoreId" to "123456789", "playStorePackage" to "com.example.app")

    @Test
    fun opensGooglePlayOnAndroid() {
        assertEquals("market://details?id=com.example.app", reviewUrl("android", both))
    }

    @Test
    fun fallsBackToAWebLinkWhenThePlatformsStoreIsntSet() {
        assertEquals(
            "https://apps.apple.com/app/id123456789?action=write-review",
            reviewUrl("android", mapOf("appStoreId" to "123456789")),
        )
        assertEquals(
            "https://play.google.com/store/apps/details?id=com.example.app",
            playStoreWebUrl(both),
        )
    }

    @Test
    fun returnsNullWithNoStoreIds() {
        assertNull(reviewUrl("android", emptyMap()))
        assertNull(playStoreWebUrl(emptyMap()))
    }
}

class LinkActionTest {
    @Test
    fun opensAUrl() {
        assertEquals(LinkAction.Url("https://example.com"), linkAction(mapOf("url" to " https://example.com ")))
        assertEquals(LinkAction.Url("whatsapp://send?phone=1"), linkAction(mapOf("url" to "whatsapp://send?phone=1")))
    }

    @Test
    fun opensAScreenWithItsValue() {
        assertEquals(LinkAction.Screen("order", "123"), linkAction(mapOf("screen" to "order", "value" to "123")))
        assertEquals(LinkAction.Screen("settings", null), linkAction(mapOf("screen" to "settings")))
    }

    @Test
    fun refusesScriptsAndEmptyCards() {
        assertNull(linkAction(mapOf("url" to "javascript:alert(1)")))
        assertNull(linkAction(mapOf("url" to "JavaScript:alert(1)")))
        assertNull(linkAction(mapOf("url" to "intent://scan/#Intent;scheme=zxing;end")))
        assertNull(linkAction(mapOf("url" to "content://contacts/people")))
        assertNull(linkAction(mapOf("url" to "file:///sdcard/secret")))
        assertNull(linkAction(emptyMap()))
    }
}

class CardContentTest {
    @Test
    fun reviewUsesTheButtonTheServerSent() {
        val card = cardContent(message(KIND_REVIEW, "Enjoying Habitly?", mapOf("cta" to "Laisser un avis")), "en-US")
        assertEquals(CardContent(title = "", text = "Enjoying Habitly?", cta = "Laisser un avis"), card)
    }

    @Test
    fun reviewButtonFallsBackToTheDeviceLanguage() {
        assertEquals("Bewertung schreiben", cardContent(message(KIND_REVIEW, "Hi"), "de-AT")?.cta)
        assertEquals("写评价", cardContent(message(KIND_REVIEW, "Hi"), "zh-Hant-TW")?.cta)
        assertEquals("Leave a review", cardContent(message(KIND_REVIEW, "Hi"), "sv-SE")?.cta)
        assertEquals("Leave a review", cardContent(message(KIND_REVIEW, "Hi"), null)?.cta)
    }

    @Test
    fun reviewButtonCoversEveryDashboardLanguage() {
        assertEquals("Dejar una reseña", reviewButton("es"))
        assertEquals("Deixar uma avaliação", reviewButton("pt_BR"))
        assertEquals("اكتب تقييمًا", reviewButton("ar"))
        assertEquals("レビューを書く", reviewButton("JA"))
        assertEquals("रिव्यू लिखें", reviewButton("hi-IN"))
    }

    @Test
    fun reviewWithNoTextGetsADefault() {
        assertEquals(
            "Enjoying the app? A quick review helps us a lot.",
            cardContent(message(KIND_REVIEW), "en")?.text,
        )
    }

    @Test
    fun offerShowsTitleDescriptionAndCta() {
        val payload = mapOf(
            "offerId" to "o1",
            "title" to "Pro, 50% off",
            "description" to "For three months",
            "cta" to "Get it",
            "ref" to "pro_50",
        )
        val offer = message(KIND_OFFER, "Pro, 50% off", payload)
        assertEquals(CardContent("Pro, 50% off", "For three months", "Get it"), cardContent(offer, "en"))
        assertEquals(HolloOffer(ref = "pro_50", title = "Pro, 50% off"), offerFrom(offer))
        assertEquals("See offer", cardContent(message(KIND_OFFER, payload = mapOf("title" to "x")), "en")?.cta)
    }

    @Test
    fun linkShowsItsBodyAndLabel() {
        val link = message(KIND_LINK, "Chat with us on WhatsApp", mapOf("label" to "Open WhatsApp", "url" to "whatsapp://"))
        assertEquals(CardContent("", "Chat with us on WhatsApp", "Open WhatsApp"), cardContent(link, "en"))
        assertEquals("Open", cardContent(message(KIND_LINK, "x"), "en")?.cta)
    }

    @Test
    fun onlyCardKindsAreCards() {
        assertTrue(isCard(KIND_REVIEW))
        assertTrue(isCard(KIND_OFFER))
        assertTrue(isCard(KIND_LINK))
        assertFalse(isCard("text"))
        assertNull(cardContent(message("text", "Hello"), "en"))
    }
}
