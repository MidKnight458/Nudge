import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';

/// Permission status when accessing local device contacts.
enum ContactsPermissionState { granted, denied, permanentlyDenied }

/// Domain contract for reading, prioritizing, and saving device contacts.
abstract interface class ContactsRepository {
  Future<ContactsPermissionState> checkPermission();

  Future<ContactsPermissionState> requestPermission();

  Future<List<ContactEntity>> getContacts();

  Future<List<String>> getGoogleAccountNames();

  Future<ContactEntity> saveContactToDevice({
    required String displayName,
    required String rawPhone,
    required String phoneE164,
    String? googleAccountName,
  });
}
