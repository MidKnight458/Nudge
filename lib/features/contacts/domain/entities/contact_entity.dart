/// Domain representation of a selectable client contact.
class ContactEntity {
  const ContactEntity({
    this.id,
    required this.displayName,
    required this.rawPhone,
    required this.phoneE164,
    required this.isGoogleAccount,
    this.accountName,
  });

  final String? id;
  final String displayName;
  final String rawPhone;
  final String phoneE164;
  final bool isGoogleAccount;
  final String? accountName;

  /// Returns a new list ordered with `com.google` contacts first, then
  /// alphabetically by [displayName] (case-insensitive).
  static List<ContactEntity> sortPrioritizingGoogle(
    List<ContactEntity> contacts,
  ) {
    final sorted = List<ContactEntity>.of(contacts);
    sorted.sort((ContactEntity a, ContactEntity b) {
      if (a.isGoogleAccount != b.isGoogleAccount) {
        return a.isGoogleAccount ? -1 : 1;
      }
      final nameCompare = a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
      if (nameCompare != 0) {
        return nameCompare;
      }
      return a.phoneE164.compareTo(b.phoneE164);
    });
    return sorted;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContactEntity &&
        other.id == id &&
        other.displayName == displayName &&
        other.rawPhone == rawPhone &&
        other.phoneE164 == phoneE164 &&
        other.isGoogleAccount == isGoogleAccount &&
        other.accountName == accountName;
  }

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        rawPhone,
        phoneE164,
        isGoogleAccount,
        accountName,
      );
}
