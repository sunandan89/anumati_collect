/// Wrong-PIN counting that survives an app restart (review C6). The count and the time until the next
/// try is allowed live in the phone's secure storage, so closing the app does not reset them.
///
/// The first [freeTries] wrong PINs cost nothing; after that each wrong PIN doubles the wait, starting
/// at [firstWait]. At [maxTries] the phone signs out and wipes (AppState).
class PinGuard {
  PinGuard({this.tries = 0, this.waitUntil});

  static const maxTries = 5;
  static const freeTries = 2;
  static const firstWait = Duration(seconds: 30);

  int tries;
  DateTime? waitUntil;

  /// How long to wait before the next try, or zero.
  Duration waitLeft(DateTime now) {
    final until = waitUntil;
    if (until == null || !until.isAfter(now)) return Duration.zero;
    return until.difference(now);
  }

  /// Records a wrong PIN. Returns true when the phone must now sign out and wipe.
  bool wrong(DateTime now) {
    tries++;
    if (tries >= maxTries) return true;
    final extra = tries - freeTries;
    waitUntil = extra > 0 ? now.add(firstWait * (1 << (extra - 1))) : null;
    return false;
  }

  int get triesLeft => maxTries - tries;

  String encode() => '$tries:${waitUntil?.millisecondsSinceEpoch ?? 0}';

  static PinGuard decode(String? stored) {
    final parts = (stored ?? '').split(':');
    if (parts.length != 2) return PinGuard();
    final tries = int.tryParse(parts[0]) ?? 0;
    final ms = int.tryParse(parts[1]) ?? 0;
    return PinGuard(tries: tries, waitUntil: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null);
  }
}
