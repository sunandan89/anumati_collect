import 'package:anumati_collect/capture/ask_plan.dart';
import 'package:anumati_collect/capture/draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// Village Health Camps, as in the product guide's "Ask for one more purpose" examples. Fictional.
NoticePurpose use(String code, {bool essential = false, bool child = true, bool phone = false}) => NoticePurpose({
  'code': code,
  'purpose_title': code,
  'essential': essential,
  'child_allowed': child,
  'needs_phone': phone,
});

final notice = [
  use('screen', essential: true),
  use('follow', phone: true),
  use('photos'),
  use('research', child: false),
  use('tips', phone: true), // added to the notice later
];

AskPlan plan(Map<String, String> decided, {bool minor = false, bool hasPhone = true}) =>
    AskPlan(purposes: notice, decided: decided, minor: minor, hasPhone: hasPhone);

List<String> codes(List<NoticePurpose> ps) => [for (final p in ps) p.code];

void main() {
  test('case 1: a new use is asked; a use refused at first is asked again; agreed uses are not', () {
    final p = plan({'screen': 'granted', 'follow': 'granted', 'photos': 'refused', 'research': 'granted'});
    expect(codes(p.agreed), ['screen', 'follow', 'research']);
    expect(codes(p.toAsk), ['photos', 'tips']);
    expect(p.kinds, {'photos': AskKind.askAgain, 'tips': AskKind.newUse});
  });

  test('case 2: a withdrawn use is asked again', () {
    final p = plan({
      'screen': 'granted',
      'follow': 'withdrawn',
      'photos': 'granted',
      'research': 'granted',
      'tips': 'granted',
    });
    expect(codes(p.toAsk), ['follow']);
    expect(p.kinds['follow'], AskKind.askAgain);
  });

  test('case 3: after leaving the programme, the essential use is a rejoin and the rest are asked again', () {
    final p = plan({
      'screen': 'withdrawn',
      'follow': 'withdrawn',
      'photos': 'refused',
      'research': 'withdrawn',
      'tips': 'withdrawn',
    });
    expect(p.agreed, isEmpty);
    expect(codes(p.toAsk), ['screen', 'follow', 'photos', 'research', 'tips']);
    expect(p.kinds['screen'], AskKind.rejoin);
    expect(p.kinds['follow'], AskKind.askAgain);
  });

  test('an essential use is never asked unless they left', () {
    expect(plan({'follow': 'granted'}).kinds.containsKey('screen'), isFalse);
  });

  test('nothing to ask when everything is agreed', () {
    final all = {for (final p in notice) p.code: 'granted'};
    expect(plan(all).toAsk, isEmpty);
  });

  test('no phone: uses that need a phone are not offered; child: uses not for children are not offered', () {
    expect(codes(plan({'screen': 'granted'}, hasPhone: false).toAsk), ['photos', 'research']);
    expect(codes(plan({'screen': 'granted'}, minor: true).toAsk), ['follow', 'photos', 'tips']);
  });
}
