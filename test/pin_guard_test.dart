import 'package:anumati_collect/core/pin_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 10, 15, 10);

  test('two free tries, then the wait doubles, and the fifth wrong PIN wipes', () {
    final g = PinGuard();
    expect(g.wrong(t0), isFalse);
    expect(g.waitLeft(t0), Duration.zero);
    expect(g.wrong(t0), isFalse);
    expect(g.waitLeft(t0), Duration.zero);
    expect(g.wrong(t0), isFalse);
    expect(g.waitLeft(t0), const Duration(seconds: 30));
    expect(g.wrong(t0), isFalse);
    expect(g.waitLeft(t0), const Duration(seconds: 60));
    expect(g.triesLeft, 1);
    expect(g.wrong(t0), isTrue);
  });

  test('the count and the wait survive a restart', () {
    final g = PinGuard()
      ..wrong(t0)
      ..wrong(t0)
      ..wrong(t0);
    final back = PinGuard.decode(g.encode());
    expect(back.tries, 3);
    expect(back.waitLeft(t0), const Duration(seconds: 30));
    expect(back.waitLeft(t0.add(const Duration(seconds: 31))), Duration.zero);
    expect(PinGuard.decode(null).tries, 0);
    expect(PinGuard.decode('junk').tries, 0);
  });
}
