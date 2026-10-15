import 'dart:convert';

import 'package:crypto/crypto.dart';

const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// The receipt code printed on the slip, e.g. `AN-7K2Q9C`.
///
/// Must match the server exactly (`anumati.api.v1.consent.short_code`): the first 30 bits of
/// sha256(event_uuid), base32. The event_uuid is the record's `mobile_uuid`, made on the phone, so the
/// code is known before the record syncs.
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
