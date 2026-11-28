import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/features/contacts/data/local_contacts_repository_impl.dart';
import 'package:nudge/features/contacts/domain/contacts_repository.dart';
import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';

/// Provides the [ContactsRepository] implementation.
final contactsRepositoryProvider = Provider<ContactsRepository>((Ref ref) {
  return const LocalContactsRepositoryImpl();
});

/// Reactive UI state for the contacts picker.
class ContactsState {
  const ContactsState({
    this.permissionState = ContactsPermissionState.denied,
    this.allContacts = const <ContactEntity>[],
    this.deviceGoogleAccounts = const <String>[],
    this.searchQuery = '',
    this.isLoading = false,
    this.errorMessage,
  });

  final ContactsPermissionState permissionState;
  final List<ContactEntity> allContacts;
  final List<String> deviceGoogleAccounts;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;

  List<ContactEntity> get filteredContacts {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return allContacts;
    }
    final digitsQuery = query.replaceAll(RegExp(r'[^0-9]'), '');
    return allContacts
        .where((ContactEntity contact) {
          final matchesName = contact.displayName.toLowerCase().contains(query);
          final matchesRawPhone = contact.rawPhone.toLowerCase().contains(
            query,
          );
          final matchesDigits =
              digitsQuery.isNotEmpty && contact.phoneE164.contains(digitsQuery);
          return matchesName || matchesRawPhone || matchesDigits;
        })
        .toList(growable: false);
  }

  ContactsState copyWith({
    ContactsPermissionState? permissionState,
    List<ContactEntity>? allContacts,
    List<String>? deviceGoogleAccounts,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ContactsState(
      permissionState: permissionState ?? this.permissionState,
      allContacts: allContacts ?? this.allContacts,
      deviceGoogleAccounts: deviceGoogleAccounts ?? this.deviceGoogleAccounts,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Manages contact permissions, loading, Google account discovery, and search.
class ContactsController extends AutoDisposeNotifier<ContactsState> {
  @override
  ContactsState build() {
    Future<void>.microtask(loadContacts);
    return const ContactsState(isLoading: true);
  }

  ContactsRepository get _repository => ref.read(contactsRepositoryProvider);

  Future<void> loadContacts() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var permission = await _repository.checkPermission();
      if (permission == ContactsPermissionState.denied) {
        permission = await _repository.requestPermission();
      }
      if (permission != ContactsPermissionState.granted) {
        state = state.copyWith(
          permissionState: permission,
          allContacts: const <ContactEntity>[],
          isLoading: false,
        );
        return;
      }

      final contacts = await _repository.getContacts();
      final accounts =
          contacts
              .where(
                (ContactEntity c) => c.isGoogleAccount && c.accountName != null,
              )
              .map((ContactEntity c) => c.accountName!)
              .toSet()
              .toList(growable: false)
            ..sort();

      state = state.copyWith(
        permissionState: ContactsPermissionState.granted,
        allContacts: contacts,
        deviceGoogleAccounts: accounts,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No se pudieron leer los contactos del dispositivo.',
      );
    }
  }

  Future<void> requestPermissionAndLoad() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final permission = await _repository.requestPermission();
    if (permission == ContactsPermissionState.granted) {
      await loadContacts();
    } else {
      state = state.copyWith(permissionState: permission, isLoading: false);
    }
  }

  Future<ContactEntity> saveManualContactToGoogle({
    required String displayName,
    required String rawPhone,
    required String phoneE164,
    String? googleAccountName,
  }) async {
    final created = await _repository.saveContactToDevice(
      displayName: displayName,
      rawPhone: rawPhone,
      phoneE164: phoneE164,
      googleAccountName: googleAccountName,
    );

    final updated = ContactEntity.sortPrioritizingGoogle(<ContactEntity>[
      created,
      ...state.allContacts.where(
        (ContactEntity c) =>
            c.phoneE164 != created.phoneE164 ||
            c.displayName != created.displayName,
      ),
    ]);
    final accounts = <String>{
      ...state.deviceGoogleAccounts,
      if (created.accountName != null && created.accountName!.isNotEmpty)
        created.accountName!,
    }.toList(growable: false)..sort();

    state = state.copyWith(
      permissionState: ContactsPermissionState.granted,
      allContacts: updated,
      deviceGoogleAccounts: accounts,
    );
    return created;
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

final contactsControllerProvider =
    AutoDisposeNotifierProvider<ContactsController, ContactsState>(
      ContactsController.new,
    );
