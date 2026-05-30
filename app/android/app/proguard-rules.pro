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

# JGit / Apache SSHD — keep all classes (uses ServiceLoader for dynamic discovery)
# Without this, R8 strips SSH key loaders and authentication providers,
# causing NoClassDefFoundError at runtime which hangs the MethodChannel.
-keep class org.eclipse.jgit.** { *; }
-keep class org.apache.sshd.** { *; }
-keep class org.slf4j.** { *; }

# JGit / Apache SSHD — suppress missing classes not available on Android
-dontwarn java.lang.ProcessHandle
-dontwarn java.lang.management.ManagementFactory
-dontwarn javax.management.**
-dontwarn javax.security.auth.login.CredentialException
-dontwarn javax.security.auth.login.FailedLoginException
-dontwarn org.bouncycastle.asn1.pkcs.PrivateKeyInfo
-dontwarn org.bouncycastle.crypto.prng.RandomGenerator
-dontwarn org.bouncycastle.crypto.prng.VMPCRandomGenerator
-dontwarn org.bouncycastle.operator.InputDecryptorProvider
-dontwarn org.bouncycastle.pkcs.**
-dontwarn org.bouncycastle.openssl.**
-dontwarn org.ietf.jgss.**
-dontwarn java.rmi.**
-dontwarn javax.security.auth.callback.**
-dontwarn javax.security.auth.login.**
-dontwarn org.apache.tomcat.jni.**
