import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/contacts/domain/contacts_repository.dart';
import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';
import 'package:permission_handler/permission_handler.dart';

/// Reads contacts from the device and prioritizes `com.google` accounts.
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
