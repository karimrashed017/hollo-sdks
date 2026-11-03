package so.hollo

import java.io.IOException
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

private const val APP_KEY = "app_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
private const val TOKEN_KEY = "hollo.deviceToken.$APP_KEY"

internal class MemoryStorage : HolloStorage {
    val data = mutableMapOf<String, String>()

    override fun get(key: String): String? = data[key]

    override fun set(key: String, value: String) {
        data[key] = value
    }

    override fun remove(key: String) {
        data.remove(key)
    }
}

/** A fake SDK API that answers by "METHOD /path". */
internal class FakeServer(
    private val routes: Map<String, (HolloHttpRequest) -> Pair<Int, String>>,
) : HolloTransport {
    val requests = mutableListOf<HolloHttpRequest>()

    override fun execute(request: HolloHttpRequest): HolloHttpResponse {
        requests += request
        val path = URL(request.url).path.removePrefix("/api/v1")
        val route = routes["${request.method} $path"] ?: error("No route for ${request.method} $path")
        val (status, body) = route(request)
        return HolloHttpResponse(status, body)
    }
}

private fun client(storage: HolloStorage, server: HolloTransport, info: Map<String, String> = emptyMap()) =
    HolloClient(
        appKey = APP_KEY,
        storage = storage,
        platform = "android",
        info = info,
        transport = server,
        io = Dispatchers.Unconfined,
    )

private fun bodyOf(request: HolloHttpRequest): JsonObject = Json.parseToJsonElement(request.body!!).jsonObject

private suspend fun expectHollo(block: suspend () -> Unit): HolloException {
    try {
        block()
    } catch (e: HolloException) {
        return e
    }
    fail("Expected a HolloException")
    throw AssertionError()
}

class HolloClientTest {
    @Test
    fun registersOnceThenSendsTheDeviceTokenOnEveryCall() = runTest {
        var registrations = 0
        val server = FakeServer(
            mapOf(
                "POST /devices" to { _: HolloHttpRequest ->
                    registrations++
                    201 to """{"deviceToken":"hdt_first_token_value_1234","userId":"u1"}"""
                },
                "GET /messages" to { _: HolloHttpRequest -> 200 to """{"messages":[],"unread":0}""" },
            ),
        )
        val storage = MemoryStorage()
        val api = client(storage, server, info = mapOf("language" to "fr-FR"))

        api.messages()
        api.messages()

        assertEquals(1, registrations)
        val register = server.requests.first()
        assertEquals("https://hollo.so/api/v1/devices", register.url)
        assertNull(register.headers["authorization"])
        assertEquals(APP_KEY, register.headers["x-hollo-app-key"])
        val body = bodyOf(register)
        assertEquals(JsonPrimitive("android"), body["platform"])
        assertEquals(JsonPrimitive("fr-FR"), body["info"]!!.jsonObject["language"])

        val last = server.requests.last()
        assertEquals("GET", last.method)
        assertNull(last.body)
        assertEquals(APP_KEY, last.headers["x-hollo-app-key"])
        assertEquals("Bearer hdt_first_token_value_1234", last.headers["authorization"])
        assertEquals("hdt_first_token_value_1234", storage.data[TOKEN_KEY])
    }

    @Test
    fun reusesATokenSavedByAnEarlierLaunch() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_saved"
        val server = FakeServer(mapOf("GET /messages" to { _: HolloHttpRequest -> 200 to """{"messages":[],"unread":2}""" }))

        val response = client(storage, server).messages()

        assertEquals(2, response.unread)
        assertEquals(1, server.requests.size)
        assertEquals("Bearer hdt_saved", server.requests[0].headers["authorization"])
    }

    @Test
    fun registersAgainWhenTheServerHasForgottenTheDevice() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_old"
        val server = FakeServer(
            mapOf(
                "GET /messages" to { request: HolloHttpRequest ->
                    if (request.headers["authorization"] == "Bearer hdt_old") {
                        401 to """{"error":{"code":"invalid_device","message":"Unknown"}}"""
                    } else {
                        200 to """{"messages":[],"unread":0}"""
                    }
                },
                "POST /devices" to { _: HolloHttpRequest -> 201 to """{"deviceToken":"hdt_new"}""" },
            ),
        )

        client(storage, server).messages()

        assertEquals("hdt_new", storage.data[TOKEN_KEY])
        assertEquals(listOf("GET", "POST", "GET"), server.requests.map { it.method })
    }

    @Test
    fun givesUpAfterOneReRegistration() = runTest {
        val server = FakeServer(
            mapOf(
                "GET /messages" to { _: HolloHttpRequest -> 401 to """{"error":{"code":"invalid_device","message":"Unknown"}}""" },
                "POST /devices" to { _: HolloHttpRequest -> 201 to """{"deviceToken":"hdt_again"}""" },
            ),
        )
        val error = expectHollo { client(MemoryStorage(), server).messages() }
        assertEquals("invalid_device", error.code)
        assertEquals(2, server.requests.count { it.method == "POST" })
    }

    @Test
    fun surfacesAMissingPlanAsAClearError() = runTest {
        val server = FakeServer(
            mapOf(
                "POST /devices" to { _: HolloHttpRequest -> 402 to """{"error":{"code":"plan_required","message":"No plan"}}""" },
            ),
        )
        val error = expectHollo { client(MemoryStorage(), server).messages() }
        assertEquals("plan_required", error.code)
        assertEquals("No plan", error.message)
        assertEquals(402, error.status)
    }

    @Test
    fun mapsAnUnreadableErrorBody() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_saved"
        val server = FakeServer(mapOf("GET /messages" to { _: HolloHttpRequest -> 502 to "<html>Bad gateway</html>" }))
        val error = expectHollo { client(storage, server).messages() }
        assertEquals("network_error", error.code)
        assertEquals("Request failed (502)", error.message)
        assertEquals(502, error.status)
    }

    @Test
    fun mapsNoConnectionToStatusZero() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_saved"
        val offline = HolloTransport { throw IOException("Unable to resolve host") }
        val error = expectHollo { client(storage, offline).send("Hello") }
        assertEquals("network_error", error.code)
        assertEquals(0, error.status)
    }

    @Test
    fun parsesMessagesWithCardsProfileAndPushSettings() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_saved"
        val server = FakeServer(
            mapOf(
                "GET /messages" to { _: HolloHttpRequest ->
                    200 to """
                        {
                          "messages": [
                            {"id":"m1","sender":"end_user","kind":"text","body":"Hi","payload":null,"created_at":"2026-11-02T10:00:00.000000+00:00"},
                            {"id":"m2","sender":"team","kind":"offer","body":"Pro","created_at":"2026-11-02T10:01:00+00:00",
                             "payload":{"offerId":"o1","title":"Pro, 50% off","description":"Three months","cta":"Get it","ref":"pro_50","extra":null}},
                            {"sender":"team","kind":"text","body":"no id"}
                          ],
                          "unread": 1,
                          "profile": {"name":"Karim","role":"Founder","photo":"http://insecure.example/p.png","welcome":""},
                          "push": {"permissionCard":"replies_offers","notifyLine":false},
                          "open": true,
                          "branding": false
                        }
                    """.trimIndent()
                },
            ),
        )

        val response = client(storage, server).messages(after = "2026-11-02T09:00:00+00:00")

        assertEquals(
            "https://hollo.so/api/v1/messages?after=2026-11-02T09%3A00%3A00%2B00%3A00",
            server.requests[0].url,
        )
        assertEquals(listOf("m1", "m2"), response.messages.map { it.id })
        assertTrue(response.messages[0].payload.isEmpty())
        val offer = response.messages[1]
        assertEquals("pro_50", offer.payload["ref"])
        assertFalse(offer.payload.containsKey("extra"))
        assertEquals(1, response.unread)
        assertTrue(response.open)
        assertFalse(response.branding)
        assertEquals("Karim", response.profile?.name)
        assertEquals("Founder", response.profile?.role)
        assertNull("Only https photos are loaded", response.profile?.photo)
        assertNull("Blank fields are dropped", response.profile?.welcome)
        assertEquals("replies_offers", response.push?.permissionCard)
        assertEquals(false, response.push?.notifyLine)
    }

    @Test
    fun defaultsWhatTheServerLeftOut() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_saved"
        val server = FakeServer(
            mapOf("GET /messages" to { _: HolloHttpRequest -> 200 to """{"messages":[],"push":{"permissionCard":"weird"}}""" }),
        )
        val response = client(storage, server).messages()
        assertEquals(0, response.unread)
        assertFalse(response.open)
        assertTrue("Branding shows unless the server says no", response.branding)
        assertNull(response.profile)
        assertEquals("off", response.push?.permissionCard)
        assertEquals(true, response.push?.notifyLine)
    }

    @Test
    fun buildsTheOtherRequests() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_saved"
        val server = FakeServer(
            mapOf(
                "POST /messages" to { _: HolloHttpRequest ->
                    201 to """{"message":{"id":"m9","sender":"end_user","kind":"text","body":"Hello","created_at":"t"}}"""
                },
                "POST /identify" to { request: HolloHttpRequest ->
                    val verified = request.body?.contains("\"token\"") == true
                    200 to """{"userId":"u1","verified":$verified}"""
                },
                "POST /links/tap" to { _: HolloHttpRequest -> 200 to """{"ok":true}""" },
                "POST /events" to { _: HolloHttpRequest -> 200 to """{"open":true}""" },
                "POST /push" to { _: HolloHttpRequest -> 200 to """{"ok":true}""" },
                "POST /read" to { _: HolloHttpRequest -> 200 to """{"unread":0}""" },
            ),
        )
        val api = client(storage, server)

        assertEquals("m9", api.send("Hello").id)
        assertEquals(JsonPrimitive("Hello"), bodyOf(server.requests.last())["body"])
        assertEquals("application/json", server.requests.last().headers["content-type"])

        assertEquals(HolloClient.Identified("u1", verified = false), api.identify("user_42", name = "Ada", email = null))
        val identify = bodyOf(server.requests.last())
        assertEquals(JsonPrimitive("user_42"), identify["id"])
        assertEquals(JsonPrimitive("Ada"), identify["name"])
        assertFalse("Unset fields aren't sent", identify.containsKey("email"))
        assertFalse("No token unless given", identify.containsKey("token"))

        val signed = api.identify("user_42", name = null, email = null, identityToken = "a1b2c3")
        assertTrue(signed.verified)
        assertEquals(JsonPrimitive("a1b2c3"), bodyOf(server.requests.last())["token"])

        api.linkTapped("m2", opened = false)
        val tap = bodyOf(server.requests.last())
        assertEquals(JsonPrimitive("m2"), tap["messageId"])
        assertEquals(JsonPrimitive(false), tap["opened"])

        assertTrue(api.event(name = "paywall_declined"))
        assertEquals(setOf("name"), bodyOf(server.requests.last()).keys)
        api.event(subscriber = true)
        assertEquals(JsonPrimitive(true), bodyOf(server.requests.last())["subscriber"])

        api.registerPush("fcm_token_value")
        val push = bodyOf(server.requests.last())
        assertEquals(JsonPrimitive("fcm_token_value"), push["token"])
        assertEquals(JsonPrimitive("fcm"), push["provider"])

        api.registerPush(null)
        assertEquals("null", bodyOf(server.requests.last())["token"].toString())

        api.markRead()
        assertEquals("{}", server.requests.last().body)
    }

    @Test
    fun erasingForgetsTheDevice() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_saved"
        val server = FakeServer(mapOf("DELETE /user" to { _: HolloHttpRequest -> 200 to """{"deleted":true}""" }))

        client(storage, server).eraseUserData()

        assertEquals("DELETE", server.requests[0].method)
        assertNull(server.requests[0].body)
        assertNull(storage.data[TOKEN_KEY])
    }

    @Test
    fun usesACustomApiUrl() = runTest {
        val storage = MemoryStorage()
        storage.data[TOKEN_KEY] = "hdt_saved"
        val server = FakeServer(mapOf("POST /read" to { _: HolloHttpRequest -> 200 to "{}" }))
        HolloClient(
            appKey = APP_KEY,
            apiUrl = "http://10.0.2.2:3000/api/v1/",
            storage = storage,
            transport = server,
            io = Dispatchers.Unconfined,
        ).markRead()
        assertEquals("http://10.0.2.2:3000/api/v1/read", server.requests[0].url)
    }
}
