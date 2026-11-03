# Hollo Android SDK (Kotlin)

The native Android SDK: a Kotlin library with a Jetpack Compose chat screen
(`HolloChat()`), an activity for View-based apps (`Hollo.present(context)`),
identify/sign-out/erase, link and offer cards, review requests, automations
(`Hollo.track`) and FCM push hand-off. Feature-equivalent to the React Native
SDK in `../react-native`. A small "Runs on Hollo" line sits under the
composer; the server hides it with `branding: false` in `GET /messages`.

Requirements: `minSdk 24`, Kotlin, Compose. The library adds no HTTP or image
library: it uses `HttpURLConnection`, coroutines and kotlinx-serialization-json.

## Install

From JitPack. In `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

Then in your app module:

```kotlin
implementation("com.github.karimrashed017:hollo-sdks:0.1.3")
```

Your project needs the Kotlin Compose compiler plugin (Kotlin 2.0+) and
`android.useAndroidX=true`.

## Use

```kotlin
class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Hollo.start(this, appKey = "app_XXXX")
    }
}

// Views or Compose: open the chat as its own screen.
Hollo.present(activity)

// Or put it in your own navigation.
composable("support") { HolloChat() }

Hollo.identify(id = user.id, name = user.name, email = user.email)
// Pass an identity token signed by your server to mark the user as verified.
// Hollo's AI only runs account actions for verified users.
Hollo.identify(id = user.id, email = user.email, identityToken = tokenFromYourServer)
Hollo.signOut()
lifecycleScope.launch { Hollo.eraseUserData() } // suspend, throws HolloException

Hollo.onOffer { offer -> showPaywall(offer.ref) }
Hollo.onLink { link -> navigate(link.screen, link.value) }
Hollo.track("paywall_declined")
Hollo.setSubscriber(true)

val unread by Hollo.unreadCount.collectAsStateWithLifecycle()
Hollo.theme = HolloTheme(light = HolloColors(accent = Color(0xFF0B0B0C)), title = "Help")
```

Push (FCM): Hollo doesn't depend on Firebase at runtime.

```kotlin
class MyMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) = Hollo.registerPush(token)
    override fun onMessageReceived(message: RemoteMessage) {
        if (Hollo.handle(message)) return
        // Your own notifications here.
    }
}

// In the activity a notification tap opens (onCreate and onNewIntent):
Hollo.handle(intent)
```

`Hollo.onPushPermission { FirebaseMessaging.getInstance().token.await() }`
enables the in-chat permission card (F-40) when it's on in the dashboard.

## Develop

There's no Gradle wrapper in the repo. With JDK 17, Gradle 8.10.2 and the
Android SDK installed:

```sh
./gradlew :hollo:testDebugUnitTest :hollo:assembleRelease
```

Unit tests are plain
JVM JUnit with a fake HTTP transport (`hollo/src/test`).
