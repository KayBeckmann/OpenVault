plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.kaybeckmann.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.kaybeckmann.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/DEPENDENCIES",
                "META-INF/MANIFEST.MF",
                "about.html",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
            )
            pickFirsts += setOf(
                "plugin.properties",
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
            )
        }
    }
}

dependencies {
    implementation("org.eclipse.jgit:org.eclipse.jgit:6.7.0.202309050840-r")
    // Use JSch-based SSH transport instead of Apache MINA SSHD.
    // The mwiede JSch fork has its own Ed25519 implementation and does not rely on
    // JCA provider discovery, which is unreliable on Android < API 33.
    implementation("org.eclipse.jgit:org.eclipse.jgit.ssh.jsch:6.7.0.202309050840-r") {
        // Exclude the unmaintained original JSch; use the mwiede fork instead.
        exclude(group = "com.jcraft", module = "jsch")
    }
    implementation("com.github.mwiede:jsch:0.2.17")
    implementation("org.slf4j:slf4j-nop:2.0.9")
    // BouncyCastle needed as JCA provider for Ed25519 signing via JSch on Android < API 33.
    // KeyFactory("Ed25519") is only available in Android's JCA from API 33; BC fills the gap.
    implementation("org.bouncycastle:bcprov-jdk15on:1.70")
}

flutter {
    source = "../.."
}
