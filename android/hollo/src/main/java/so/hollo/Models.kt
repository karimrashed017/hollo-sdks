package so.hollo

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

// What the SDK API sends back, parsed defensively: anything missing or of the
// wrong type falls back to a default instead of crashing the host app.

/** An offer card the user tapped. [ref] is the ID you set in the dashboard. */
data class HolloOffer(val ref: String, val title: String)

/**
 * A link card that opens one of your app's screens. [screen] is the name you
 * gave it in the dashboard, [value] its optional value (an order number, say).
 */
data class HolloLink(val screen: String, val value: String?)

/** A failed SDK API call. [code] is the API's error code, like "plan_required". */
class HolloException(
    val code: String,
    message: String,
    /** The HTTP status, or 0 when the server couldn't be reached at all. */
    val status: Int,
    cause: Throwable? = null,
) : Exception(message, cause)

internal object Sender {
    const val END_USER = "end_user"
    const val TEAM = "team"
    const val AI = "ai"
}

internal data class HolloMessage(
    val id: String,
    val sender: String,
    val kind: String,
    val body: String,
    /** Card details for review_request, offer and link messages. */
    val payload: Map<String, String>,
    val createdAt: String,
)

/** Who answers, set on the app's page in the dashboard. */
internal data class HolloProfile(
    val name: String? = null,
    val role: String? = null,
    val photo: String? = null,
    val welcome: String? = null,
)

internal data class HolloPushSettings(
    /** "off", "replies" or "replies_offers". */
    val permissionCard: String = "off",
    val notifyLine: Boolean = true,
)

internal data class MessagesResponse(
    val messages: List<HolloMessage>,
    val unread: Int,
    val profile: HolloProfile?,
    val push: HolloPushSettings?,
    /** An automation asked to open the chat. */
    val open: Boolean,
)

private val PERMISSION_CARDS = setOf("off", "replies", "replies_offers")

internal fun JsonObject.string(key: String): String? {
    val value = this[key]
    return if (value is JsonPrimitive && value.isString) value.content else null
}

/** The body as a JSON object, or an empty one if it isn't JSON at all. */
internal fun parseObject(text: String): JsonObject =
    (
        try {
            Json.parseToJsonElement(text) as? JsonObject
        } catch (e: Exception) {
            null
        }
        ) ?: JsonObject(emptyMap())

internal fun parseMessage(element: JsonElement): HolloMessage? {
    val o = element as? JsonObject ?: return null
    val id = o.string("id") ?: return null
    // The server sends string or null values; nulls are dropped.
    val payload = (o["payload"] as? JsonObject)
        ?.entries
        ?.mapNotNull { (key, value) ->
            if (value is JsonPrimitive && value !is JsonNull) key to value.content else null
        }
        ?.toMap()
        ?: emptyMap()
    return HolloMessage(
        id = id,
        sender = o.string("sender") ?: "system",
        kind = o.string("kind") ?: "text",
        body = o.string("body") ?: "",
        payload = payload,
        createdAt = o.string("created_at") ?: "",
    )
}

internal fun parseProfile(element: JsonElement?): HolloProfile? {
    val o = element as? JsonObject ?: return null
    fun pick(key: String) = o.string(key)?.takeIf { it.isNotBlank() }
    return HolloProfile(
        name = pick("name"),
        role = pick("role"),
        // Only https photos are ever loaded.
        photo = pick("photo")?.takeIf { it.startsWith("https://") },
        welcome = pick("welcome"),
    )
}

internal fun parsePushSettings(element: JsonElement?): HolloPushSettings? {
    val o = element as? JsonObject ?: return null
    val card = o.string("permissionCard")
    return HolloPushSettings(
        permissionCard = if (card != null && card in PERMISSION_CARDS) card else "off",
        notifyLine = (o["notifyLine"] as? JsonPrimitive)?.booleanOrNull != false,
    )
}

internal fun parseMessagesResponse(o: JsonObject): MessagesResponse =
    MessagesResponse(
        messages = (o["messages"] as? JsonArray)?.mapNotNull { parseMessage(it) } ?: emptyList(),
        unread = (o["unread"] as? JsonPrimitive)?.intOrNull ?: 0,
        profile = parseProfile(o["profile"]),
        push = parsePushSettings(o["push"]),
        open = (o["open"] as? JsonPrimitive)?.booleanOrNull == true,
    )
