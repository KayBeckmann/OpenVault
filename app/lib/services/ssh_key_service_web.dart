class SshKeyInfo {
  final String privateKeyPath;
  final String publicKey;
  final bool isSystemKey;
  const SshKeyInfo({required this.privateKeyPath, required this.publicKey, required this.isSystemKey});
}

class SshKeyService {
  static Future<SshKeyInfo?> findKey() async => null;
  static Future<SshKeyInfo> generateKey() async =>
      throw UnsupportedError('SSH key management not available on web');
  static Future<String> defaultVaultPath() async => '';
  static Future<String> browseRoot() async => '';
}
