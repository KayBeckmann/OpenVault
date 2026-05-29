import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  static final ApiClient _instance = ApiClient._();
  ApiClient._();
  factory ApiClient() => _instance;

  // In production this comes from env/config; during dev the Flutter Web dev
  // server proxies /api to localhost:8080 via nginx (or we use the direct URL).
  final String _base = kDebugMode ? 'http://localhost:8080' : '';

  String? _token;

  void setToken(String? token) => _token = token;
  bool get isAuthenticated => _token != null;

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final resp = await http.post(
      Uri.parse('$_base$path'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw ApiException(decoded['error'] as String? ?? 'Unknown error', resp.statusCode);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final resp = await http.delete(
      Uri.parse('$_base$path'),
      headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
    );
    if (resp.body.isEmpty) return {};
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw ApiException(decoded['error'] as String? ?? 'Unknown error', resp.statusCode);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> get(String path) async {
    final resp = await http.get(
      Uri.parse('$_base$path'),
      headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode >= 400) {
      throw ApiException(decoded['error'] as String? ?? 'Unknown error', resp.statusCode);
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> getList(String path) async {
    final resp = await http.get(
      Uri.parse('$_base$path'),
      headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
    );
    if (resp.statusCode >= 400) {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      throw ApiException(decoded['error'] as String? ?? 'Unknown error', resp.statusCode);
    }
    final list = jsonDecode(resp.body) as List;
    return list.cast<Map<String, dynamic>>();
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
