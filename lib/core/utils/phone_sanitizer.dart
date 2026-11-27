import 'dart:ui';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Candidate phone entry extracted from a device contact.
class PhoneCandidate {
  const PhoneCandidate({required this.number, required this.label});

  final String number;
  final PhoneLabel label;
}

/// Utilities to normalize device and manual phone numbers into WhatsApp-ready
/// international E.164 digit strings (without leading `+`).
abstract final class PhoneSanitizer {
  static const IsoCode defaultFallbackCountry = IsoCode.MX;

  /// Resolves an ISO-3166 alpha-2 [countryCode] into an [IsoCode],
  /// falling back to [defaultFallbackCountry] when missing or unrecognized.
  static IsoCode resolveIsoCode(String? countryCode) {
    if (countryCode == null || countryCode.trim().isEmpty) {
      return defaultFallbackCountry;
    }
    final normalized = countryCode.trim().toUpperCase();
    for (final code in IsoCode.values) {
      if (code.name == normalized) {
        return code;
      }
    }
    return defaultFallbackCountry;
  }

  /// Infers the caller's country from the platform locale.
  static IsoCode deviceCallerCountry() {
    final countryCode = PlatformDispatcher.instance.locale.countryCode;
    return resolveIsoCode(countryCode);
  }

  /// Normalizes [rawPhone] to an E.164 digit string without `+`
  /// (e.g. `524611234567`). Returns `null` if [rawPhone] is empty or invalid.
  static String? sanitizeToE164Digits(
    String rawPhone, {
    IsoCode? callerCountry,
  }) {
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty || RegExp(r'[a-zA-Z]').hasMatch(trimmed)) {
      return null;
    }

    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length < 7) {
      return null;
    }

    final resolvedCountry = callerCountry ?? deviceCallerCountry();
    try {
      final parsed = PhoneNumber.parse(trimmed, callerCountry: resolvedCountry);
      if (!parsed.isValid() && !parsed.isValidLength()) {
        return null;
      }
      final e164Digits = parsed.international.replaceAll(RegExp(r'[^0-9]'), '');
      if (e164Digits.length < 7 || e164Digits.length > 15) {
        return null;
      }
      return e164Digits;
    } on PhoneNumberException {
      return null;
    }
  }

  /// Formats an E.164 digit string or raw phone for readable UI presentation.
  static String formatForDisplay(String rawOrE164, {IsoCode? callerCountry}) {
    final trimmed = rawOrE164.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final candidate =
        trimmed.startsWith('+') || RegExp(r'[^0-9]').hasMatch(trimmed)
        ? trimmed
        : '+$trimmed';

    try {
      final parsed = PhoneNumber.parse(
        candidate,
        callerCountry: callerCountry ?? deviceCallerCountry(),
      );
      if (parsed.isValid() || parsed.isValidLength()) {
        return '+${parsed.countryCode} ${parsed.formatNsn()}';
      }
    } on PhoneNumberException {
      // Fall back to the original string if parsing fails.
    }
    return trimmed;
  }

  /// Selects the preferred phone from [candidates], prioritizing mobile/cell
  /// labels before falling back to the first valid number.
  static ({String rawPhone, String phoneE164})? selectPreferredPhone(
    List<PhoneCandidate> candidates, {
    IsoCode? callerCountry,
  }) {
    if (candidates.isEmpty) {
      return null;
    }

    final sorted = List<PhoneCandidate>.of(candidates)
      ..sort(
        (a, b) => _labelPriority(a.label).compareTo(_labelPriority(b.label)),
      );

    for (final candidate in sorted) {
      final e164 = sanitizeToE164Digits(
        candidate.number,
        callerCountry: callerCountry,
      );
      if (e164 != null) {
        return (rawPhone: candidate.number.trim(), phoneE164: e164);
      }
    }
    return null;
  }

  static int _labelPriority(PhoneLabel label) {
    return switch (label) {
      PhoneLabel.mobile => 0,
      PhoneLabel.workMobile => 1,
      PhoneLabel.iPhone => 2,
      PhoneLabel.main => 3,
      _ => 4,
    };
  }
}
