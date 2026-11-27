import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

void main() {
  group('PhoneSanitizer', () {
    test('normalizes international numbers with country prefix to E.164 digits',
        () {
      expect(
        PhoneSanitizer.sanitizeToE164Digits(
          '+52 461 123 4567',
          callerCountry: IsoCode.MX,
        ),
        '524611234567',
      );
      expect(
        PhoneSanitizer.sanitizeToE164Digits(
          '+1 (650) 555-0199',
          callerCountry: IsoCode.US,
        ),
        '16505550199',
      );
      expect(
        PhoneSanitizer.sanitizeToE164Digits(
          '00 34 612 34 56 78',
          callerCountry: IsoCode.ES,
        ),
        '34612345678',
      );
    });

    test('infers caller country code when local number lacks prefix', () {
      expect(
        PhoneSanitizer.sanitizeToE164Digits(
          '461 123 4567',
          callerCountry: IsoCode.MX,
        ),
        '524611234567',
      );
      expect(
        PhoneSanitizer.sanitizeToE164Digits(
          '(650) 555-0199',
          callerCountry: IsoCode.US,
        ),
        '16505550199',
      );
    });

    test('returns null for empty, alphabetic, or too-short inputs', () {
      expect(PhoneSanitizer.sanitizeToE164Digits(''), isNull);
      expect(PhoneSanitizer.sanitizeToE164Digits('   '), isNull);
      expect(PhoneSanitizer.sanitizeToE164Digits('12345'), isNull);
      expect(PhoneSanitizer.sanitizeToE164Digits('tel 4611234567'), isNull);
    });

    test('resolves ISO codes with MX fallback for missing or unknown codes',
        () {
      expect(PhoneSanitizer.resolveIsoCode('us'), IsoCode.US);
      expect(PhoneSanitizer.resolveIsoCode('ES'), IsoCode.ES);
      expect(PhoneSanitizer.resolveIsoCode(null), IsoCode.MX);
      expect(PhoneSanitizer.resolveIsoCode('ZZ'), IsoCode.MX);
    });

    test('selectPreferredPhone prioritizes mobile labels over landline/other',
        () {
      final selected = PhoneSanitizer.selectPreferredPhone(
        const <PhoneCandidate>[
          PhoneCandidate(number: '461 200 0000', label: PhoneLabel.home),
          PhoneCandidate(number: '461 999 8888', label: PhoneLabel.mobile),
        ],
        callerCountry: IsoCode.MX,
      );

      expect(selected, isNotNull);
      expect(selected!.rawPhone, '461 999 8888');
      expect(selected.phoneE164, '524619998888');
    });
  });

  group('ContactEntity.sortPrioritizingGoogle', () {
    test('places com.google contacts first and sorts alphabetically', () {
      const localZ = ContactEntity(
        id: '1',
        displayName: 'Ana Local',
        rawPhone: '4611111111',
        phoneE164: '524611111111',
        isGoogleAccount: false,
      );
      const googleB = ContactEntity(
        id: '2',
        displayName: 'Carlos Google',
        rawPhone: '4612222222',
        phoneE164: '524612222222',
        isGoogleAccount: true,
        accountName: 'pro@gmail.com',
      );
      const googleA = ContactEntity(
        id: '3',
        displayName: 'Beatriz Google',
        rawPhone: '4613333333',
        phoneE164: '524613333333',
        isGoogleAccount: true,
        accountName: 'pro@gmail.com',
      );

      final sorted = ContactEntity.sortPrioritizingGoogle(
        const <ContactEntity>[localZ, googleB, googleA],
      );

      expect(
        sorted.map((ContactEntity c) => c.displayName).toList(),
        <String>['Beatriz Google', 'Carlos Google', 'Ana Local'],
      );
    });
  });
}
