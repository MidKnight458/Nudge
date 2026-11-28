import 'dart:convert';

import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

/// Custom service or appointment reason configurable in Settings.
class CustomServiceItem {
  const CustomServiceItem({
    required this.id,
    required this.name,
    required this.durationMinutes,
  });

  factory CustomServiceItem.fromMap(Map<String, dynamic> map) {
    final rawDuration = (map['durationMinutes'] as num?)?.toInt();
    return CustomServiceItem(
      id: (map['id'] as String?)?.trim() ?? '',
      name: (map['name'] as String?)?.trim() ?? '',
      durationMinutes: (rawDuration != null && rawDuration > 0)
          ? rawDuration
          : AppConstants.defaultSlotDurationMinutes,
    );
  }

  final String id;
  final String name;
  final int durationMinutes;

  CustomServiceItem copyWith({String? id, String? name, int? durationMinutes}) {
    return CustomServiceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'durationMinutes': durationMinutes,
  };

  static List<CustomServiceItem> decodeList(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List<dynamic>) {
        return const <CustomServiceItem>[];
      }
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> e) =>
                CustomServiceItem.fromMap(Map<String, dynamic>.from(e)),
          )
          .where((CustomServiceItem item) => item.name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <CustomServiceItem>[];
    }
  }

  static String encodeList(List<CustomServiceItem> items) =>
      jsonEncode(items.map((e) => e.toMap()).toList(growable: false));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomServiceItem &&
        other.id == id &&
        other.name == name &&
        other.durationMinutes == durationMinutes;
  }

  @override
  int get hashCode => Object.hash(id, name, durationMinutes);
}

/// Configurable appointment time slots & default duration.
class ScheduleConfig {
  const ScheduleConfig({
    this.defaultSlotDurationMinutes = AppConstants.defaultSlotDurationMinutes,
    this.slotMinutesFromMidnight = const <int>[],
  });

  factory ScheduleConfig.fromMap(Map<String, dynamic> map) {
    final rawDuration = (map['defaultSlotDurationMinutes'] as num?)?.toInt();
    final rawSlots = map['slotMinutesFromMidnight'];
    final slots = <int>{};
    if (rawSlots is List<dynamic>) {
      for (final value in rawSlots) {
        final mins = (value as num?)?.toInt();
        if (mins != null && mins >= 0 && mins < 24 * 60) {
          slots.add(mins);
        }
      }
    }
    final sortedSlots = slots.toList()..sort();
    return ScheduleConfig(
      defaultSlotDurationMinutes: (rawDuration != null && rawDuration > 0)
          ? rawDuration
          : AppConstants.defaultSlotDurationMinutes,
      slotMinutesFromMidnight: List<int>.unmodifiable(sortedSlots),
    );
  }

  factory ScheduleConfig.fromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<dynamic, dynamic>) {
        return ScheduleConfig.fromMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return const ScheduleConfig();
  }

  final int defaultSlotDurationMinutes;
  final List<int> slotMinutesFromMidnight;

  bool get hasConfiguredSlots => slotMinutesFromMidnight.isNotEmpty;

  ScheduleConfig copyWith({
    int? defaultSlotDurationMinutes,
    List<int>? slotMinutesFromMidnight,
  }) {
    final normalized =
        (slotMinutesFromMidnight ?? this.slotMinutesFromMidnight)
            .where((int m) => m >= 0 && m < 24 * 60)
            .toSet()
            .toList()
          ..sort();
    return ScheduleConfig(
      defaultSlotDurationMinutes:
          defaultSlotDurationMinutes ?? this.defaultSlotDurationMinutes,
      slotMinutesFromMidnight: List<int>.unmodifiable(normalized),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'defaultSlotDurationMinutes': defaultSlotDurationMinutes,
    'slotMinutesFromMidnight': slotMinutesFromMidnight,
  };

  String toJson() => jsonEncode(toMap());

  /// Generates sorted slot start minutes in `[startMinutes, endMinutes]`,
  /// ensuring `slot + intervalMinutes` never overflows 24h cleanly.
  static List<int> generateSlots({
    required int startMinutes,
    required int endMinutes,
    required int intervalMinutes,
  }) {
    if (intervalMinutes <= 0 || endMinutes < startMinutes) {
      return const <int>[];
    }
    final slots = <int>[];
    for (
      var current = startMinutes;
      current <= endMinutes;
      current += intervalMinutes
    ) {
      if (current >= 0 && current < 24 * 60) {
        slots.add(current);
      }
    }
    return List<int>.unmodifiable(slots);
  }

  /// Filters [slotMinutesFromMidnight] to exclude slots that overlap any
  /// existing appointment on [day] (excluding [excludeAppointmentId]).
  List<int> availableSlotsForDay({
    required DateTime day,
    required List<AppointmentEntity> dayAppointments,
    int? durationMinutes,
    int? excludeAppointmentId,
  }) {
    if (slotMinutesFromMidnight.isEmpty) {
      return const <int>[];
    }

    final slotDuration = Duration(
      minutes: (durationMinutes != null && durationMinutes > 0)
          ? durationMinutes
          : defaultSlotDurationMinutes,
    );
    final baseDay = DateTime(day.year, day.month, day.day);

    return slotMinutesFromMidnight
        .where((int slotMinutes) {
          final slotStart = baseDay.add(Duration(minutes: slotMinutes));
          final slotEnd = slotStart.add(slotDuration);

          for (final appt in dayAppointments) {
            if (excludeAppointmentId != null &&
                appt.id == excludeAppointmentId) {
              continue;
            }
            if (appt.syncStatus == AppointmentSyncStatus.pendingDelete) {
              continue;
            }
            final apptStart = appt.startTime.toLocal();
            final apptEnd = appt.endTime.toLocal();
            final overlaps =
                slotStart.isBefore(apptEnd) && slotEnd.isAfter(apptStart);
            if (overlaps) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);
  }

  static String formatMinutesOfDay(int minutesFromMidnight) {
    final hour = (minutesFromMidnight ~/ 60).toString().padLeft(2, '0');
    final minute = (minutesFromMidnight % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ScheduleConfig ||
        other.defaultSlotDurationMinutes != defaultSlotDurationMinutes ||
        other.slotMinutesFromMidnight.length !=
            slotMinutesFromMidnight.length) {
      return false;
    }
    for (var i = 0; i < slotMinutesFromMidnight.length; i++) {
      if (other.slotMinutesFromMidnight[i] != slotMinutesFromMidnight[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    defaultSlotDurationMinutes,
    Object.hashAll(slotMinutesFromMidnight),
  );
}

/// Complete domain view of user preferences stored locally and synced in Firestore.
class AppPreferencesEntity {
  const AppPreferencesEntity({
    this.clientLabelPlural = AppConstants.defaultClientLabelPlural,
    this.clientLabelSingular = AppConstants.defaultClientLabelSingular,
    this.services = const <CustomServiceItem>[],
    this.schedule = const ScheduleConfig(),
    required this.updatedAt,
  });

  final String clientLabelPlural;
  final String clientLabelSingular;
  final List<CustomServiceItem> services;
  final ScheduleConfig schedule;
  final DateTime updatedAt;

  AppPreferencesEntity copyWith({
    String? clientLabelPlural,
    String? clientLabelSingular,
    List<CustomServiceItem>? services,
    ScheduleConfig? schedule,
    DateTime? updatedAt,
  }) {
    return AppPreferencesEntity(
      clientLabelPlural: clientLabelPlural ?? this.clientLabelPlural,
      clientLabelSingular: clientLabelSingular ?? this.clientLabelSingular,
      services: services ?? this.services,
      schedule: schedule ?? this.schedule,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
