import 'package:anumati_collect/core/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => Strings.uiLang = 'en');

  test('a count of one reads in the singular', () {
    expect(trCount(1, '{0} record on this phone', '{0} records on this phone'), '1 record on this phone');
    expect(trCount(0, '{0} record on this phone', '{0} records on this phone'), '0 records on this phone');
    expect(trCount(3, '{0} record on this phone', '{0} records on this phone'), '3 records on this phone');
  });

  test('both forms have Hindi', () {
    Strings.uiLang = 'hi';
    expect(trCount(1, '{0} record on this phone', '{0} records on this phone'), 'इस फ़ोन पर 1 रिकॉर्ड');
    const one = '{0} record could not be saved on the server. Open to see why.';
    const many = '{0} records could not be saved on the server. Open to see why.';
    expect(trCount(1, one, many), isNot(contains('record')));
    expect(trCount(2, one, many), isNot(contains('record')));
  });
}
