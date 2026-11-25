import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val releaseKeystoreProps = Properties()
val userKeystorePropsFile = file("${System.getProperty("user.home")}/.presentersync/keystore.properties")
val localKeystorePropsFile = rootProject.file("keystore.properties")
val activePropsFile = when {
    localKeystorePropsFile.exists() -> {
        localKeystorePropsFile.inputStream().use { releaseKeystoreProps.load(it) }
        localKeystorePropsFile
    }
    userKeystorePropsFile.exists() -> {
        userKeystorePropsFile.inputStream().use { releaseKeystoreProps.load(it) }
        userKeystorePropsFile
    }
    else -> null
}

fun resolveKeystoreCandidate(pathStr: String?): File? {
    val cleaned = pathStr?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    val direct = file(cleaned)
    if (direct.exists()) return direct
    activePropsFile?.parentFile?.resolve(cleaned)?.takeIf { it.exists() }?.let { return it }
    rootProject.file(cleaned).takeIf { it.exists() }?.let { return it }
    return null
}

val resolvedKeystoreFile = resolveKeystoreCandidate(System.getenv("KEYSTORE_FILE"))
    ?: resolveKeystoreCandidate(releaseKeystoreProps.getProperty("storeFile"))
val hasReleaseSigning = resolvedKeystoreFile != null
val requireReleaseSigning = (findProperty("requireReleaseSigning")?.toString()?.toBoolean() == true)
if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException(
        "Release signing keystore required (-PrequireReleaseSigning=true), but no keystore.properties or KEYSTORE_FILE was found."
    )
}

android {
    namespace = "com.saabithjiffry.presentersync.remote"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.saabithjiffry.presentersync.remote"
        minSdk = 26
        targetSdk = 34
        versionCode = 90600
        versionName = "9.6.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = resolvedKeystoreFile!!
                storePassword = (System.getenv("KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
                    ?: releaseKeystoreProps.getProperty("storePassword")?.trim())
                keyAlias = (System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() }
                    ?: releaseKeystoreProps.getProperty("keyAlias")?.trim())
                keyPassword = (System.getenv("KEY_PASSWORD")?.takeIf { it.isNotBlank() }
                    ?: releaseKeystoreProps.getProperty("keyPassword")?.trim())
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        debug {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.10"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.interpolator:interpolator:1.0.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.7.0")
    implementation("androidx.lifecycle:lifecycle-service:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")

    implementation(platform("androidx.compose:compose-bom:2024.02.02"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Zero-GMS CameraX + ZXing Core for offline Smart Board QR pairing
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")
    implementation("androidx.camera:camera-view:1.3.4")
    implementation("com.google.zxing:core:3.5.3")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.json:json:20240303")

    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test:core-ktx:1.5.0")
    androidTestImplementation("androidx.test:runner:1.5.2")
    androidTestImplementation("androidx.test:rules:1.5.0")
    androidTestImplementation(platform("androidx.compose:compose-bom:2024.02.02"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
