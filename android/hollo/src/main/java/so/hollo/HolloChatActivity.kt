package so.hollo

import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.ui.Modifier

/**
 * The chat as its own screen, for Hollo.present() and View-based apps. It's
 * declared in Hollo's manifest, so apps don't add anything.
 */
class HolloChatActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val systemDark =
            (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        // Status bar icons follow the chat's look, which the theme or the
        // dashboard may force.
        val style = if (isDark(Hollo.theme, systemDark, Hollo.store.state.value.remoteTheme)) {
            SystemBarStyle.dark(Color.TRANSPARENT)
        } else {
            SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
        }
        enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
        super.onCreate(savedInstanceState)
        Hollo.chatCreated(this)
        setContent {
            HolloChatScreen(
                theme = Hollo.theme,
                onClose = { finish() },
                modifier = Modifier.safeDrawingPadding(),
            )
        }
    }

    override fun onDestroy() {
        Hollo.chatDestroyed(this)
        super.onDestroy()
    }
}
