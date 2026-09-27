import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// The receipt code printed on the slip, e.g. `AN-7K2Q9C`.
///
/// Must match the server exactly (`anumati.api.v1.consent.short_code`): the
/// first 30 bits of sha256(event_uuid), base32. It depends only on the
/// event_uuid this phone generates, so the worker can write it on the slip
/// before the phone syncs.
String receiptCode(String eventUuid) {
  final digest = sha256.convert(utf8.encode(eventUuid)).bytes;
  var bits = 0;
  var value = 0;
  final out = StringBuffer();
  for (final byte in digest.take(5)) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5 && out.length < 6) {
      out.write(_b32[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  return 'AN-$out';
}

/// A beneficiary reference for people with no ID in a host system.
String newPrincipalRef() {
  final r = Random.secure();
  final s = List.generate(8, (_) => _b32[r.nextInt(32)]).join();
  return 'AC-$s';
}
