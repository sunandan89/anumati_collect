import 'dart:convert';
import 'dart:io';

import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

/// The server calls the app makes. Everything goes through stock Frappe
/// endpoints or the Anumati v1 API, authenticated by the Frappe Mobile SDK
/// session (Frappe Mobile Control login). No personal data is logged.
abstract class Server {
  Future<List<Map<String, dynamic>>> programmes();
  Future<Map<String, dynamic>> programme(String code);
  Future<Map<String, dynamic>> activeNotice(String programme, String? language);
  Future<File?> download(String fileUrl, File to);

  Future<void> upsertPrincipal(Map<String, dynamic> values);
  Future<String?> principalName(String ref);
  Future<String> guardianLink(Map<String, dynamic> doc);
  Future<String> uploadEvidence(File file, String principalName, String fileName);
  Future<Map<String, dynamic>> record(Map<String, dynamic> event);
  Future<Map<String, dynamic>> withdraw(Map<String, dynamic> args);
  Future<Map<String, dynamic>> submitRequest(Map<String, dynamic> args);
}

/// The app's failure kinds, so sync knows whether to stop, retry or park.
enum Failure { offline, auth, rejected }

class ServerFailure implements Exception {
  ServerFailure(this.kind, this.message);
  final Failure kind;
  final String message;
  @override
  String toString() => message;
}

class SdkServer implements Server {
  SdkServer(this.sdk);
  final FrappeSDK sdk;

  FrappeClient get _api => sdk.api;

  Future<dynamic> _call(String method, Map<String, dynamic> args, {bool get = false}) async {
    try {
      final body = await _api.call(method, args: args, httpMethod: get ? 'GET' : 'POST');
      return body is Map ? body['message'] : body;
    } on AuthException catch (e) {
      throw ServerFailure(Failure.auth, e.message);
    } on NetworkException catch (e) {
      throw ServerFailure(Failure.offline, e.message);
    } on ApiException catch (e) {
      final code = e.statusCode ?? 0;
      if (code >= 500 || code == 0 || code == 429) {
        throw ServerFailure(Failure.offline, e.message);
      }
      throw ServerFailure(Failure.rejected, e.message);
    } on SocketException catch (e) {
      throw ServerFailure(Failure.offline, e.message);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> programmes() async {
    final rows = await _call('frappe.client.get_list', {
      'doctype': 'Programme',
      'fields': jsonEncode(['name', 'programme_name', 'status']),
      'filters': jsonEncode([
        ['status', '!=', 'Paused'],
      ]),
      'limit_page_length': 200,
    }, get: true);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  @override
  Future<Map<String, dynamic>> programme(String code) async {
    final doc = await _call('frappe.client.get', {'doctype': 'Programme', 'name': code}, get: true);
    return Map<String, dynamic>.from(doc as Map);
  }

  @override
  Future<Map<String, dynamic>> activeNotice(String programme, String? language) async {
    final out = await _call('anumati.api.v1.notice.get_active', {
      'programme': programme,
      'language': ?language,
    }, get: true);
    return Map<String, dynamic>.from(out as Map);
  }

  @override
  Future<File?> download(String fileUrl, File to) async {
    final uri = Uri.parse(fileUrl.startsWith('http') ? fileUrl : '${_api.baseUrl}$fileUrl');
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      _api.requestHeaders.forEach(req.headers.set);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      await res.pipe(to.openWrite());
      return to;
    } on SocketException {
      return null;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> upsertPrincipal(Map<String, dynamic> values) => _call('anumati.api.v1.principal.upsert', values);

  @override
  Future<String?> principalName(String ref) async {
    final out = await _call('frappe.client.get_value', {
      'doctype': 'Data Principal',
      'filters': jsonEncode({'principal_ref': ref}),
      'fieldname': 'name',
    }, get: true);
    return out is Map ? out['name'] as String? : null;
  }

  @override
  Future<String> guardianLink(Map<String, dynamic> doc) async {
    final existing = await _call('frappe.client.get_list', {
      'doctype': 'Guardian Link',
      'filters': jsonEncode({'principal': doc['principal'], 'guardian': doc['guardian']}),
      'fields': jsonEncode(['name']),
      'limit_page_length': 1,
    }, get: true);
    if (existing is List && existing.isNotEmpty) {
      return existing.first['name'] as String;
    }
    final out = await _call('frappe.client.insert', {
      'doc': {'doctype': 'Guardian Link', ...doc},
    });
    return (out as Map)['name'] as String;
  }

  @override
  Future<String> uploadEvidence(File file, String principalName, String fileName) async {
    try {
      final body = await _api.rest.uploadFile(
        '/api/method/upload_file',
        'file',
        file,
        filename: fileName,
        fields: {'is_private': '1', 'doctype': 'Data Principal', 'docname': principalName},
      );
      return ((body as Map)['message'] as Map)['file_url'] as String;
    } on AuthException catch (e) {
      throw ServerFailure(Failure.auth, e.message);
    } on NetworkException catch (e) {
      throw ServerFailure(Failure.offline, e.message);
    } on ApiException catch (e) {
      throw ServerFailure((e.statusCode ?? 0) >= 500 ? Failure.offline : Failure.rejected, e.message);
    }
  }

  @override
  Future<Map<String, dynamic>> record(Map<String, dynamic> event) async =>
      Map<String, dynamic>.from(await _call('anumati.api.v1.consent.record', {'event': event}) as Map);

  @override
  Future<Map<String, dynamic>> withdraw(Map<String, dynamic> args) async =>
      Map<String, dynamic>.from(await _call('anumati.api.v1.consent.withdraw', args) as Map);

  @override
  Future<Map<String, dynamic>> submitRequest(Map<String, dynamic> args) async =>
      Map<String, dynamic>.from(await _call('anumati.api.v1.rights.submit', args) as Map);
}
