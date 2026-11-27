import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';

/// Permission status when accessing local device contacts.
enum ContactsPermissionState {
  granted,
  denied,
  permanentlyDenied,
}

/// Domain contract for reading and prioritizing local contacts.
abstract interface class ContactsRepository {
  Future<ContactsPermissionState> checkPermission();

  Future<ContactsPermissionState> requestPermission();

  Future<List<ContactEntity>> getContacts();
}
