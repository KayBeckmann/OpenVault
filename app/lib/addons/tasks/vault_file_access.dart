import '../../services/api_client.dart';
import '../../services/local_vault_service.dart';

/// Abstraction over vault file access so the Tasks index works on both the
/// web (backend API) and native (local filesystem) targets.
abstract class VaultFileAccess {
  /// Vault-relative paths of `.md` files whose content contains [needle].
  /// Used to limit full reads to files that actually carry tasks.
  Future<List<String>> pathsContaining(String needle);

  /// Reads a vault file's raw content.
  Future<String> read(String path);
}

/// Web implementation backed by the backend REST API.
class WebVaultFileAccess implements VaultFileAccess {
  WebVaultFileAccess(this.vaultId);
  final String vaultId;

  @override
  Future<List<String>> pathsContaining(String needle) async {
    final results = await ApiClient()
        .getList('/api/files/$vaultId/search?q=${Uri.encodeQueryComponent(needle)}');
    return results
        .map((e) => (e['path'] as String?) ?? '')
        .where((p) => p.endsWith('.md'))
        .toList();
  }

  @override
  Future<String> read(String path) => ApiClient()
      .getRaw('/api/files/$vaultId/file?path=${Uri.encodeQueryComponent(path)}');
}

/// Native implementation backed by the local vault directory.
class NativeVaultFileAccess implements VaultFileAccess {
  NativeVaultFileAccess(this.basePath);
  final String basePath;

  @override
  Future<List<String>> pathsContaining(String needle) async {
    return LocalVaultService.searchFiles(basePath, needle)
        .map((e) => (e['path'] as String?) ?? '')
        .where((p) => p.endsWith('.md'))
        .toList();
  }

  @override
  Future<String> read(String path) async =>
      LocalVaultService.readFile(basePath, path);
}
