package so.hollo

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
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
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.util.Locale
import kotlinx.coroutines.delay

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
    var photos by rememberSaveable(saver = PickedPhotosSaver) { mutableStateOf(emptyList<Uri>()) }
    var sendingPhotos by remember { mutableStateOf(false) }
    // The message photos open full screen, and which one.
    var viewing by remember { mutableStateOf<Pair<List<String>, Int>?>(null) }
    // The system photo picker: no storage permission, and androidx backports it to old phones.
    // Older phones may fall back to a file picker with no limit, hence the take().
    val picker = rememberLauncherForActivityResult(
        remember { ActivityResultContracts.PickMultipleVisualMedia(MAX_PHOTOS) },
    ) { picked -> photos = (photos + picked).distinct().take(MAX_PHOTOS) }
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
                        val confirm = message.confirm
                        if (confirm != null) {
                            ConfirmCardView(
                                confirm = confirm,
                                busy = message.id in state.confirming,
                                error = state.confirmErrors[message.id],
                                colors = colors,
                                font = font,
                                onAnswer = { yes -> store.answerConfirmation(message.id, yes) },
                            )
                        } else if (isCard(message.kind)) {
                            CardView(
                                message = message,
                                language = language,
                                colors = colors,
                                font = font,
                                onTap = { tapCard(context, message) },
                            )
                        } else if (message.photos.isNotEmpty()) {
                            PhotoBubble(
                                message = message,
                                label = labelFor(message, state.profile),
                                colors = colors,
                                font = font,
                                onOpen = { index -> viewing = message.photos to index },
                            )
                        } else {
                            Bubble(
                                // A photo message whose links didn't come through still says what it was.
                                text = if (message.kind == KIND_IMAGE && message.body.isEmpty()) "Photo" else message.body,
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

        if (photos.isNotEmpty()) {
            PickedPhotos(
                photos = photos,
                sending = sendingPhotos,
                colors = colors,
                font = font,
                onRemove = { uri -> photos = photos - uri },
            )
        }

        Composer(
            draft = draft,
            onDraft = { draft = it },
            hasPhotos = photos.isNotEmpty(),
            canAttach = !sendingPhotos && photos.size < MAX_PHOTOS,
            sending = sendingPhotos,
            onAttach = {
                picker.launch(
                    PickVisualMediaRequest.Builder()
                        .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly)
                        .build(),
                )
            },
            onSend = {
                val text = draft
                val picked = photos
                if (picked.isEmpty()) {
                    draft = ""
                    // Refused by the server (not just offline): give the text back.
                    store.send(text) { rejected -> if (draft.isEmpty()) draft = rejected }
                } else {
                    // The draft stays on screen until the photos are in, so a failure loses nothing.
                    sendingPhotos = true
                    val app = context.applicationContext
                    store.sendPhotos(text, jpegs = { picked.map { compressPhoto(app, it) } }) { sent ->
                        sendingPhotos = false
                        if (sent) {
                            if (draft == text) draft = ""
                            photos = photos - picked.toSet()
                        }
                    }
                }
            },
            colors = colors,
            font = font,
        )

        if (state.branding) {
            BrandingFooter(colors = colors, font = font)
        }
    }

    viewing?.let { (urls, index) ->
        PhotoViewer(photos = urls, start = index, onClose = { viewing = null })
    }
}

// Picked photos survive rotation as content URIs; the picker's read grant lasts as long as the activity.
private val PickedPhotosSaver = listSaver<MutableState<List<Uri>>, String>(
    save = { state -> state.value.map { it.toString() } },
    restore = { saved -> mutableStateOf(saved.map { Uri.parse(it) }) },
)

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
    val shape = bubbleShape(mine)
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

private fun bubbleShape(mine: Boolean) = RoundedCornerShape(
    topStart = 18.dp,
    topEnd = 18.dp,
    bottomEnd = if (mine) 6.dp else 18.dp,
    bottomStart = if (mine) 18.dp else 6.dp,
)

private val PHOTO_GRID = 240.dp
private val PHOTO_GAP = 4.dp
private val PHOTO_TILE = (PHOTO_GRID - PHOTO_GAP) / 2
private const val BUBBLE_PHOTO_EDGE = 512

/** An image message: its photos in a grid, then the caption. Tapping a photo opens it full screen. */
@Composable
private fun PhotoBubble(
    message: HolloMessage,
    label: String?,
    colors: ResolvedColors,
    font: FontFamily?,
    onOpen: (Int) -> Unit,
) {
    val context = LocalContext.current
    val mine = message.sender == Sender.END_USER
    val foreground = if (mine) colors.onUserBubble else colors.onTeamBubble
    val alignment = if (mine) Alignment.CenterEnd else Alignment.CenterStart
    val caption = message.body
    val linked = remember(caption) { linkify(caption) { url -> Hollo.openUrl(context, url) } }
    val count = message.photos.size

    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = alignment) {
        Column(
            modifier = Modifier
                .width(PHOTO_GRID + PHOTO_GAP * 2)
                .clip(bubbleShape(mine))
                .background(if (mine) colors.userBubble else colors.teamBubble)
                .padding(PHOTO_GAP),
            verticalArrangement = Arrangement.spacedBy(PHOTO_GAP),
        ) {
            if (label != null) {
                BasicText(
                    text = label,
                    modifier = Modifier.padding(start = 10.dp, top = 4.dp),
                    style = TextStyle(color = colors.muted, fontSize = 11.sp, fontFamily = font),
                )
            }
            message.photos.chunked(2).forEachIndexed { row, pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(PHOTO_GAP)) {
                    pair.forEachIndexed { column, url ->
                        val index = row * 2 + column
                        // One photo, or the odd one out at the end, takes the whole width.
                        val tile = when {
                            count == 1 -> Modifier.size(PHOTO_GRID)
                            pair.size == 1 -> Modifier.width(PHOTO_GRID).height(PHOTO_TILE)
                            else -> Modifier.size(PHOTO_TILE)
                        }
                        PhotoTile(
                            url = url,
                            description = "Photo ${index + 1} of $count",
                            colors = colors,
                            modifier = tile,
                            onClick = { onOpen(index) },
                        )
                    }
                }
            }
            if (caption.isNotEmpty()) {
                BasicText(
                    text = linked,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                    style = TextStyle(color = foreground, fontSize = 15.sp, lineHeight = 21.sp, fontFamily = font),
                )
            }
        }
    }
}

@Composable
private fun PhotoTile(
    url: String,
    description: String,
    colors: ResolvedColors,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val image = rememberRemoteImage(url, maxEdge = BUBBLE_PHOTO_EDGE)
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(colors.border)
            .clickable(onClickLabel = "Open photo", role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
    ) {
        if (image != null) {
            Image(
                bitmap = image,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

private const val MAX_ZOOM = 5f
private const val DOUBLE_TAP_ZOOM = 2.5f

/** A message's photos full screen: swipe between them, pinch or double-tap to zoom. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PhotoViewer(photos: List<String>, start: Int, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val pager = rememberPagerState(initialPage = start.coerceIn(0, photos.lastIndex), pageCount = { photos.size })
        Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { page ->
                ZoomablePhoto(url = photos[page], description = "Photo ${page + 1} of ${photos.size}")
            }
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.5f))
                    .clickable(onClickLabel = "Close photo", role = Role.Button, onClick = onClose)
                    .semantics { contentDescription = "Close photo" },
                contentAlignment = Alignment.Center,
            ) {
                BasicText(text = "×", style = TextStyle(color = Color.White, fontSize = 26.sp))
            }
            if (photos.size > 1) {
                BasicText(
                    text = "${pager.currentPage + 1} / ${photos.size}",
                    modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp),
                    style = TextStyle(color = Color.White, fontSize = 13.sp),
                )
            }
        }
    }
}

@Composable
private fun ZoomablePhoto(url: String, description: String) {
    val image = rememberRemoteImage(url)
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onDoubleTap = { tap ->
                        if (scale > 1f) {
                            scale = 1f
                            offset = Offset.Zero
                        } else {
                            // Zoom in on the tapped spot, not the middle.
                            val middle = Offset(size.width / 2f, size.height / 2f)
                            scale = DOUBLE_TAP_ZOOM
                            offset = clampPan((middle - tap) * (DOUBLE_TAP_ZOOM - 1f), DOUBLE_TAP_ZOOM, size)
                        }
                    },
                )
            }
            .pointerInput(Unit) {
                // Pinch and pan by hand: one finger at normal size is left to the
                // pager, so swiping still moves between photos.
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        val pinching = event.changes.count { it.pressed } > 1
                        if (pinching || scale > 1f) {
                            val next = (scale * event.calculateZoom()).coerceIn(1f, MAX_ZOOM)
                            offset = if (next == 1f) Offset.Zero else clampPan(offset + event.calculatePan(), next, size)
                            scale = next
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                }
            }
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        if (image != null) {
            Image(
                bitmap = image,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = scale
                        scaleY = scale
                        translationX = offset.x
                        translationY = offset.y
                    },
            )
        }
    }
}

/** Keeps a zoomed photo from being dragged off screen. */
private fun clampPan(offset: Offset, scale: Float, size: IntSize): Offset {
    val maxX = size.width * (scale - 1f) / 2f
    val maxY = size.height * (scale - 1f) / 2f
    return Offset(offset.x.coerceIn(-maxX, maxX), offset.y.coerceIn(-maxY, maxY))
}

/** The photos picked for the next message, above the composer, each with a remove button. */
@Composable
private fun PickedPhotos(
    photos: List<Uri>,
    sending: Boolean,
    colors: ResolvedColors,
    font: FontFamily?,
    onRemove: (Uri) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .alpha(if (sending) 0.6f else 1f)
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            photos.forEachIndexed { index, uri ->
                key(uri) {
                    val image = rememberPickedPhoto(uri)
                    Box(modifier = Modifier.size(64.dp)) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .clip(RoundedCornerShape(12.dp))
                                .background(colors.border)
                                .semantics { contentDescription = "Photo ${index + 1} of ${photos.size}" },
                        ) {
                            if (image != null) {
                                Image(
                                    bitmap = image,
                                    contentDescription = null,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                        }
                        if (!sending) {
                            // A bigger touch target than the dot it shows.
                            Box(
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .size(32.dp)
                                    .clickable(onClickLabel = "Remove photo", role = Role.Button) { onRemove(uri) }
                                    .semantics { contentDescription = "Remove photo ${index + 1}" },
                                contentAlignment = Alignment.Center,
                            ) {
                                Box(
                                    modifier = Modifier.size(20.dp).clip(CircleShape).background(colors.accent),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    BasicText(text = "×", style = TextStyle(color = colors.onAccent, fontSize = 13.sp))
                                }
                            }
                        }
                    }
                }
            }
        }
        if (sending) {
            BasicText(
                text = "Sending…",
                modifier = Modifier.padding(top = 4.dp),
                style = TextStyle(color = colors.muted, fontSize = 11.sp, fontFamily = font),
            )
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
 * An action the AI wants to run, with Confirm and Cancel (F-42). Once
 * answered, expired or gone, the buttons give way to a line saying so.
 */
@Composable
private fun ConfirmCardView(
    confirm: ActionConfirm,
    busy: Boolean,
    error: String?,
    colors: ResolvedColors,
    font: FontFamily?,
    onAnswer: (confirm: Boolean) -> Unit,
) {
    // Ticks once at the expiry time, so a card left open on screen turns to "Expired".
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val expires = remember(confirm.expiresAt) { confirm.expiresAt?.let { parseIsoMillis(it) } }
    LaunchedEffect(expires) {
        if (expires != null && expires > now) {
            delay(expires - now + 500)
            now = System.currentTimeMillis()
        }
    }
    val stateNow = confirmState(confirm, now)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, colors.border, RoundedCornerShape(18.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (confirm.title.isNotEmpty()) {
            BasicText(
                text = confirm.title,
                style = TextStyle(color = colors.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, fontFamily = font),
            )
        }
        if (confirm.summary.isNotEmpty()) {
            BasicText(
                text = confirm.summary,
                style = TextStyle(color = colors.muted, fontSize = 14.sp, lineHeight = 20.sp, fontFamily = font),
            )
        }
        for (line in confirmLines(confirm)) {
            BasicText(
                text = line,
                style = TextStyle(color = colors.text, fontSize = 14.sp, lineHeight = 20.sp, fontFamily = font),
            )
        }
        if (stateNow == ConfirmState.PENDING) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Pill(
                    label = "Cancel",
                    filled = false,
                    colors = colors,
                    font = font,
                    modifier = Modifier.weight(1f),
                    enabled = !busy,
                    onClick = { onAnswer(false) },
                )
                Pill(
                    label = "Confirm",
                    filled = true,
                    colors = colors,
                    font = font,
                    modifier = Modifier.weight(1f),
                    enabled = !busy,
                    onClick = { onAnswer(true) },
                )
            }
            if (error != null) {
                BasicText(
                    text = error,
                    modifier = Modifier.fillMaxWidth(),
                    style = TextStyle(color = colors.muted, fontSize = 12.sp, textAlign = TextAlign.Center, fontFamily = font),
                )
            }
        } else {
            BasicText(
                text = stateNow.label,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                style = TextStyle(
                    color = colors.muted,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    fontFamily = font,
                ),
            )
        }
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
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(20.dp)
    val surface = if (filled) Modifier.background(colors.accent, shape) else Modifier.border(1.dp, colors.border, shape)
    Box(
        modifier = modifier
            .height(40.dp)
            // Dimmed while off, like the send button.
            .alpha(if (enabled) 1f else 0.35f)
            .clip(shape)
            .then(surface)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
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
    hasPhotos: Boolean,
    canAttach: Boolean,
    sending: Boolean,
    onAttach: () -> Unit,
    onSend: () -> Unit,
    colors: ResolvedColors,
    font: FontFamily?,
) {
    // With photos the text is an optional caption.
    val canSend = !sending && (draft.isNotBlank() || hasPhotos)
    Row(
        modifier = Modifier.fillMaxWidth().padding(12.dp),
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .border(1.dp, colors.border, CircleShape)
                .clickable(enabled = canAttach, onClickLabel = "Attach photos", role = Role.Button, onClick = onAttach)
                .semantics { contentDescription = "Attach photos" },
            contentAlignment = Alignment.Center,
        ) {
            BasicText(
                text = "+",
                style = TextStyle(color = colors.text.copy(alpha = if (canAttach) 1f else 0.35f), fontSize = 22.sp),
            )
        }
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
                            text = if (hasPhotos) "Add a caption" else "Message",
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
