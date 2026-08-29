import java.util.Properties
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "io.confinia.overwatch"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.confinia.overwatch"
        // Android 8+, same intention as iOS 16: a ham's phone is often not a
        // new phone.
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }
    // Play upload signing. The keystore and its password live OUTSIDE the
    // repo (~/.android-keys/, chmod 600) and are referenced via
    // local.properties — losing that keystore means losing the ability to
    // update the app, so it is backed up like a production secret, never
    // committed like one.
    val localProps = Properties()
    rootProject.file("local.properties").takeIf { it.exists() }
        ?.inputStream()?.use { localProps.load(it) }
    val uploadKs: String? = localProps.getProperty("uploadKeystore")
    signingConfigs {
        create("upload") {
            if (uploadKs != null) {
                storeFile = file(uploadKs)
                storePassword = localProps.getProperty("uploadPassword")
                keyAlias = "overwatch"
                keyPassword = localProps.getProperty("uploadPassword")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (uploadKs != null) signingConfigs.getByName("upload")
                            else signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
}
