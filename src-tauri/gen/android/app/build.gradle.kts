import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("rust")
}

val tauriProperties = Properties().apply {
    val propFile = file("tauri.properties")
    if (propFile.exists()) {
        propFile.inputStream().use { load(it) }
    }
}

// The Android port's version (src-tauri/android-port.properties): the upstream version Tauri hands
// over in tauri.properties, plus the port's revision. versionName is the release's name,
// 1.4.0-rc.3-universal-android.2. versionCode packs the same numbers so every later release is
// higher: major, minor and patch (two digits each), the release candidate (01-98, 99 for the
// final release, which comes after its candidates), then the revision (two digits).
// 1.4.0-rc.3 revision 2 is 104000302. Tauri's own code ignores the release candidate, so 1.4.0
// would have come out lower than 1.4.0-rc.3 revision 5, and Android refuses that as a downgrade.
val portRevision = Properties().apply {
    rootProject.file("../../android-port.properties").inputStream().use { load(it) }
}.getProperty("revision").trim().toInt()
val upstreamVersion = tauriProperties.getProperty("tauri.android.versionName", "0.0.0")
val portVersionCode = run {
    val m = Regex("^(\\d+)\\.(\\d+)\\.(\\d+)(?:-rc\\.(\\d+))?$").matchEntire(upstreamVersion)
        ?: error("upstream version $upstreamVersion is not X.Y.Z or X.Y.Z-rc.N")
    val (major, minor, patch) = (1..3).map { m.groupValues[it].toInt() }
    val rc = m.groupValues[4].ifEmpty { "99" }.toInt()
    require(minor < 100 && patch < 100 && rc in 1..99 && portRevision in 1..99) {
        "version $upstreamVersion revision $portRevision does not fit versionCode's digits"
    }
    (((major * 100 + minor) * 100 + patch) * 100 + rc) * 100 + portRevision
}

// Release signing, never committed: `src-tauri/gen/android/keystore.properties` (gitignored) with
// storeFile, storePassword, keyAlias and keyPassword, or the LIMUSIC_ANDROID_* environment variables
// of the same names for CI. Without either, the release APK is built unsigned (sign it with
// apksigner afterwards); debug builds always use the SDK's debug key.
val keystoreProperties = Properties().apply {
    val propFile = rootProject.file("keystore.properties")
    if (propFile.exists()) {
        propFile.inputStream().use { load(it) }
    }
}
fun signingValue(key: String): String? =
    keystoreProperties.getProperty(key)
        ?: System.getenv("LIMUSIC_ANDROID_" + key.replace(Regex("([a-z])([A-Z])"), "$1_$2").uppercase())

android {
    compileSdk = 37
    namespace = "com.limusic.android"
    defaultConfig {
        manifestPlaceholders["usesCleartextTraffic"] = "false"
        manifestPlaceholders["networkSecurityConfig"] = "@xml/network_security_config"
        applicationId = "com.limusic.android"
        minSdk = 26
        targetSdk = 37
        versionCode = portVersionCode
        versionName = "$upstreamVersion-universal-android.$portRevision"
    }
    val releaseStore = signingValue("storeFile")
    if (releaseStore != null) {
        signingConfigs {
            create("release") {
                storeFile = rootProject.file(releaseStore)
                storePassword = signingValue("storePassword")
                keyAlias = signingValue("keyAlias")
                keyPassword = signingValue("keyPassword")
                // v3 on top of v2, from the first release on: it is what lets the key be rotated
                // later without breaking updates, and installed copies only honour a rotation if
                // they were signed with v3 to begin with.
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }
    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["usesCleartextTraffic"] = "true"
            manifestPlaceholders["networkSecurityConfig"] = "@xml/network_security_config_debug"
            isDebuggable = true
            isJniDebuggable = true
            isMinifyEnabled = false
            packaging {
                jniLibs.keepDebugSymbols.add("*/arm64-v8a/*.so")
                jniLibs.keepDebugSymbols.add("*/armeabi-v7a/*.so")
                jniLibs.keepDebugSymbols.add("*/x86/*.so")
                jniLibs.keepDebugSymbols.add("*/x86_64/*.so")
            }
        }
        getByName("release") {
            if (releaseStore != null) {
                signingConfig = signingConfigs.getByName("release")
            }
            optimization {
               enable = true
            }
            proguardFiles(
                *fileTree(".") {
                  include("**/*.pro")
                  exclude("build/**")
                }.files.toTypedArray()
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    buildFeatures {
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_1_8
    }
}

rust {
    rootDirRel = "../../../"
}

dependencies {
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")
    // The media session (PlaybackService). Playback itself is libmpv's, from Rust; Media3 provides
    // the session, notification, foreground-service handling and controller plumbing.
    implementation("androidx.media3:media3-session:1.11.1")
    implementation("androidx.media3:media3-common:1.11.1")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.4")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.0")
}

apply(from = file("tauri.build.gradle.kts"))
