// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ClientsTable extends Clients with TableInfo<$ClientsTable, Client> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _googleContactIdMeta = const VerificationMeta(
    'googleContactId',
  );
  @override
  late final GeneratedColumn<String> googleContactId = GeneratedColumn<String>(
    'google_contact_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawPhoneMeta = const VerificationMeta(
    'rawPhone',
  );
  @override
  late final GeneratedColumn<String> rawPhone = GeneratedColumn<String>(
    'raw_phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneE164Meta = const VerificationMeta(
    'phoneE164',
  );
  @override
  late final GeneratedColumn<String> phoneE164 = GeneratedColumn<String>(
    'phone_e164',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    googleContactId,
    name,
    rawPhone,
    phoneE164,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'clients';
  @override
  VerificationContext validateIntegrity(
    Insertable<Client> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('google_contact_id')) {
      context.handle(
        _googleContactIdMeta,
        googleContactId.isAcceptableOrUnknown(
          data['google_contact_id']!,
          _googleContactIdMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('raw_phone')) {
      context.handle(
        _rawPhoneMeta,
        rawPhone.isAcceptableOrUnknown(data['raw_phone']!, _rawPhoneMeta),
      );
    } else if (isInserting) {
      context.missing(_rawPhoneMeta);
    }
    if (data.containsKey('phone_e164')) {
      context.handle(
        _phoneE164Meta,
        phoneE164.isAcceptableOrUnknown(data['phone_e164']!, _phoneE164Meta),
      );
    } else if (isInserting) {
      context.missing(_phoneE164Meta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Client map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Client(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      googleContactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}google_contact_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      rawPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_phone'],
      )!,
      phoneE164: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_e164'],
      )!,
    );
  }

  @override
  $ClientsTable createAlias(String alias) {
    return $ClientsTable(attachedDatabase, alias);
  }
}

class Client extends DataClass implements Insertable<Client> {
  final int id;
  final String? googleContactId;
  final String name;
  final String rawPhone;
  final String phoneE164;
  const Client({
    required this.id,
    this.googleContactId,
    required this.name,
    required this.rawPhone,
    required this.phoneE164,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || googleContactId != null) {
      map['google_contact_id'] = Variable<String>(googleContactId);
    }
    map['name'] = Variable<String>(name);
    map['raw_phone'] = Variable<String>(rawPhone);
    map['phone_e164'] = Variable<String>(phoneE164);
    return map;
  }

  ClientsCompanion toCompanion(bool nullToAbsent) {
    return ClientsCompanion(
      id: Value(id),
      googleContactId: googleContactId == null && nullToAbsent
          ? const Value.absent()
          : Value(googleContactId),
      name: Value(name),
      rawPhone: Value(rawPhone),
      phoneE164: Value(phoneE164),
    );
  }

  factory Client.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Client(
      id: serializer.fromJson<int>(json['id']),
      googleContactId: serializer.fromJson<String?>(json['googleContactId']),
      name: serializer.fromJson<String>(json['name']),
      rawPhone: serializer.fromJson<String>(json['rawPhone']),
      phoneE164: serializer.fromJson<String>(json['phoneE164']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'googleContactId': serializer.toJson<String?>(googleContactId),
      'name': serializer.toJson<String>(name),
      'rawPhone': serializer.toJson<String>(rawPhone),
      'phoneE164': serializer.toJson<String>(phoneE164),
    };
  }

  Client copyWith({
    int? id,
    Value<String?> googleContactId = const Value.absent(),
    String? name,
    String? rawPhone,
    String? phoneE164,
  }) => Client(
    id: id ?? this.id,
    googleContactId: googleContactId.present
        ? googleContactId.value
        : this.googleContactId,
    name: name ?? this.name,
    rawPhone: rawPhone ?? this.rawPhone,
    phoneE164: phoneE164 ?? this.phoneE164,
  );
  Client copyWithCompanion(ClientsCompanion data) {
    return Client(
      id: data.id.present ? data.id.value : this.id,
      googleContactId: data.googleContactId.present
          ? data.googleContactId.value
          : this.googleContactId,
      name: data.name.present ? data.name.value : this.name,
      rawPhone: data.rawPhone.present ? data.rawPhone.value : this.rawPhone,
      phoneE164: data.phoneE164.present ? data.phoneE164.value : this.phoneE164,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Client(')
          ..write('id: $id, ')
          ..write('googleContactId: $googleContactId, ')
          ..write('name: $name, ')
          ..write('rawPhone: $rawPhone, ')
          ..write('phoneE164: $phoneE164')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, googleContactId, name, rawPhone, phoneE164);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Client &&
          other.id == this.id &&
          other.googleContactId == this.googleContactId &&
          other.name == this.name &&
          other.rawPhone == this.rawPhone &&
          other.phoneE164 == this.phoneE164);
}

class ClientsCompanion extends UpdateCompanion<Client> {
  final Value<int> id;
  final Value<String?> googleContactId;
  final Value<String> name;
  final Value<String> rawPhone;
  final Value<String> phoneE164;
  const ClientsCompanion({
    this.id = const Value.absent(),
    this.googleContactId = const Value.absent(),
    this.name = const Value.absent(),
    this.rawPhone = const Value.absent(),
    this.phoneE164 = const Value.absent(),
  });
  ClientsCompanion.insert({
    this.id = const Value.absent(),
    this.googleContactId = const Value.absent(),
    required String name,
    required String rawPhone,
    required String phoneE164,
  }) : name = Value(name),
       rawPhone = Value(rawPhone),
       phoneE164 = Value(phoneE164);
  static Insertable<Client> custom({
    Expression<int>? id,
    Expression<String>? googleContactId,
    Expression<String>? name,
    Expression<String>? rawPhone,
    Expression<String>? phoneE164,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (googleContactId != null) 'google_contact_id': googleContactId,
      if (name != null) 'name': name,
      if (rawPhone != null) 'raw_phone': rawPhone,
      if (phoneE164 != null) 'phone_e164': phoneE164,
    });
  }

  ClientsCompanion copyWith({
    Value<int>? id,
    Value<String?>? googleContactId,
    Value<String>? name,
    Value<String>? rawPhone,
    Value<String>? phoneE164,
  }) {
    return ClientsCompanion(
      id: id ?? this.id,
      googleContactId: googleContactId ?? this.googleContactId,
      name: name ?? this.name,
      rawPhone: rawPhone ?? this.rawPhone,
      phoneE164: phoneE164 ?? this.phoneE164,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (googleContactId.present) {
      map['google_contact_id'] = Variable<String>(googleContactId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rawPhone.present) {
      map['raw_phone'] = Variable<String>(rawPhone.value);
    }
    if (phoneE164.present) {
      map['phone_e164'] = Variable<String>(phoneE164.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientsCompanion(')
          ..write('id: $id, ')
          ..write('googleContactId: $googleContactId, ')
          ..write('name: $name, ')
          ..write('rawPhone: $rawPhone, ')
          ..write('phoneE164: $phoneE164')
          ..write(')'))
        .toString();
  }
}

class $AppointmentsTable extends Appointments
    with TableInfo<$AppointmentsTable, Appointment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppointmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _syncIdMeta = const VerificationMeta('syncId');
  @override
  late final GeneratedColumn<String> syncId = GeneratedColumn<String>(
    'sync_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _googleCalendarEventIdMeta =
      const VerificationMeta('googleCalendarEventId');
  @override
  late final GeneratedColumn<String> googleCalendarEventId =
      GeneratedColumn<String>(
        'google_calendar_event_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
      );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<int> clientId = GeneratedColumn<int>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES clients (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
    'end_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reminderSentMeta = const VerificationMeta(
    'reminderSent',
  );
  @override
  late final GeneratedColumn<bool> reminderSent = GeneratedColumn<bool>(
    'reminder_sent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reminder_sent" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(AppConstants.syncStatusSynced),
  );
  static const VerificationMeta _lastModifiedMeta = const VerificationMeta(
    'lastModified',
  );
  @override
  late final GeneratedColumn<DateTime> lastModified = GeneratedColumn<DateTime>(
    'last_modified',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    syncId,
    googleCalendarEventId,
    clientId,
    title,
    notes,
    startTime,
    endTime,
    reminderSent,
    syncStatus,
    lastModified,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'appointments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Appointment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_id')) {
      context.handle(
        _syncIdMeta,
        syncId.isAcceptableOrUnknown(data['sync_id']!, _syncIdMeta),
      );
    } else if (isInserting) {
      context.missing(_syncIdMeta);
    }
    if (data.containsKey('google_calendar_event_id')) {
      context.handle(
        _googleCalendarEventIdMeta,
        googleCalendarEventId.isAcceptableOrUnknown(
          data['google_calendar_event_id']!,
          _googleCalendarEventIdMeta,
        ),
      );
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_endTimeMeta);
    }
    if (data.containsKey('reminder_sent')) {
      context.handle(
        _reminderSentMeta,
        reminderSent.isAcceptableOrUnknown(
          data['reminder_sent']!,
          _reminderSentMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('last_modified')) {
      context.handle(
        _lastModifiedMeta,
        lastModified.isAcceptableOrUnknown(
          data['last_modified']!,
          _lastModifiedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Appointment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Appointment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      syncId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_id'],
      )!,
      googleCalendarEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}google_calendar_event_id'],
      ),
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}client_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_time'],
      )!,
      reminderSent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reminder_sent'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_modified'],
      )!,
    );
  }

  @override
  $AppointmentsTable createAlias(String alias) {
    return $AppointmentsTable(attachedDatabase, alias);
  }
}

class Appointment extends DataClass implements Insertable<Appointment> {
  final int id;
  final String syncId;
  final String? googleCalendarEventId;
  final int clientId;
  final String title;
  final String? notes;
  final DateTime startTime;
  final DateTime endTime;
  final bool reminderSent;
  final String syncStatus;
  final DateTime lastModified;
  const Appointment({
    required this.id,
    required this.syncId,
    this.googleCalendarEventId,
    required this.clientId,
    required this.title,
    this.notes,
    required this.startTime,
    required this.endTime,
    required this.reminderSent,
    required this.syncStatus,
    required this.lastModified,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sync_id'] = Variable<String>(syncId);
    if (!nullToAbsent || googleCalendarEventId != null) {
      map['google_calendar_event_id'] = Variable<String>(googleCalendarEventId);
    }
    map['client_id'] = Variable<int>(clientId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['start_time'] = Variable<DateTime>(startTime);
    map['end_time'] = Variable<DateTime>(endTime);
    map['reminder_sent'] = Variable<bool>(reminderSent);
    map['sync_status'] = Variable<String>(syncStatus);
    map['last_modified'] = Variable<DateTime>(lastModified);
    return map;
  }

  AppointmentsCompanion toCompanion(bool nullToAbsent) {
    return AppointmentsCompanion(
      id: Value(id),
      syncId: Value(syncId),
      googleCalendarEventId: googleCalendarEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(googleCalendarEventId),
      clientId: Value(clientId),
      title: Value(title),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      startTime: Value(startTime),
      endTime: Value(endTime),
      reminderSent: Value(reminderSent),
      syncStatus: Value(syncStatus),
      lastModified: Value(lastModified),
    );
  }

  factory Appointment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Appointment(
      id: serializer.fromJson<int>(json['id']),
      syncId: serializer.fromJson<String>(json['syncId']),
      googleCalendarEventId: serializer.fromJson<String?>(
        json['googleCalendarEventId'],
      ),
      clientId: serializer.fromJson<int>(json['clientId']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String?>(json['notes']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      endTime: serializer.fromJson<DateTime>(json['endTime']),
      reminderSent: serializer.fromJson<bool>(json['reminderSent']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      lastModified: serializer.fromJson<DateTime>(json['lastModified']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncId': serializer.toJson<String>(syncId),
      'googleCalendarEventId': serializer.toJson<String?>(
        googleCalendarEventId,
      ),
      'clientId': serializer.toJson<int>(clientId),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String?>(notes),
      'startTime': serializer.toJson<DateTime>(startTime),
      'endTime': serializer.toJson<DateTime>(endTime),
      'reminderSent': serializer.toJson<bool>(reminderSent),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'lastModified': serializer.toJson<DateTime>(lastModified),
    };
  }

  Appointment copyWith({
    int? id,
    String? syncId,
    Value<String?> googleCalendarEventId = const Value.absent(),
    int? clientId,
    String? title,
    Value<String?> notes = const Value.absent(),
    DateTime? startTime,
    DateTime? endTime,
    bool? reminderSent,
    String? syncStatus,
    DateTime? lastModified,
  }) => Appointment(
    id: id ?? this.id,
    syncId: syncId ?? this.syncId,
    googleCalendarEventId: googleCalendarEventId.present
        ? googleCalendarEventId.value
        : this.googleCalendarEventId,
    clientId: clientId ?? this.clientId,
    title: title ?? this.title,
    notes: notes.present ? notes.value : this.notes,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    reminderSent: reminderSent ?? this.reminderSent,
    syncStatus: syncStatus ?? this.syncStatus,
    lastModified: lastModified ?? this.lastModified,
  );
  Appointment copyWithCompanion(AppointmentsCompanion data) {
    return Appointment(
      id: data.id.present ? data.id.value : this.id,
      syncId: data.syncId.present ? data.syncId.value : this.syncId,
      googleCalendarEventId: data.googleCalendarEventId.present
          ? data.googleCalendarEventId.value
          : this.googleCalendarEventId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      reminderSent: data.reminderSent.present
          ? data.reminderSent.value
          : this.reminderSent,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Appointment(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('googleCalendarEventId: $googleCalendarEventId, ')
          ..write('clientId: $clientId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('reminderSent: $reminderSent, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('lastModified: $lastModified')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    syncId,
    googleCalendarEventId,
    clientId,
    title,
    notes,
    startTime,
    endTime,
    reminderSent,
    syncStatus,
    lastModified,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Appointment &&
          other.id == this.id &&
          other.syncId == this.syncId &&
          other.googleCalendarEventId == this.googleCalendarEventId &&
          other.clientId == this.clientId &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.reminderSent == this.reminderSent &&
          other.syncStatus == this.syncStatus &&
          other.lastModified == this.lastModified);
}

class AppointmentsCompanion extends UpdateCompanion<Appointment> {
  final Value<int> id;
  final Value<String> syncId;
  final Value<String?> googleCalendarEventId;
  final Value<int> clientId;
  final Value<String> title;
  final Value<String?> notes;
  final Value<DateTime> startTime;
  final Value<DateTime> endTime;
  final Value<bool> reminderSent;
  final Value<String> syncStatus;
  final Value<DateTime> lastModified;
  const AppointmentsCompanion({
    this.id = const Value.absent(),
    this.syncId = const Value.absent(),
    this.googleCalendarEventId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.reminderSent = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.lastModified = const Value.absent(),
  });
  AppointmentsCompanion.insert({
    this.id = const Value.absent(),
    required String syncId,
    this.googleCalendarEventId = const Value.absent(),
    required int clientId,
    required String title,
    this.notes = const Value.absent(),
    required DateTime startTime,
    required DateTime endTime,
    this.reminderSent = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required DateTime lastModified,
  }) : syncId = Value(syncId),
       clientId = Value(clientId),
       title = Value(title),
       startTime = Value(startTime),
       endTime = Value(endTime),
       lastModified = Value(lastModified);
  static Insertable<Appointment> custom({
    Expression<int>? id,
    Expression<String>? syncId,
    Expression<String>? googleCalendarEventId,
    Expression<int>? clientId,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<bool>? reminderSent,
    Expression<String>? syncStatus,
    Expression<DateTime>? lastModified,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncId != null) 'sync_id': syncId,
      if (googleCalendarEventId != null)
        'google_calendar_event_id': googleCalendarEventId,
      if (clientId != null) 'client_id': clientId,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (reminderSent != null) 'reminder_sent': reminderSent,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (lastModified != null) 'last_modified': lastModified,
    });
  }

  AppointmentsCompanion copyWith({
    Value<int>? id,
    Value<String>? syncId,
    Value<String?>? googleCalendarEventId,
    Value<int>? clientId,
    Value<String>? title,
    Value<String?>? notes,
    Value<DateTime>? startTime,
    Value<DateTime>? endTime,
    Value<bool>? reminderSent,
    Value<String>? syncStatus,
    Value<DateTime>? lastModified,
  }) {
    return AppointmentsCompanion(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      googleCalendarEventId:
          googleCalendarEventId ?? this.googleCalendarEventId,
      clientId: clientId ?? this.clientId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      reminderSent: reminderSent ?? this.reminderSent,
      syncStatus: syncStatus ?? this.syncStatus,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncId.present) {
      map['sync_id'] = Variable<String>(syncId.value);
    }
    if (googleCalendarEventId.present) {
      map['google_calendar_event_id'] = Variable<String>(
        googleCalendarEventId.value,
      );
    }
    if (clientId.present) {
      map['client_id'] = Variable<int>(clientId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (reminderSent.present) {
      map['reminder_sent'] = Variable<bool>(reminderSent.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<DateTime>(lastModified.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppointmentsCompanion(')
          ..write('id: $id, ')
          ..write('syncId: $syncId, ')
          ..write('googleCalendarEventId: $googleCalendarEventId, ')
          ..write('clientId: $clientId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('reminderSent: $reminderSent, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('lastModified: $lastModified')
          ..write(')'))
        .toString();
  }
}

class $SyncMetadataTable extends SyncMetadata
    with TableInfo<$SyncMetadataTable, SyncMetadataRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _syncTokenMeta = const VerificationMeta(
    'syncToken',
  );
  @override
  late final GeneratedColumn<String> syncToken = GeneratedColumn<String>(
    'sync_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncTimestampMeta = const VerificationMeta(
    'lastSyncTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncTimestamp =
      GeneratedColumn<DateTime>(
        'last_sync_timestamp',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [id, syncToken, lastSyncTimestamp];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetadataRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sync_token')) {
      context.handle(
        _syncTokenMeta,
        syncToken.isAcceptableOrUnknown(data['sync_token']!, _syncTokenMeta),
      );
    }
    if (data.containsKey('last_sync_timestamp')) {
      context.handle(
        _lastSyncTimestampMeta,
        lastSyncTimestamp.isAcceptableOrUnknown(
          data['last_sync_timestamp']!,
          _lastSyncTimestampMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncMetadataRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetadataRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      syncToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_token'],
      ),
      lastSyncTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_timestamp'],
      ),
    );
  }

  @override
  $SyncMetadataTable createAlias(String alias) {
    return $SyncMetadataTable(attachedDatabase, alias);
  }
}

class SyncMetadataRecord extends DataClass
    implements Insertable<SyncMetadataRecord> {
  final int id;
  final String? syncToken;
  final DateTime? lastSyncTimestamp;
  const SyncMetadataRecord({
    required this.id,
    this.syncToken,
    this.lastSyncTimestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || syncToken != null) {
      map['sync_token'] = Variable<String>(syncToken);
    }
    if (!nullToAbsent || lastSyncTimestamp != null) {
      map['last_sync_timestamp'] = Variable<DateTime>(lastSyncTimestamp);
    }
    return map;
  }

  SyncMetadataCompanion toCompanion(bool nullToAbsent) {
    return SyncMetadataCompanion(
      id: Value(id),
      syncToken: syncToken == null && nullToAbsent
          ? const Value.absent()
          : Value(syncToken),
      lastSyncTimestamp: lastSyncTimestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncTimestamp),
    );
  }

  factory SyncMetadataRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetadataRecord(
      id: serializer.fromJson<int>(json['id']),
      syncToken: serializer.fromJson<String?>(json['syncToken']),
      lastSyncTimestamp: serializer.fromJson<DateTime?>(
        json['lastSyncTimestamp'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'syncToken': serializer.toJson<String?>(syncToken),
      'lastSyncTimestamp': serializer.toJson<DateTime?>(lastSyncTimestamp),
    };
  }

  SyncMetadataRecord copyWith({
    int? id,
    Value<String?> syncToken = const Value.absent(),
    Value<DateTime?> lastSyncTimestamp = const Value.absent(),
  }) => SyncMetadataRecord(
    id: id ?? this.id,
    syncToken: syncToken.present ? syncToken.value : this.syncToken,
    lastSyncTimestamp: lastSyncTimestamp.present
        ? lastSyncTimestamp.value
        : this.lastSyncTimestamp,
  );
  SyncMetadataRecord copyWithCompanion(SyncMetadataCompanion data) {
    return SyncMetadataRecord(
      id: data.id.present ? data.id.value : this.id,
      syncToken: data.syncToken.present ? data.syncToken.value : this.syncToken,
      lastSyncTimestamp: data.lastSyncTimestamp.present
          ? data.lastSyncTimestamp.value
          : this.lastSyncTimestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataRecord(')
          ..write('id: $id, ')
          ..write('syncToken: $syncToken, ')
          ..write('lastSyncTimestamp: $lastSyncTimestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, syncToken, lastSyncTimestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetadataRecord &&
          other.id == this.id &&
          other.syncToken == this.syncToken &&
          other.lastSyncTimestamp == this.lastSyncTimestamp);
}

class SyncMetadataCompanion extends UpdateCompanion<SyncMetadataRecord> {
  final Value<int> id;
  final Value<String?> syncToken;
  final Value<DateTime?> lastSyncTimestamp;
  const SyncMetadataCompanion({
    this.id = const Value.absent(),
    this.syncToken = const Value.absent(),
    this.lastSyncTimestamp = const Value.absent(),
  });
  SyncMetadataCompanion.insert({
    this.id = const Value.absent(),
    this.syncToken = const Value.absent(),
    this.lastSyncTimestamp = const Value.absent(),
  });
  static Insertable<SyncMetadataRecord> custom({
    Expression<int>? id,
    Expression<String>? syncToken,
    Expression<DateTime>? lastSyncTimestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (syncToken != null) 'sync_token': syncToken,
      if (lastSyncTimestamp != null) 'last_sync_timestamp': lastSyncTimestamp,
    });
  }

  SyncMetadataCompanion copyWith({
    Value<int>? id,
    Value<String?>? syncToken,
    Value<DateTime?>? lastSyncTimestamp,
  }) {
    return SyncMetadataCompanion(
      id: id ?? this.id,
      syncToken: syncToken ?? this.syncToken,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (syncToken.present) {
      map['sync_token'] = Variable<String>(syncToken.value);
    }
    if (lastSyncTimestamp.present) {
      map['last_sync_timestamp'] = Variable<DateTime>(lastSyncTimestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataCompanion(')
          ..write('id: $id, ')
          ..write('syncToken: $syncToken, ')
          ..write('lastSyncTimestamp: $lastSyncTimestamp')
          ..write(')'))
        .toString();
  }
}

class $ReminderTemplatesTable extends ReminderTemplates
    with TableInfo<$ReminderTemplatesTable, ReminderTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReminderTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, body, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reminder_templates';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReminderTemplate> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReminderTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReminderTemplate(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReminderTemplatesTable createAlias(String alias) {
    return $ReminderTemplatesTable(attachedDatabase, alias);
  }
}

class ReminderTemplate extends DataClass
    implements Insertable<ReminderTemplate> {
  final String id;
  final String name;
  final String body;
  final DateTime updatedAt;
  const ReminderTemplate({
    required this.id,
    required this.name,
    required this.body,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['body'] = Variable<String>(body);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReminderTemplatesCompanion toCompanion(bool nullToAbsent) {
    return ReminderTemplatesCompanion(
      id: Value(id),
      name: Value(name),
      body: Value(body),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReminderTemplate.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReminderTemplate(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      body: serializer.fromJson<String>(json['body']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'body': serializer.toJson<String>(body),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReminderTemplate copyWith({
    String? id,
    String? name,
    String? body,
    DateTime? updatedAt,
  }) => ReminderTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    body: body ?? this.body,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReminderTemplate copyWithCompanion(ReminderTemplatesCompanion data) {
    return ReminderTemplate(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      body: data.body.present ? data.body.value : this.body,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReminderTemplate(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, body, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReminderTemplate &&
          other.id == this.id &&
          other.name == this.name &&
          other.body == this.body &&
          other.updatedAt == this.updatedAt);
}

class ReminderTemplatesCompanion extends UpdateCompanion<ReminderTemplate> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> body;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReminderTemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.body = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReminderTemplatesCompanion.insert({
    required String id,
    required String name,
    required String body,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       body = Value(body),
       updatedAt = Value(updatedAt);
  static Insertable<ReminderTemplate> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? body,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (body != null) 'body': body,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReminderTemplatesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? body,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReminderTemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      body: body ?? this.body,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReminderTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('body: $body, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ClientsTable clients = $ClientsTable(this);
  late final $AppointmentsTable appointments = $AppointmentsTable(this);
  late final $SyncMetadataTable syncMetadata = $SyncMetadataTable(this);
  late final $ReminderTemplatesTable reminderTemplates =
      $ReminderTemplatesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    clients,
    appointments,
    syncMetadata,
    reminderTemplates,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'clients',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('appointments', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ClientsTableCreateCompanionBuilder = ClientsCompanion Function({
  Value<int> id,
  Value<String?> googleContactId,
  required String name,
  required String rawPhone,
  required String phoneE164,
});
typedef $$ClientsTableUpdateCompanionBuilder = ClientsCompanion Function({
  Value<int> id,
  Value<String?> googleContactId,
  Value<String> name,
  Value<String> rawPhone,
  Value<String> phoneE164,
});

final class $$ClientsTableReferences
    extends BaseReferences<_$AppDatabase, $ClientsTable, Client> {
  $$ClientsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AppointmentsTable, List<Appointment>>
  _appointmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.appointments,
    aliasName: 'clients__id__appointments__client_id',
  );

  $$AppointmentsTableProcessedTableManager get appointmentsRefs {
    final manager = $$AppointmentsTableTableManager(
      $_db,
      $_db.appointments,
    ).filter((f) => f.clientId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_appointmentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ClientsTableFilterComposer
    extends Composer<_$AppDatabase, $ClientsTable> {
  $$ClientsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get googleContactId => $composableBuilder(
    column: $table.googleContactId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawPhone => $composableBuilder(
    column: $table.rawPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneE164 => $composableBuilder(
    column: $table.phoneE164,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> appointmentsRefs(
    Expression<bool> Function($$AppointmentsTableFilterComposer f) f,
  ) {
    final $$AppointmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.appointments,
      getReferencedColumn: (t) => t.clientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AppointmentsTableFilterComposer(
            $db: $db,
            $table: $db.appointments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClientsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClientsTable> {
  $$ClientsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get googleContactId => $composableBuilder(
    column: $table.googleContactId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawPhone => $composableBuilder(
    column: $table.rawPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneE164 => $composableBuilder(
    column: $table.phoneE164,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClientsTable> {
  $$ClientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get googleContactId => $composableBuilder(
    column: $table.googleContactId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get rawPhone =>
      $composableBuilder(column: $table.rawPhone, builder: (column) => column);

  GeneratedColumn<String> get phoneE164 =>
      $composableBuilder(column: $table.phoneE164, builder: (column) => column);

  Expression<T> appointmentsRefs<T extends Object>(
    Expression<T> Function($$AppointmentsTableAnnotationComposer a) f,
  ) {
    final $$AppointmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.appointments,
      getReferencedColumn: (t) => t.clientId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AppointmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.appointments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ClientsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClientsTable,
          Client,
          $$ClientsTableFilterComposer,
          $$ClientsTableOrderingComposer,
          $$ClientsTableAnnotationComposer,
          $$ClientsTableCreateCompanionBuilder,
          $$ClientsTableUpdateCompanionBuilder,
          (Client, $$ClientsTableReferences),
          Client,
          PrefetchHooks Function({bool appointmentsRefs})
        > {
  $$ClientsTableTableManager(_$AppDatabase db, $ClientsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> googleContactId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> rawPhone = const Value.absent(),
                Value<String> phoneE164 = const Value.absent(),
              }) => ClientsCompanion(
                id: id,
                googleContactId: googleContactId,
                name: name,
                rawPhone: rawPhone,
                phoneE164: phoneE164,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> googleContactId = const Value.absent(),
                required String name,
                required String rawPhone,
                required String phoneE164,
              }) => ClientsCompanion.insert(
                id: id,
                googleContactId: googleContactId,
                name: name,
                rawPhone: rawPhone,
                phoneE164: phoneE164,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ClientsTable, Client>(table),
                  $$ClientsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({appointmentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (appointmentsRefs) db.appointments],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (appointmentsRefs)
                    await $_getPrefetchedDataByColumns<
                      Client,
                      $ClientsTable,
                      Appointment,
                      $AppointmentsTable
                    >(
                      currentTable: table,
                      referencedTable: $$ClientsTableReferences
                          ._appointmentsRefsTable(db),
                      managerFromTypedResult: (p0) => $$ClientsTableReferences(
                        db,
                        table,
                        p0,
                      ).appointmentsRefs,
                      currentColumn: 'id',
                      referencedColumn: 'client_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ClientsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClientsTable,
      Client,
      $$ClientsTableFilterComposer,
      $$ClientsTableOrderingComposer,
      $$ClientsTableAnnotationComposer,
      $$ClientsTableCreateCompanionBuilder,
      $$ClientsTableUpdateCompanionBuilder,
      (Client, $$ClientsTableReferences),
      Client,
      PrefetchHooks Function({bool appointmentsRefs})
    >;
typedef $$AppointmentsTableCreateCompanionBuilder =
    AppointmentsCompanion Function({
      Value<int> id,
      required String syncId,
      Value<String?> googleCalendarEventId,
      required int clientId,
      required String title,
      Value<String?> notes,
      required DateTime startTime,
      required DateTime endTime,
      Value<bool> reminderSent,
      Value<String> syncStatus,
      required DateTime lastModified,
    });
typedef $$AppointmentsTableUpdateCompanionBuilder =
    AppointmentsCompanion Function({
      Value<int> id,
      Value<String> syncId,
      Value<String?> googleCalendarEventId,
      Value<int> clientId,
      Value<String> title,
      Value<String?> notes,
      Value<DateTime> startTime,
      Value<DateTime> endTime,
      Value<bool> reminderSent,
      Value<String> syncStatus,
      Value<DateTime> lastModified,
    });

final class $$AppointmentsTableReferences
    extends BaseReferences<_$AppDatabase, $AppointmentsTable, Appointment> {
  $$AppointmentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ClientsTable _clientIdTable(_$AppDatabase db) =>
      db.clients.createAlias('appointments__client_id__clients__id');

  $$ClientsTableProcessedTableManager get clientId {
    final $_column = $_itemColumn<int>('client_id')!;

    final manager = $$ClientsTableTableManager(
      $_db,
      $_db.clients,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_clientIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AppointmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AppointmentsTable> {
  $$AppointmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get googleCalendarEventId => $composableBuilder(
    column: $table.googleCalendarEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reminderSent => $composableBuilder(
    column: $table.reminderSent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnFilters(column),
  );

  $$ClientsTableFilterComposer get clientId {
    final $$ClientsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.clients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientsTableFilterComposer(
            $db: $db,
            $table: $db.clients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppointmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppointmentsTable> {
  $$AppointmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncId => $composableBuilder(
    column: $table.syncId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get googleCalendarEventId => $composableBuilder(
    column: $table.googleCalendarEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reminderSent => $composableBuilder(
    column: $table.reminderSent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnOrderings(column),
  );

  $$ClientsTableOrderingComposer get clientId {
    final $$ClientsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.clients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientsTableOrderingComposer(
            $db: $db,
            $table: $db.clients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppointmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppointmentsTable> {
  $$AppointmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncId =>
      $composableBuilder(column: $table.syncId, builder: (column) => column);

  GeneratedColumn<String> get googleCalendarEventId => $composableBuilder(
    column: $table.googleCalendarEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<bool> get reminderSent => $composableBuilder(
    column: $table.reminderSent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => column,
  );

  $$ClientsTableAnnotationComposer get clientId {
    final $$ClientsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.clientId,
      referencedTable: $db.clients,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ClientsTableAnnotationComposer(
            $db: $db,
            $table: $db.clients,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppointmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppointmentsTable,
          Appointment,
          $$AppointmentsTableFilterComposer,
          $$AppointmentsTableOrderingComposer,
          $$AppointmentsTableAnnotationComposer,
          $$AppointmentsTableCreateCompanionBuilder,
          $$AppointmentsTableUpdateCompanionBuilder,
          (Appointment, $$AppointmentsTableReferences),
          Appointment,
          PrefetchHooks Function({bool clientId})
        > {
  $$AppointmentsTableTableManager(_$AppDatabase db, $AppointmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppointmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppointmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppointmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> syncId = const Value.absent(),
                Value<String?> googleCalendarEventId = const Value.absent(),
                Value<int> clientId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> startTime = const Value.absent(),
                Value<DateTime> endTime = const Value.absent(),
                Value<bool> reminderSent = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime> lastModified = const Value.absent(),
              }) => AppointmentsCompanion(
                id: id,
                syncId: syncId,
                googleCalendarEventId: googleCalendarEventId,
                clientId: clientId,
                title: title,
                notes: notes,
                startTime: startTime,
                endTime: endTime,
                reminderSent: reminderSent,
                syncStatus: syncStatus,
                lastModified: lastModified,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String syncId,
                Value<String?> googleCalendarEventId = const Value.absent(),
                required int clientId,
                required String title,
                Value<String?> notes = const Value.absent(),
                required DateTime startTime,
                required DateTime endTime,
                Value<bool> reminderSent = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                required DateTime lastModified,
              }) => AppointmentsCompanion.insert(
                id: id,
                syncId: syncId,
                googleCalendarEventId: googleCalendarEventId,
                clientId: clientId,
                title: title,
                notes: notes,
                startTime: startTime,
                endTime: endTime,
                reminderSent: reminderSent,
                syncStatus: syncStatus,
                lastModified: lastModified,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppointmentsTable, Appointment>(table),
                  $$AppointmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({clientId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (clientId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.clientId,
                        referencedTable: $$AppointmentsTableReferences
                            ._clientIdTable(db),
                        referencedColumn: $$AppointmentsTableReferences
                            ._clientIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AppointmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppointmentsTable,
      Appointment,
      $$AppointmentsTableFilterComposer,
      $$AppointmentsTableOrderingComposer,
      $$AppointmentsTableAnnotationComposer,
      $$AppointmentsTableCreateCompanionBuilder,
      $$AppointmentsTableUpdateCompanionBuilder,
      (Appointment, $$AppointmentsTableReferences),
      Appointment,
      PrefetchHooks Function({bool clientId})
    >;
typedef $$SyncMetadataTableCreateCompanionBuilder =
    SyncMetadataCompanion Function({
      Value<int> id,
      Value<String?> syncToken,
      Value<DateTime?> lastSyncTimestamp,
    });
typedef $$SyncMetadataTableUpdateCompanionBuilder =
    SyncMetadataCompanion Function({
      Value<int> id,
      Value<String?> syncToken,
      Value<DateTime?> lastSyncTimestamp,
    });

class $$SyncMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncToken => $composableBuilder(
    column: $table.syncToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncTimestamp => $composableBuilder(
    column: $table.lastSyncTimestamp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncToken => $composableBuilder(
    column: $table.syncToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncTimestamp => $composableBuilder(
    column: $table.lastSyncTimestamp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get syncToken =>
      $composableBuilder(column: $table.syncToken, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncTimestamp => $composableBuilder(
    column: $table.lastSyncTimestamp,
    builder: (column) => column,
  );
}

class $$SyncMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetadataTable,
          SyncMetadataRecord,
          $$SyncMetadataTableFilterComposer,
          $$SyncMetadataTableOrderingComposer,
          $$SyncMetadataTableAnnotationComposer,
          $$SyncMetadataTableCreateCompanionBuilder,
          $$SyncMetadataTableUpdateCompanionBuilder,
          (
            SyncMetadataRecord,
            BaseReferences<
              _$AppDatabase,
              $SyncMetadataTable,
              SyncMetadataRecord
            >,
          ),
          SyncMetadataRecord,
          PrefetchHooks Function()
        > {
  $$SyncMetadataTableTableManager(_$AppDatabase db, $SyncMetadataTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> syncToken = const Value.absent(),
                Value<DateTime?> lastSyncTimestamp = const Value.absent(),
              }) => SyncMetadataCompanion(
                id: id,
                syncToken: syncToken,
                lastSyncTimestamp: lastSyncTimestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> syncToken = const Value.absent(),
                Value<DateTime?> lastSyncTimestamp = const Value.absent(),
              }) => SyncMetadataCompanion.insert(
                id: id,
                syncToken: syncToken,
                lastSyncTimestamp: lastSyncTimestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMetadataTable, SyncMetadataRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncMetadataTable,
                    SyncMetadataRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetadataTable,
      SyncMetadataRecord,
      $$SyncMetadataTableFilterComposer,
      $$SyncMetadataTableOrderingComposer,
      $$SyncMetadataTableAnnotationComposer,
      $$SyncMetadataTableCreateCompanionBuilder,
      $$SyncMetadataTableUpdateCompanionBuilder,
      (
        SyncMetadataRecord,
        BaseReferences<_$AppDatabase, $SyncMetadataTable, SyncMetadataRecord>,
      ),
      SyncMetadataRecord,
      PrefetchHooks Function()
    >;
typedef $$ReminderTemplatesTableCreateCompanionBuilder =
    ReminderTemplatesCompanion Function({
      required String id,
      required String name,
      required String body,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReminderTemplatesTableUpdateCompanionBuilder =
    ReminderTemplatesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> body,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ReminderTemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $ReminderTemplatesTable> {
  $$ReminderTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReminderTemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReminderTemplatesTable> {
  $$ReminderTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReminderTemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReminderTemplatesTable> {
  $$ReminderTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReminderTemplatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReminderTemplatesTable,
          ReminderTemplate,
          $$ReminderTemplatesTableFilterComposer,
          $$ReminderTemplatesTableOrderingComposer,
          $$ReminderTemplatesTableAnnotationComposer,
          $$ReminderTemplatesTableCreateCompanionBuilder,
          $$ReminderTemplatesTableUpdateCompanionBuilder,
          (
            ReminderTemplate,
            BaseReferences<
              _$AppDatabase,
              $ReminderTemplatesTable,
              ReminderTemplate
            >,
          ),
          ReminderTemplate,
          PrefetchHooks Function()
        > {
  $$ReminderTemplatesTableTableManager(
    _$AppDatabase db,
    $ReminderTemplatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReminderTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReminderTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReminderTemplatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReminderTemplatesCompanion(
                id: id,
                name: name,
                body: body,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String body,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReminderTemplatesCompanion.insert(
                id: id,
                name: name,
                body: body,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReminderTemplatesTable, ReminderTemplate>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReminderTemplatesTable,
                    ReminderTemplate
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReminderTemplatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReminderTemplatesTable,
      ReminderTemplate,
      $$ReminderTemplatesTableFilterComposer,
      $$ReminderTemplatesTableOrderingComposer,
      $$ReminderTemplatesTableAnnotationComposer,
      $$ReminderTemplatesTableCreateCompanionBuilder,
      $$ReminderTemplatesTableUpdateCompanionBuilder,
      (
        ReminderTemplate,
        BaseReferences<
          _$AppDatabase,
          $ReminderTemplatesTable,
          ReminderTemplate
        >,
      ),
      ReminderTemplate,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ClientsTableTableManager get clients =>
      $$ClientsTableTableManager(_db, _db.clients);
  $$AppointmentsTableTableManager get appointments =>
      $$AppointmentsTableTableManager(_db, _db.appointments);
  $$SyncMetadataTableTableManager get syncMetadata =>
      $$SyncMetadataTableTableManager(_db, _db.syncMetadata);
  $$ReminderTemplatesTableTableManager get reminderTemplates =>
      $$ReminderTemplatesTableTableManager(_db, _db.reminderTemplates);
}
