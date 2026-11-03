package so.hollo

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontFamily

/**
 * Colours for one look (light or dark). Leave any of them null to use Hollo's
 * black-and-white default for that look.
 */
data class HolloColors(
    /** Buttons, the send button and the user's own bubbles. */
    val accent: Color? = null,
    val background: Color? = null,
    val text: Color? = null,
    /** Secondary text: subtitles, labels, hints. */
    val muted: Color? = null,
    /** The user's bubbles, if you want something other than [accent]. */
    val userBubble: Color? = null,
    /** Bubbles for replies from your team and the AI. */
    val teamBubble: Color? = null,
)

enum class HolloColorScheme { SYSTEM, LIGHT, DARK }

/**
 * How the chat looks. Set `Hollo.theme` before the chat opens; every field is
 * optional. Fixed colours can't adapt to dark mode, so they're given per look.
 */
data class HolloTheme(
    val light: HolloColors = HolloColors(),
    val dark: HolloColors = HolloColors(),
    /** For messages and the composer. Use a font your app already bundles. */
    val fontFamily: FontFamily? = null,
    /** The title at the top of the chat when the dashboard sets no name. */
    val title: String? = null,
    /** The welcome text when the dashboard sets none. */
    val welcome: String? = null,
    /** Force one look, or follow the system. */
    val colorScheme: HolloColorScheme = HolloColorScheme.SYSTEM,
)

internal data class ResolvedColors(
    val accent: Color,
    val onAccent: Color,
    val background: Color,
    val text: Color,
    val muted: Color,
    val userBubble: Color,
    val onUserBubble: Color,
    val teamBubble: Color,
    val onTeamBubble: Color,
    val border: Color,
)

private val INK = Color(0xFF0B0B0C)

private val LIGHT = ResolvedColors(
    accent = INK,
    onAccent = Color.White,
    background = Color.White,
    text = INK,
    muted = Color(0xFF8A8A8E),
    userBubble = INK,
    onUserBubble = Color.White,
    teamBubble = Color(0xFFF1F1F0),
    onTeamBubble = INK,
    border = Color(0xFFE5E5E3),
)

private val DARK = ResolvedColors(
    accent = Color.White,
    onAccent = INK,
    background = INK,
    text = Color(0xFFF5F5F4),
    muted = Color(0xFF8E8E93),
    userBubble = Color.White,
    onUserBubble = INK,
    teamBubble = Color(0xFF1C1C1E),
    onTeamBubble = Color(0xFFF5F5F4),
    border = Color(0xFF2C2C2E),
)

/** Text that stays readable on a custom colour. */
private fun contentOn(color: Color) = if (color.luminance() > 0.5f) INK else Color.White

/** The dashboard's forced look wins, then the app's, then the system's. */
internal fun isDark(theme: HolloTheme, systemDark: Boolean, remote: RemoteTheme = RemoteTheme()) =
    when (remote.colorScheme?.takeIf { it != HolloColorScheme.SYSTEM } ?: theme.colorScheme) {
        HolloColorScheme.SYSTEM -> systemDark
        HolloColorScheme.LIGHT -> false
        HolloColorScheme.DARK -> true
    }

internal fun resolveColors(theme: HolloTheme, dark: Boolean, remote: RemoteTheme = RemoteTheme()): ResolvedColors {
    val base = if (dark) DARK else LIGHT
    val custom = if (dark) theme.dark else theme.light
    val accent = custom.accent ?: base.accent
    val userBubble = custom.userBubble ?: custom.accent ?: base.userBubble
    val local = ResolvedColors(
        accent = accent,
        onAccent = if (custom.accent != null) contentOn(accent) else base.onAccent,
        background = custom.background ?: base.background,
        text = custom.text ?: base.text,
        muted = custom.muted ?: base.muted,
        userBubble = userBubble,
        onUserBubble = if (custom.userBubble != null || custom.accent != null) contentOn(userBubble) else base.onUserBubble,
        teamBubble = custom.teamBubble ?: base.teamBubble,
        onTeamBubble = custom.text ?: base.onTeamBubble,
        border = base.border,
    )
    // Dashboard colours go over the app's, one look at a time: a colour set
    // only for dark leaves the light look as the app has it.
    fun pick(color: RemoteColor?) = color?.pick(dark)?.let { Color(it) }
    val remoteAccent = pick(remote.accent)
    val remoteOnAccent = pick(remote.onAccent)
    // The dashboard has one accent for both, so it also wins over userBubble.
    val onRemoteAccent = remoteOnAccent ?: remoteAccent?.let { contentOn(it) }
    return local.copy(
        accent = remoteAccent ?: local.accent,
        onAccent = onRemoteAccent ?: local.onAccent,
        background = pick(remote.background) ?: local.background,
        userBubble = remoteAccent ?: local.userBubble,
        onUserBubble = onRemoteAccent ?: local.onUserBubble,
        teamBubble = pick(remote.incoming) ?: local.teamBubble,
        onTeamBubble = pick(remote.incomingText) ?: local.onTeamBubble,
    )
}
