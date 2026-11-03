package so.hollo

import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale

// The native chat screen. Black and white by default, following light and
// dark mode; set Hollo.theme to match the host app.

private const val MAX_MESSAGE = 4000

/**
 * The support chat as a composable, to place in your own navigation, a tab
 * or a sheet. It counts as open (replies are marked read) while on screen.
 */
@Composable
fun HolloChat(modifier: Modifier = Modifier) {
    HolloChatScreen(theme = Hollo.theme, onClose = null, modifier = modifier.imePadding())
}

@Composable
internal fun HolloChatScreen(theme: HolloTheme, onClose: (() -> Unit)?, modifier: Modifier = Modifier) {
    val store = Hollo.store
    val state by store.state.collectAsState()
    val remote = state.remoteTheme
    val colors = resolveColors(theme, isDark(theme, isSystemInDarkTheme(), remote), remote)
    val font = theme.fontFamily
    val context = LocalContext.current
    val language = remember { Locale.getDefault().toLanguageTag() }

    DisposableEffect(store) {
        store.chatShown()
        onDispose { store.chatHidden() }
    }

    var draft by rememberSaveable { mutableStateOf("") }
    val listState = rememberLazyListState()
    val count = state.messages.size + state.pending.size
    // The footer (push card or notify line) is the item after the messages.
    LaunchedEffect(count, state.askPush) {
        if (count > 0) listState.animateScrollToItem(count)
    }

    Column(modifier = modifier.fillMaxSize().background(colors.background)) {
        Header(
            profile = state.profile,
            title = remote.title ?: theme.title,
            theme = theme,
            colors = colors,
            onClose = onClose,
        )

        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (count == 0) {
                Welcome(profile = state.profile, theme = theme, colors = colors)
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.messages, key = { it.id }) { message ->
                        if (isCard(message.kind)) {
                            CardView(
                                message = message,
                                language = language,
                                colors = colors,
                                font = font,
                                onTap = { tapCard(context, message) },
                            )
                        } else {
                            Bubble(
                                text = message.body,
                                mine = message.sender == Sender.END_USER,
                                label = labelFor(message, state.profile),
                                note = null,
                                colors = colors,
                                font = font,
                            )
                        }
                    }
                    items(state.pending, key = { "pending:" + it.localId }) { pending ->
                        Bubble(
                            text = pending.body,
                            mine = true,
                            label = null,
                            note = if (state.offline) "Waiting for connection" else "Sending…",
                            colors = colors,
                            font = font,
                        )
                    }
                    item(key = "footer") {
                        PushFooter(state = state, colors = colors, font = font)
                    }
                }
            }
        }

        if (state.error != null) {
            BasicText(
                text = if (state.offline) {
                    "You're offline. Messages send when you're back."
                } else {
                    "Couldn't reach support. Retrying…"
                },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                style = TextStyle(color = colors.muted, fontSize = 12.sp, textAlign = TextAlign.Center, fontFamily = font),
            )
        }

        Composer(
            draft = draft,
            onDraft = { draft = it },
            onSend = {
                val text = draft
                draft = ""
                // Refused by the server (not just offline): give the text back.
                store.send(text) { rejected -> if (draft.isEmpty()) draft = rejected }
            },
            colors = colors,
            font = font,
        )

        if (state.branding) {
            BrandingFooter(colors = colors, font = font)
        }
    }
}

private fun labelFor(message: HolloMessage, profile: HolloProfile): String? = when (message.sender) {
    Sender.AI -> "AI"
    Sender.TEAM -> profile.name
    else -> null
}

private fun tapCard(context: Context, message: HolloMessage) {
    when (message.kind) {
        KIND_REVIEW -> Hollo.tapReview(context, message.payload)
        KIND_LINK -> Hollo.tapLink(context, message)
        else -> Hollo.tapOffer(offerFrom(message))
    }
}

@Composable
private fun Header(
    profile: HolloProfile,
    title: String?,
    theme: HolloTheme,
    colors: ResolvedColors,
    onClose: (() -> Unit)?,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 16.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Avatar(photo = profile.photo, colors = colors, size = 36.dp)
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                BasicText(
                    text = profile.name ?: title ?: "Support",
                    style = TextStyle(
                        color = colors.text,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = theme.fontFamily,
                    ),
                )
                BasicText(
                    text = profile.role ?: "We usually reply in a few minutes",
                    style = TextStyle(color = colors.muted, fontSize = 12.sp, fontFamily = theme.fontFamily),
                )
            }
            if (onClose != null) {
                BasicText(
                    text = "Done",
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable(onClickLabel = "Close support chat", role = Role.Button, onClick = onClose)
                        .padding(8.dp),
                    style = TextStyle(
                        color = colors.text,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = theme.fontFamily,
                    ),
                )
            }
        }
        Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(colors.border))
    }
}

/** The owner's photo when they've added one, otherwise the Hollo dot. */
@Composable
private fun Avatar(photo: String?, colors: ResolvedColors, size: Dp) {
    val image = rememberRemoteImage(photo)
    if (image != null) {
        Image(
            bitmap = image,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(size).clip(CircleShape).background(colors.teamBubble),
        )
    } else {
        Box(
            modifier = Modifier.size(size).clip(CircleShape).background(colors.accent),
            contentAlignment = Alignment.Center,
        ) {
            Box(modifier = Modifier.size(size * 0.39f).border(size * 0.083f, colors.onAccent, CircleShape))
        }
    }
}

@Composable
private fun Welcome(profile: HolloProfile, theme: HolloTheme, colors: ResolvedColors) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (profile.photo != null) {
            Avatar(photo = profile.photo, colors = colors, size = 72.dp)
            Spacer(modifier = Modifier.height(12.dp))
        }
        BasicText(
            text = "How can we help?",
            style = TextStyle(
                color = colors.text,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                fontFamily = theme.fontFamily,
            ),
        )
        Spacer(modifier = Modifier.height(6.dp))
        BasicText(
            // The dashboard's welcome line wins: it can change without an app update.
            text = profile.welcome ?: theme.welcome ?: "Send us a message and we'll get back to you right here.",
            style = TextStyle(
                color = colors.muted,
                fontSize = 14.sp,
                textAlign = TextAlign.Center,
                fontFamily = theme.fontFamily,
            ),
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Bubble(
    text: String,
    mine: Boolean,
    label: String?,
    note: String?,
    colors: ResolvedColors,
    font: FontFamily?,
) {
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val shape = RoundedCornerShape(
        topStart = 18.dp,
        topEnd = 18.dp,
        bottomEnd = if (mine) 6.dp else 18.dp,
        bottomStart = if (mine) 18.dp else 6.dp,
    )
    val background = if (mine) colors.userBubble else colors.teamBubble
    val foreground = if (mine) colors.onUserBubble else colors.onTeamBubble
    val alignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart
    val linked = remember(text) { linkify(text) { url -> Hollo.openUrl(context, url) } }

    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = alignment) {
        Box(modifier = Modifier.fillMaxWidth(0.8f), contentAlignment = alignment) {
            Column(horizontalAlignment = if (mine) Alignment.End else Alignment.Start) {
                Column(
                    modifier = Modifier
                        .alpha(if (note != null) 0.6f else 1f)
                        .clip(shape)
                        .background(background)
                        // A long press copies the message.
                        .combinedClickable(
                            onLongClickLabel = "Copy message",
                            onLongClick = { clipboard.setText(AnnotatedString(text)) },
                            onClick = {},
                        )
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                ) {
                    if (label != null) {
                        BasicText(
                            text = label,
                            style = TextStyle(color = colors.muted, fontSize = 11.sp, fontFamily = font),
                        )
                    }
                    BasicText(
                        text = linked,
                        style = TextStyle(color = foreground, fontSize = 15.sp, lineHeight = 21.sp, fontFamily = font),
                    )
                }
                if (note != null) {
                    BasicText(
                        text = note,
                        modifier = Modifier.padding(top = 2.dp),
                        style = TextStyle(color = colors.muted, fontSize = 11.sp, fontFamily = font),
                    )
                }
            }
        }
    }
}

private val URL_PATTERN = Regex("""https?://[^\s<>"]+""")

/** Web links in a message, tappable and underlined. */
private fun linkify(text: String, open: (String) -> Unit): AnnotatedString = buildAnnotatedString {
    var last = 0
    for (match in URL_PATTERN.findAll(text)) {
        val url = match.value.trimEnd('.', ',', ')', '!', '?', ';', ':')
        val start = match.range.first
        append(text.substring(last, start))
        val link = LinkAnnotation.Url(
            url = url,
            styles = TextLinkStyles(style = SpanStyle(textDecoration = TextDecoration.Underline)),
            linkInteractionListener = { open(url) },
        )
        withLink(link) { append(url) }
        last = start + url.length
    }
    append(text.substring(last))
}

/** A review request, offer or link the team sent, with one button. */
@Composable
private fun CardView(
    message: HolloMessage,
    language: String,
    colors: ResolvedColors,
    font: FontFamily?,
    onTap: () -> Unit,
) {
    val content = cardContent(message, language) ?: return
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, colors.border, RoundedCornerShape(18.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (content.title.isNotEmpty()) {
            BasicText(
                text = content.title,
                style = TextStyle(color = colors.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, fontFamily = font),
            )
        }
        if (content.text.isNotEmpty()) {
            BasicText(
                text = content.text,
                style = TextStyle(color = colors.muted, fontSize = 14.sp, lineHeight = 20.sp, fontFamily = font),
            )
        }
        Pill(
            label = content.cta,
            filled = true,
            colors = colors,
            font = font,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            onClick = onTap,
        )
    }
}

/**
 * Under the user's latest message: the card asking to turn on notifications
 * (F-40), or a line saying they'll be notified of the reply (F-16).
 */
@Composable
private fun PushFooter(state: HolloState, colors: ResolvedColors, font: FontFamily?) {
    val waiting = state.pending.isNotEmpty() || state.messages.lastOrNull()?.sender == Sender.END_USER
    if (state.askPush) {
        val context = LocalContext.current
        val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            Hollo.store.answerPushCard(granted)
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .border(1.dp, colors.border, RoundedCornerShape(18.dp))
                .padding(16.dp),
        ) {
            BasicText(
                text = if (state.push.permissionCard == "replies_offers") {
                    "Turn on notifications to hear about replies and offers?"
                } else {
                    "Turn on notifications so you know when we reply?"
                },
                style = TextStyle(color = colors.text, fontSize = 14.sp, lineHeight = 20.sp, fontFamily = font),
            )
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Pill(
                    label = "No thanks",
                    filled = false,
                    colors = colors,
                    font = font,
                    modifier = Modifier.weight(1f),
                    onClick = { Hollo.store.answerPushCard(false) },
                )
                Pill(
                    label = "Continue",
                    filled = true,
                    colors = colors,
                    font = font,
                    modifier = Modifier.weight(1f),
                    onClick = {
                        // Continue shows the system prompt (F-40); Hollo never asks on its own.
                        if (Hollo.needsNotificationPrompt(context)) {
                            launcher.launch(Hollo.NOTIFICATION_PERMISSION)
                        } else {
                            Hollo.store.answerPushCard(true)
                        }
                    },
                )
            }
        }
    } else if (waiting && state.pushRegistered && state.push.notifyLine) {
        BasicText(
            text = "We'll send you a notification when we reply.",
            modifier = Modifier.fillMaxWidth(),
            style = TextStyle(color = colors.muted, fontSize = 12.sp, textAlign = TextAlign.End, fontFamily = font),
        )
    }
}

@Composable
private fun Pill(
    label: String,
    filled: Boolean,
    colors: ResolvedColors,
    font: FontFamily?,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(20.dp)
    val surface = if (filled) Modifier.background(colors.accent, shape) else Modifier.border(1.dp, colors.border, shape)
    Box(
        modifier = modifier
            .height(40.dp)
            .clip(shape)
            .then(surface)
            .clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text = label,
            style = TextStyle(
                color = if (filled) colors.onAccent else colors.text,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = font,
            ),
        )
    }
}

@Composable
private fun Composer(
    draft: String,
    onDraft: (String) -> Unit,
    onSend: () -> Unit,
    colors: ResolvedColors,
    font: FontFamily?,
) {
    val canSend = draft.isNotBlank()
    Row(
        modifier = Modifier.fillMaxWidth().padding(12.dp),
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        BasicTextField(
            value = draft,
            onValueChange = { if (it.length <= MAX_MESSAGE) onDraft(it) },
            modifier = Modifier
                .weight(1f)
                .heightIn(min = 40.dp, max = 120.dp)
                .border(1.dp, colors.border, RoundedCornerShape(20.dp))
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .semantics { contentDescription = "Message" },
            textStyle = TextStyle(color = colors.text, fontSize = 15.sp, fontFamily = font),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            cursorBrush = SolidColor(colors.text),
            decorationBox = { inner ->
                Box {
                    if (draft.isEmpty()) {
                        BasicText(
                            text = "Message",
                            style = TextStyle(color = colors.muted, fontSize = 15.sp, fontFamily = font),
                        )
                    }
                    inner()
                }
            },
        )
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(colors.accent.copy(alpha = if (canSend) 1f else 0.35f))
                .clickable(enabled = canSend, onClickLabel = "Send message", role = Role.Button, onClick = onSend)
                .semantics { contentDescription = "Send message" },
            contentAlignment = Alignment.Center,
        ) {
            BasicText(text = "↑", style = TextStyle(color = colors.onAccent, fontSize = 17.sp))
        }
    }
}

private const val BRANDING_URL = "https://hollo.so/?ref=chat"

/** "Runs on Hollo" under the composer, unless the server turns it off. */
@Composable
private fun BrandingFooter(colors: ResolvedColors, font: FontFamily?) {
    val context = LocalContext.current
    Box(modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp), contentAlignment = Alignment.Center) {
        // The text doubles as the accessibility label, since clickable merges it.
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .clickable(role = Role.Button) { Hollo.openUrl(context, BRANDING_URL) }
                .padding(horizontal = 8.dp, vertical = 3.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HolloMark(colors = colors, size = 12.dp)
            Spacer(modifier = Modifier.width(5.dp))
            BasicText(
                text = "Runs on Hollo",
                style = TextStyle(color = colors.muted, fontSize = 11.sp, fontWeight = FontWeight.Medium, fontFamily = font),
            )
        }
    }
}

/**
 * The Hollo mark from brand/hollo-mark.svg (48 × 48): a speech bubble with a
 * bubble-shaped hole and a dot, drawn even-odd so the hole stays open.
 */
@Composable
private fun HolloMark(colors: ResolvedColors, size: Dp) {
    Canvas(modifier = Modifier.size(size)) {
        val s = this.size.minDimension / 48f
        val path = Path().apply {
            fillType = PathFillType.EvenOdd
            // A disc around (24, 24) whose bottom-left quarter is square.
            for (r in floatArrayOf(24f, 13f)) {
                val lo = (24f - r) * s
                val hi = (24f + r) * s
                moveTo(lo, 24f * s)
                arcTo(Rect(lo, lo, hi, hi), 180f, 270f, false)
                lineTo(lo, hi)
                close()
            }
            addOval(Rect(18.5f * s, 18.5f * s, 29.5f * s, 29.5f * s))
        }
        drawPath(path, colors.muted)
    }
}
