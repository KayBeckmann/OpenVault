package de.kaybeckmann.app

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.api.TransportConfigCallback
import org.eclipse.jgit.api.errors.GitAPIException
import org.eclipse.jgit.transport.CredentialsProvider
import org.eclipse.jgit.transport.RemoteRefUpdate
import org.eclipse.jgit.transport.SshTransport
import org.eclipse.jgit.transport.sshd.ServerKeyDatabase
import org.eclipse.jgit.transport.sshd.SshdSessionFactoryBuilder
import java.io.File
import java.net.InetSocketAddress
import java.security.PublicKey
import java.security.Security
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val CHANNEL = "de.kaybeckmann.app/git"
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Replace Android's stripped-down BC with the full BouncyCastle so that
        // Apache MINA SSHD can load Ed25519 OpenSSH keys on Android < API 33.
        Security.removeProvider("BC")
        Security.insertProviderAt(BouncyCastleProvider(), 1)
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                when (call.method) {
                    "clone" -> {
                        val url = args["url"] as? String
                            ?: return@setMethodCallHandler result.error("ARG", "url missing", null)
                        val destPath = args["destPath"] as? String
                            ?: return@setMethodCallHandler result.error("ARG", "destPath missing", null)
                        val sshKeyPath = args["sshKeyPath"] as? String
                        doAsync(result) { gitClone(url, destPath, sshKeyPath) }
                    }
                    "pull" -> {
                        val repoPath = args["repoPath"] as? String
                            ?: return@setMethodCallHandler result.error("ARG", "repoPath missing", null)
                        val sshKeyPath = args["sshKeyPath"] as? String
                        doAsync(result) { gitPull(repoPath, sshKeyPath) }
                    }
                    "commitAndPush" -> {
                        val repoPath = args["repoPath"] as? String
                            ?: return@setMethodCallHandler result.error("ARG", "repoPath missing", null)
                        val message = args["message"] as? String ?: "Auto-commit"
                        val sshKeyPath = args["sshKeyPath"] as? String
                        doAsync(result) { gitCommitAndPush(repoPath, message, sshKeyPath) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun doAsync(result: MethodChannel.Result, block: () -> Map<String, Any>) {
        executor.submit {
            try {
                val out = block()
                mainHandler.post { result.success(out) }
            } catch (t: Throwable) {
                // Catch Throwable (not just Exception) to also handle NoClassDefFoundError
                // and other JVM errors that can occur if R8 strips dynamically loaded classes.
                mainHandler.post { result.error("GIT_ERROR", t.message ?: t.javaClass.simpleName, null) }
            }
        }
    }

    private fun buildTransportCallback(sshKeyPath: String?): TransportConfigCallback? {
        if (sshKeyPath == null) return null
        val keyFile = File(sshKeyPath)
        if (!keyFile.exists()) return null

        val sshDir = File(filesDir, ".ssh").also { it.mkdirs() }

        val factory = SshdSessionFactoryBuilder()
            .setServerKeyDatabase { _, _ ->
                object : ServerKeyDatabase {
                    override fun lookup(
                        connectAddress: String,
                        remoteAddress: InetSocketAddress,
                        config: ServerKeyDatabase.Configuration,
                    ): List<PublicKey> = emptyList()

                    override fun accept(
                        connectAddress: String,
                        remoteAddress: InetSocketAddress,
                        serverKey: PublicKey,
                        config: ServerKeyDatabase.Configuration,
                        provider: CredentialsProvider,
                    ): Boolean = true
                }
            }
            .setDefaultIdentities { _ -> listOf(keyFile.toPath()) }
            .setHomeDirectory(filesDir)
            .setSshDirectory(sshDir)
            .build(null)

        return TransportConfigCallback { transport ->
            if (transport is SshTransport) {
                transport.sshSessionFactory = factory
            }
        }
    }

    private fun gitClone(url: String, destPath: String, sshKeyPath: String?): Map<String, Any> {
        val dest = File(destPath).also { it.mkdirs() }
        return try {
            val cmd = Git.cloneRepository()
                .setURI(url)
                .setDirectory(dest)
                .setTimeout(30)
            buildTransportCallback(sshKeyPath)?.let { cb -> cmd.setTransportConfigCallback(cb) }
            cmd.call().close()
            mapOf("success" to true, "output" to "Clone erfolgreich nach $destPath")
        } catch (e: GitAPIException) {
            mapOf("success" to false, "output" to (e.message ?: "Clone fehlgeschlagen"))
        }
    }

    private fun gitPull(repoPath: String, sshKeyPath: String?): Map<String, Any> {
        return try {
            Git.open(File(repoPath)).use { git ->
                val cmd = git.pull().setTimeout(30)
                buildTransportCallback(sshKeyPath)?.let { cb -> cmd.setTransportConfigCallback(cb) }
                val res = cmd.call()
                mapOf(
                    "success" to res.isSuccessful,
                    "output" to if (res.isSuccessful) "Pull erfolgreich"
                                else "Pull fehlgeschlagen: ${res.mergeResult?.mergeStatus}",
                )
            }
        } catch (e: Exception) {
            mapOf("success" to false, "output" to (e.message ?: "Pull fehlgeschlagen"))
        }
    }

    private fun gitCommitAndPush(repoPath: String, message: String, sshKeyPath: String?): Map<String, Any> {
        return try {
            Git.open(File(repoPath)).use { git ->
                git.add().addFilepattern(".").call()
                if (!git.status().call().isClean) {
                    git.commit().setMessage(message).call()
                }
                val pushCmd = git.push().setTimeout(30)
                buildTransportCallback(sshKeyPath)?.let { cb -> pushCmd.setTransportConfigCallback(cb) }
                val pushOk = pushCmd.call().all { r ->
                    r.remoteUpdates.all { u ->
                        u.status == RemoteRefUpdate.Status.OK ||
                        u.status == RemoteRefUpdate.Status.UP_TO_DATE
                    }
                }
                mapOf(
                    "success" to pushOk,
                    "output" to if (pushOk) "Sync erfolgreich" else "Push fehlgeschlagen",
                )
            }
        } catch (e: Exception) {
            mapOf("success" to false, "output" to (e.message ?: "Commit/Push fehlgeschlagen"))
        }
    }
}
