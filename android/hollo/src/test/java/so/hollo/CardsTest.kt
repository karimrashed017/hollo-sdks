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

class ActionConfirmTest {
    private val full = """
        {"id":"m5","sender":"ai","kind":"action_confirm","body":"Restore your streak to 41 days?","created_at":"t",
         "payload":{"confirmationId":"0b6f9a8e-1c2d-4e5f-8a9b-0c1d2e3f4a5b","title":"Restore lost streak",
           "summary":"Restore your streak to 41 days","inputs":[{"label":"Streak days","value":"41"}],
           "risk":"low","status":"pending","expiresAt":"2026-11-05T12:00:00.000Z"}}
    """.trimIndent()

    @Test
    fun parsesAFullCard() {
        val message = parseMessage(parseObject(full))!!
        assertEquals(KIND_ACTION_CONFIRM, message.kind)
        assertEquals("Restore your streak to 41 days?", message.body)
        assertEquals(
            ActionConfirm(
                confirmationId = "0b6f9a8e-1c2d-4e5f-8a9b-0c1d2e3f4a5b",
                title = "Restore lost streak",
                summary = "Restore your streak to 41 days",
                inputs = listOf(ActionInput("Streak days", "41")),
                risk = "low",
                status = CONFIRM_PENDING,
                expiresAt = "2026-11-05T12:00:00.000Z",
            ),
            message.confirm,
        )
        assertEquals(listOf("Streak days: 41"), confirmLines(message.confirm!!))
        assertFalse("Not a one-button card", isCard(message.kind))
    }

    @Test
    fun toleratesMissingAndOddFields() {
        val confirm = parseActionConfirm(
            parseObject(
                """
                    {"confirmationId":"c1","title":7,"inputs":[{"label":"Days","value":41},{"value":"no label"},
                     "junk",{"label":"Note","value":null}],"risk":"extreme","status":"weird"}
                """.trimIndent(),
            ),
        )!!
        assertEquals("", confirm.title)
        assertEquals("", confirm.summary)
        assertEquals(listOf(ActionInput("Days", "41"), ActionInput("Note", "")), confirm.inputs)
        assertEquals(listOf("Days: 41", "Note"), confirmLines(confirm))
        assertEquals("medium", confirm.risk)
        assertEquals(CONFIRM_PENDING, confirm.status)
        assertNull(confirm.expiresAt)

        assertEquals(emptyList<ActionInput>(), parseActionConfirm(parseObject("""{"confirmationId":"c1","inputs":"x"}"""))!!.inputs)
    }

    @Test
    fun aCardWithoutAnIdFallsBackToItsText() {
        val message = parseMessage(
            parseObject("""{"id":"m6","sender":"ai","kind":"action_confirm","body":"Restore your streak?","payload":{"title":"x"}}"""),
        )!!
        assertNull(message.confirm)
        assertEquals("Restore your streak?", message.body)
        assertNull(parseMessage(parseObject("""{"id":"m7","kind":"action_confirm","payload":null}"""))!!.confirm)
        assertNull(parseActionConfirm(null))
        // Other kinds never carry one, even with a look-alike payload.
        assertNull(parseMessage(parseObject("""{"id":"m8","kind":"offer","payload":{"confirmationId":"c1"}}"""))!!.confirm)
    }

    @Test
    fun showsTheRightState() {
        val card = parseActionConfirm(parseObject("""{"confirmationId":"c1","expiresAt":"2026-11-05T12:00:00Z"}"""))!!
        val expiry = parseIsoMillis("2026-11-05T12:00:00Z")!!
        assertEquals(ConfirmState.PENDING, confirmState(card, expiry - 1))
        assertEquals(ConfirmState.EXPIRED, confirmState(card, expiry))
        assertEquals(ConfirmState.CONFIRMED, confirmState(card.copy(status = CONFIRM_CONFIRMED), expiry + 1))
        assertEquals(ConfirmState.CANCELLED, confirmState(card.copy(status = CONFIRM_CANCELLED), 0))
        assertEquals("No longer available", confirmState(card.copy(status = CONFIRM_UNAVAILABLE), 0).label)
        assertEquals("Expired", ConfirmState.EXPIRED.label)
        // No time, or one we can't read, leaves the buttons; the server still checks.
        assertEquals(ConfirmState.PENDING, confirmState(card.copy(expiresAt = null), Long.MAX_VALUE))
        assertEquals(ConfirmState.PENDING, confirmState(card.copy(expiresAt = "soon"), Long.MAX_VALUE))
    }

    @Test
    fun readsIsoTimes() {
        assertEquals(1_793_877_600_000L, parseIsoMillis("2026-11-05T11:20:00Z"))
        assertEquals(1_793_877_600_123L, parseIsoMillis("2026-11-05T11:20:00.123456+00:00"))
        assertEquals(1_793_877_600_000L, parseIsoMillis("2026-11-05T13:20:00+02:00"))
        assertEquals(1_793_877_600_000L, parseIsoMillis("2026-11-05T06:20:00-0500"))
        assertEquals(1_793_877_600_500L, parseIsoMillis("2026-11-05 11:20:00.5"))
        assertNull(parseIsoMillis("tomorrow"))
        assertNull(parseIsoMillis(""))
    }
}
