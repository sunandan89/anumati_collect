import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Device SMS OTP (spec section 5, "Signal, no data"): the app makes a 6-digit
/// code, opens the SMS app pre-filled to the principal's number, and the
/// principal reads the code back. Only a salted hash is kept in memory; the
/// code itself is never stored or synced.
class DeviceOtp {
  DeviceOtp._(this._salt, this._hash);

  final String _salt;
  final String _hash;
  int _tries = 0;

  static const maxTries = 5;

  /// Returns the OTP holder and the code to put in the SMS body.
  static (DeviceOtp, String) generate() {
    final r = Random.secure();
    final code = List.generate(6, (_) => r.nextInt(10)).join();
    final salt = base64Url.encode(List.generate(16, (_) => r.nextInt(256)));
    return (DeviceOtp._(salt, _digest(salt, code)), code);
  }

  static String _digest(String salt, String code) => sha256.convert(utf8.encode('$salt:$code')).toString();

  bool get locked => _tries >= maxTries;

  bool verify(String entered) {
    if (locked) return false;
    _tries++;
    return _digest(_salt, entered.trim()) == _hash;
  }
}
