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
    this.searchQuery = '',
    this.isLoading = false,
    this.errorMessage,
  });

  final ContactsPermissionState permissionState;
  final List<ContactEntity> allContacts;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;

  List<ContactEntity> get filteredContacts {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return allContacts;
    }
    final digitsQuery = query.replaceAll(RegExp(r'[^0-9]'), '');
    return allContacts.where((ContactEntity contact) {
      final matchesName = contact.displayName.toLowerCase().contains(query);
      final matchesRawPhone = contact.rawPhone.toLowerCase().contains(query);
      final matchesDigits =
          digitsQuery.isNotEmpty && contact.phoneE164.contains(digitsQuery);
      return matchesName || matchesRawPhone || matchesDigits;
    }).toList(growable: false);
  }

  ContactsState copyWith({
    ContactsPermissionState? permissionState,
    List<ContactEntity>? allContacts,
    String? searchQuery,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ContactsState(
      permissionState: permissionState ?? this.permissionState,
      allContacts: allContacts ?? this.allContacts,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Manages contact permissions, loading, and search filtering.
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
      state = state.copyWith(
        permissionState: ContactsPermissionState.granted,
        allContacts: contacts,
        isLoading: false,
      );
    } catch (error) {
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
      state = state.copyWith(
        permissionState: permission,
        isLoading: false,
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

final contactsControllerProvider =
    AutoDisposeNotifierProvider<ContactsController, ContactsState>(
  ContactsController.new,
);
