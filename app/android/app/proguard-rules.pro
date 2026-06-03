# Flutter default keep rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter Play Store deferred components (not used, safe to ignore)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# JGit + JSch — keep all classes (ServiceLoader + reflection used internally)
-keep class org.eclipse.jgit.** { *; }
-keep class com.jcraft.jsch.** { *; }
-keep class org.slf4j.** { *; }

# Suppress missing platform classes not available on Android
-dontwarn java.lang.ProcessHandle
-dontwarn java.lang.management.ManagementFactory
-dontwarn javax.management.**
-dontwarn javax.security.auth.login.CredentialException
-dontwarn javax.security.auth.login.FailedLoginException
-dontwarn org.ietf.jgss.**
-dontwarn java.rmi.**
-dontwarn javax.security.auth.callback.**
-dontwarn javax.security.auth.login.**

# JSch optional deps not needed on Android
# Unix domain socket support (junixsocket library, not present on Android)
-dontwarn org.newsclub.net.unix.**
# com.sun.jna: Windows Pageant SSH agent connector (not available on Android)
-dontwarn com.sun.jna.**
# Log4J2: JSch supports multiple loggers; we use slf4j-nop via the slf4j bridge
-dontwarn org.apache.logging.log4j.**
# BouncyCastle: required as JCA provider for Ed25519 KeyFactory/Signature on Android < API 33.
# JSch falls back to JCA for signing; without BC the Ed25519 KeyFactory is missing on older Android.
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**
