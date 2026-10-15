import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

/// The two things the consent package needs from a data layer: save a DocType record (offline first)
/// and read records back. On a phone this is the host's Frappe Mobile SDK ([SdkConsentData]); tests
/// use a fake.
abstract class ConsentData {
  /// Saves [data] as a [doctype] record and returns its id (the `mobile_uuid` when offline).
  Future<String> save(String doctype, Map<String, dynamic> data);

  /// Reads [doctype] records matching Frappe-style [filters] (`[[field, op, value], …]`).
  Future<List<Map<String, Object?>>> list(String doctype, {List<List> filters = const [], int pageSize = 200});
}

/// [ConsentData] over the host app's `FrappeSDK`: its offline repository (local table + outbox, pushed
/// by the SDK's sync) and its resolver (local tables pulled by the SDK's sync).
class SdkConsentData implements ConsentData {
  SdkConsentData(this.sdk);

  final FrappeSDK sdk;

  @override
  Future<String> save(String doctype, Map<String, dynamic> data) =>
      sdk.repository.saveDocument(doctype: doctype, data: data);

  @override
  Future<List<Map<String, Object?>>> list(String doctype, {List<List> filters = const [], int pageSize = 200}) async {
    final out = await sdk.resolver.resolve(doctype: doctype, filters: filters, pageSize: pageSize);
    return out.rows;
  }
}
