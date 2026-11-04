plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    `maven-publish`
}

android {
    namespace = "so.hollo"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            // The app that uses Hollo shrinks it; consumer-rules.pro covers that.
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }

    testOptions {
        // Plain JVM tests: android.* calls (like Log) return defaults instead
        // of throwing, so no Robolectric is needed.
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.10.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // Only the JsonElement API, so no serialization compiler plugin is needed.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    // Only for the Hollo.handle(RemoteMessage) signature: apps bring their own
    // Firebase, and apps without it never call that overload.
    compileOnly("com.google.firebase:firebase-messaging:24.0.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}

// JitPack builds the public SDK repo with publishToMavenLocal, and serves it
// as com.github.karimrashed017:hollo-sdks:<tag>.
publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "so.hollo"
            artifactId = "hollo"
            version = providers.gradleProperty("holloVersion").getOrElse("0.1.6")
            afterEvaluate { from(components["release"]) }
            pom {
                licenses {
                    license {
                        name = "MIT License"
                        url = "https://opensource.org/licenses/MIT"
                    }
                }
            }
        }
    }
}
