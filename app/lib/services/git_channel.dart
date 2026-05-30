import 'package:flutter/services.dart';

class GitChannel {
  static const _channel = MethodChannel('de.kaybeckmann.app/git');

  static Future<({bool success, String output})> clone(
    String url,
    String destPath, {
    String? sshKeyPath,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('clone', {
      'url': url,
      'destPath': destPath,
      if (sshKeyPath != null) 'sshKeyPath': sshKeyPath,
    });
    return (
      success: result?['success'] as bool? ?? false,
      output: result?['output'] as String? ?? '',
    );
  }

  static Future<({bool success, String output})> pull(
    String repoPath, {
    String? sshKeyPath,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pull', {
      'repoPath': repoPath,
      if (sshKeyPath != null) 'sshKeyPath': sshKeyPath,
    });
    return (
      success: result?['success'] as bool? ?? false,
      output: result?['output'] as String? ?? '',
    );
  }

  static Future<({bool success, String output})> commitAndPush(
    String repoPath,
    String message, {
    String? sshKeyPath,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('commitAndPush', {
      'repoPath': repoPath,
      'message': message,
      if (sshKeyPath != null) 'sshKeyPath': sshKeyPath,
    });
    return (
      success: result?['success'] as bool? ?? false,
      output: result?['output'] as String? ?? '',
    );
  }
}
