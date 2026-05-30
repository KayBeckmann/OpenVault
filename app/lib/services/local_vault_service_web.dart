// Web stub — LocalVaultService is only used on native platforms.
class LocalVaultService {
  static Future<List<Map<String, dynamic>>> loadVaults() async => [];
  static Future<Map<String, dynamic>> addVault({
    required String name,
    required String localPath,
    String? remoteUrl,
  }) async =>
      {};
  static Future<void> removeVault(String id) async {}
  static List<Map<String, dynamic>> buildTree(String basePath) => [];
  static String readFile(String base, String rel) => '';
  static void writeFile(String base, String rel, String content) {}
  static void deleteFile(String base, String rel) {}
  static void createFolder(String base, String rel) {}
  static List<Map<String, dynamic>> searchFiles(String base, String query) => [];
  static List<String> collectFilePaths(String base) => [];
  static Future<({bool success, String output})> cloneRepo(
          String url, String destPath, {String? sshKeyPath}) async =>
      (success: false, output: 'Not supported on web');
}
