import 'draft.dart';

/// Why a use is asked on "Add a use or rejoin".
enum AskKind {
  /// Never asked before: a use added to the notice later.
  newUse,

  /// Asked before and now off (refused at first, or withdrawn since): they may have changed their mind.
  askAgain,

  /// An essential use they withdrew when they left the programme: saying Yes rejoins it.
  rejoin,
}

/// What "Add a use or rejoin" asks a person, and what it shows as already agreed (spec A2, A4).
///
/// - Uses already agreed are never asked again.
/// - An optional use that is not on is asked: new if never decided, "ask again" if refused or withdrawn.
/// - An essential use is asked only after they left the programme (withdrawn): "rejoin".
/// - Uses not allowed for children are not offered to a child; uses that need a phone are not offered to
///   someone without one.
class AskPlan {
  AskPlan({
    required List<NoticePurpose> purposes,
    required Map<String, String> decided,
    required bool minor,
    required bool hasPhone,
  }) : agreed = [
         for (final p in purposes)
           if (decided[p.code] == 'granted') p,
       ],
       toAsk = [
         for (final p in purposes)
           if (_offered(p, minor: minor, hasPhone: hasPhone) && _kind(p, decided[p.code]) != null) p,
       ],
       kinds = {
         for (final p in purposes)
           if (_offered(p, minor: minor, hasPhone: hasPhone)) p.code: ?_kind(p, decided[p.code]),
       };

  /// Already agreed: shown, not asked.
  final List<NoticePurpose> agreed;

  /// Asked now, in notice order.
  final List<NoticePurpose> toAsk;

  /// Why each asked use is asked, by use code.
  final Map<String, AskKind> kinds;

  /// Essential uses being rejoined. The other uses apply only once they say Yes to these: someone who does
  /// not rejoin the programme cannot agree to its extras.
  List<String> get rejoinCodes => [
    for (final p in toAsk)
      if (kinds[p.code] == AskKind.rejoin) p.code,
  ];

  /// Whether this use can be answered yet: while rejoining, only after Yes to every rejoin.
  bool canAnswer(String code, Map<String, bool> answers) =>
      rejoinCodes.contains(code) || rejoinCodes.every((c) => answers[c] == true);

  /// They said No to rejoining: nothing else applies and there is nothing to save.
  bool declinedRejoin(Map<String, bool> answers) => rejoinCodes.any((c) => answers[c] == false);

  /// Every use answered, and not a declined rejoin: ready to save.
  bool complete(Map<String, bool> answers) =>
      toAsk.isNotEmpty && !declinedRejoin(answers) && toAsk.every((p) => answers.containsKey(p.code));

  static bool _offered(NoticePurpose p, {required bool minor, required bool hasPhone}) =>
      !(minor && !p.childAllowed) && !(p.needsPhone && !hasPhone);

  static AskKind? _kind(NoticePurpose p, String? status) {
    if (status == 'granted') return null;
    if (p.essential) return status == 'withdrawn' ? AskKind.rejoin : null;
    return (status == 'withdrawn' || status == 'refused') ? AskKind.askAgain : AskKind.newUse;
  }
}
