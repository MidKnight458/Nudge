import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/contacts/domain/contacts_repository.dart';
import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';
import 'package:permission_handler/permission_handler.dart';

/// Reads and creates device contacts, prioritizing and targeting `com.google`.
class LocalContactsRepositoryImpl implements ContactsRepository {
  const LocalContactsRepositoryImpl();

  @override
  Future<ContactsPermissionState> checkPermission() async {
    final status = await Permission.contacts.status;
    return _mapPermissionStatus(status);
  }

  @override
  Future<ContactsPermissionState> requestPermission() async {
    final status = await Permission.contacts.request();
    return _mapPermissionStatus(status);
  }

  @override
  Future<List<ContactEntity>> getContacts() async {
    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withAccounts: true,
    );

    final callerCountry = PhoneSanitizer.deviceCallerCountry();
    final mapped = <ContactEntity>[];

    for (final contact in contacts) {
      if (contact.phones.isEmpty) {
        continue;
      }

      final candidates = contact.phones
          .map(
            (Phone phone) =>
                PhoneCandidate(number: phone.number, label: phone.label),
          )
          .toList(growable: false);

      final selectedPhone = PhoneSanitizer.selectPreferredPhone(
        candidates,
        callerCountry: callerCountry,
      );
      if (selectedPhone == null) {
        continue;
      }

      final googleAccount = contact.accounts
          .where((Account a) => a.type == AppConstants.googleAccountType)
          .firstOrNull;

      final displayName = contact.displayName.trim().isNotEmpty
          ? contact.displayName.trim()
          : PhoneSanitizer.formatForDisplay(
              selectedPhone.phoneE164,
              callerCountry: callerCountry,
            );

      mapped.add(
        ContactEntity(
          id: contact.id.trim().isEmpty ? null : contact.id.trim(),
          displayName: displayName,
          rawPhone: selectedPhone.rawPhone,
          phoneE164: selectedPhone.phoneE164,
          isGoogleAccount: googleAccount != null,
          accountName: googleAccount?.name.isNotEmpty == true
              ? googleAccount!.name
              : null,
        ),
      );
    }

    return ContactEntity.sortPrioritizingGoogle(mapped);
  }

  @override
  Future<List<String>> getGoogleAccountNames() async {
    final permission = await checkPermission();
    if (permission != ContactsPermissionState.granted) {
      return const <String>[];
    }

    final contacts = await FlutterContacts.getContacts(
      withProperties: false,
      withAccounts: true,
    );
    final accounts = <String>{};
    for (final contact in contacts) {
      for (final account in contact.accounts) {
        final name = account.name.trim();
        if (account.type == AppConstants.googleAccountType && name.isNotEmpty) {
          accounts.add(name);
        }
      }
    }
    return accounts.toList(growable: false)..sort();
  }

  @override
  Future<ContactEntity> saveContactToDevice({
    required String displayName,
    required String rawPhone,
    required String phoneE164,
    String? googleAccountName,
  }) async {
    final granted = await FlutterContacts.requestPermission(readonly: false);
    if (!granted) {
      throw StateError(
        'Concede permiso de contactos para guardar en tu agenda de Google.',
      );
    }

    final trimmedName = displayName.trim();
    final nameParts = trimmedName
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    final firstName = nameParts.isNotEmpty ? nameParts.first : trimmedName;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final formattedPhone = PhoneSanitizer.formatForDisplay(phoneE164);
    final cleanAccount = googleAccountName?.trim();
    final hasGoogleAccount = cleanAccount != null && cleanAccount.isNotEmpty;

    final newContact = Contact(
      displayName: trimmedName,
      name: Name(first: firstName, last: lastName),
      phones: <Phone>[
        Phone(
          formattedPhone.isNotEmpty ? formattedPhone : rawPhone.trim(),
          label: PhoneLabel.mobile,
        ),
      ],
      accounts: hasGoogleAccount
          ? <Account>[
              Account(
                '',
                AppConstants.googleAccountType,
                cleanAccount,
                const <String>[],
              ),
            ]
          : <Account>[],
    );

    final inserted = await FlutterContacts.insertContact(newContact);
    final insertedGoogle = inserted.accounts
        .where((Account a) => a.type == AppConstants.googleAccountType)
        .firstOrNull;

    return ContactEntity(
      id: inserted.id.trim().isEmpty ? null : inserted.id.trim(),
      displayName: inserted.displayName.trim().isNotEmpty
          ? inserted.displayName.trim()
          : trimmedName,
      rawPhone: rawPhone.trim(),
      phoneE164: phoneE164.trim(),
      isGoogleAccount: hasGoogleAccount || insertedGoogle != null,
      accountName: insertedGoogle?.name.isNotEmpty == true
          ? insertedGoogle!.name
          : (hasGoogleAccount ? cleanAccount : null),
    );
  }

  ContactsPermissionState _mapPermissionStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return ContactsPermissionState.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return ContactsPermissionState.permanentlyDenied;
    }
    return ContactsPermissionState.denied;
  }
}
