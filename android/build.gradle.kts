// Versions are pinned together: AGP 8.7 needs Gradle 8.9+, and the Compose
// compiler plugin must match the Kotlin version exactly.
plugins {
    id("com.android.library") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
