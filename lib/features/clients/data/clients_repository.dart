import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/data/local_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';
import 'package:nudge/features/clients/data/google_drive_files_datasource.dart';
import 'package:nudge/features/clients/domain/entities/client_entity.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Repository managing client/patient profiles, general notes, and attached
/// photos or PDFs synchronized across devices via Cloud Firestore + Google Drive.
class ClientsRepository {
  ClientsRepository(
    this._db, {
    required LocalAppointmentsDatasource localAppointmentsDatasource,
    required FirestoreSyncDatasource firestoreDatasource,
    required GoogleDriveFilesDatasource driveDatasource,
    String? Function()? currentUserId,
    Future<bool> Function()? isOnline,
    Future<Directory> Function()? attachmentsDirectoryProvider,
  }) : _localAppointments = localAppointmentsDatasource,
       _firestore = firestoreDatasource,
       _drive = driveDatasource,
       _userIdProvider = currentUserId,
       _onlineCheck = isOnline,
       _attachmentsDirProvider =
           attachmentsDirectoryProvider ?? _defaultAttachmentsDirectory;

  final AppDatabase _db;
  final LocalAppointmentsDatasource _localAppointments;
  final FirestoreSyncDatasource _firestore;
  final GoogleDriveFilesDatasource _drive;
  final String? Function()? _userIdProvider;
  final Future<bool> Function()? _onlineCheck;
  final Future<Directory> Function() _attachmentsDirProvider;

  static Future<Directory> _defaultAttachmentsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'nudge_attachments'));
    await dir.create(recursive: true);
    return dir;
  }

  Stream<List<ClientEntity>> watchClients() {
    return _db
        .customSelect(
          '''
          SELECT
            c.*,
            (
              SELECT COUNT(*)
              FROM appointments a
              WHERE a.client_id = c.id
                AND a.sync_status != ?
            ) AS appointment_count,
            (
              SELECT COUNT(*)
              FROM client_attachments f
              WHERE f.client_id = c.id
                AND f.sync_status != ?
            ) AS attachment_count
          FROM clients c
          WHERE c.sync_status != ?
          ORDER BY c.name COLLATE NOCASE ASC
          ''',
          variables: <Variable<Object>>[
            Variable.withString(AppConstants.syncStatusPendingDelete),
            Variable.withString(AppConstants.syncStatusPendingDelete),
            Variable.withString(AppConstants.syncStatusPendingDelete),
          ],
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.clients,
            _db.appointments,
            _db.clientAttachments,
          },
        )
        .watch()
        .map(
          (List<QueryRow> rows) =>
              rows.map(_mapClientQueryRow).toList(growable: false),
        );
  }

  Stream<ClientEntity?> watchClientById(int clientId) {
    return _db
        .customSelect(
          '''
          SELECT
            c.*,
            (
              SELECT COUNT(*)
              FROM appointments a
              WHERE a.client_id = c.id
                AND a.sync_status != ?
            ) AS appointment_count,
            (
              SELECT COUNT(*)
              FROM client_attachments f
              WHERE f.client_id = c.id
                AND f.sync_status != ?
            ) AS attachment_count
          FROM clients c
          WHERE c.id = ?
            AND c.sync_status != ?
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable.withString(AppConstants.syncStatusPendingDelete),
            Variable.withString(AppConstants.syncStatusPendingDelete),
            Variable.withInt(clientId),
            Variable.withString(AppConstants.syncStatusPendingDelete),
          ],
          readsFrom: <ResultSetImplementation<dynamic, dynamic>>{
            _db.clients,
            _db.appointments,
            _db.clientAttachments,
          },
        )
        .watchSingleOrNull()
        .map((QueryRow? row) => row == null ? null : _mapClientQueryRow(row));
  }

  Stream<List<AppointmentEntity>> watchAppointmentsForClient(int clientId) {
    final query =
        _db.select(_db.appointments).join([
            innerJoin(
              _db.clients,
              _db.clients.id.equalsExp(_db.appointments.clientId),
            ),
          ])
          ..where(
            _db.appointments.clientId.equals(clientId) &
                _db.appointments.syncStatus
                    .equals(AppConstants.syncStatusPendingDelete)
                    .not(),
          )
          ..orderBy([
            OrderingTerm.desc(_db.appointments.startTime),
            OrderingTerm.desc(_db.appointments.id),
          ]);

    return query.watch().map(
      (List<TypedResult> rows) => rows
          .map((TypedResult row) {
            final appt = row.readTable(_db.appointments);
            final client = row.readTable(_db.clients);
            return AppointmentEntity(
              id: appt.id,
              syncId: appt.syncId,
              googleCalendarEventId: appt.googleCalendarEventId,
              clientId: client.id,
              clientName: client.name,
              clientRawPhone: client.rawPhone,
              clientPhoneE164: client.phoneE164,
              clientGoogleContactId: client.googleContactId,
              title: appt.title,
              notes: appt.notes,
              startTime: appt.startTime.toLocal(),
              endTime: appt.endTime.toLocal(),
              reminderSent: appt.reminderSent,
              syncStatus: AppointmentSyncStatus.fromDbValue(appt.syncStatus),
              lastModified: appt.lastModified.toLocal(),
            );
          })
          .toList(growable: false),
    );
  }

  Stream<List<ClientAttachmentEntity>> watchAttachmentsForClient(int clientId) {
    final query =
        _db.select(_db.clientAttachments).join([
            innerJoin(
              _db.clients,
              _db.clients.id.equalsExp(_db.clientAttachments.clientId),
            ),
          ])
          ..where(
            _db.clientAttachments.clientId.equals(clientId) &
                _db.clientAttachments.syncStatus
                    .equals(AppConstants.syncStatusPendingDelete)
                    .not(),
          )
          ..orderBy([
            OrderingTerm.desc(_db.clientAttachments.createdAt),
            OrderingTerm.desc(_db.clientAttachments.id),
          ]);

    return query.watch().map(
      (List<TypedResult> rows) => rows
          .map((TypedResult row) {
            final att = row.readTable(_db.clientAttachments);
            final client = row.readTable(_db.clients);
            return ClientAttachmentEntity(
              id: att.id,
              syncId: att.syncId,
              clientId: att.clientId,
              clientSyncId: client.syncId,
              fileName: att.fileName,
              mimeType: att.mimeType,
              sizeBytes: att.sizeBytes,
              localPath: att.localPath,
              driveFileId: att.driveFileId,
              syncStatus: AppointmentSyncStatus.fromDbValue(att.syncStatus),
              createdAt: att.createdAt.toLocal(),
              lastModified: att.lastModified.toLocal(),
            );
          })
          .toList(growable: false),
    );
  }

  Future<ClientEntity> createOrUpdateClient({
    int? existingClientId,
    required String name,
    required String rawPhone,
    required String phoneE164,
    String? googleContactId,
  }) async {
    final cleanName = name.trim();
    final cleanRawPhone = rawPhone.trim();
    final cleanE164 = phoneE164.trim();
    final cleanContactId = _trimOrNull(googleContactId);
    final now = _truncateUtcSeconds(DateTime.now());

    late final int resolvedId;
    if (existingClientId != null) {
      final current =
          await (_db.select(_db.clients)
                ..where((c) => c.id.equals(existingClientId))
                ..limit(1))
              .getSingleOrNull();
      if (current != null) {
        final nextStatus =
            current.syncStatus == AppConstants.syncStatusPendingCreate
            ? AppConstants.syncStatusPendingCreate
            : AppConstants.syncStatusPendingUpdate;
        await (_db.update(
          _db.clients,
        )..where((c) => c.id.equals(current.id))).write(
          ClientsCompanion(
            name: Value(cleanName),
            rawPhone: Value(cleanRawPhone),
            phoneE164: Value(cleanE164),
            googleContactId: Value(cleanContactId ?? current.googleContactId),
            syncStatus: Value(nextStatus),
            lastModified: Value(now),
          ),
        );
        resolvedId = current.id;
      } else {
        resolvedId = await _localAppointments.upsertClient(
          name: cleanName,
          rawPhone: cleanRawPhone,
          phoneE164: cleanE164,
          googleContactId: cleanContactId,
        );
      }
    } else {
      resolvedId = await _localAppointments.upsertClient(
        name: cleanName,
        rawPhone: cleanRawPhone,
        phoneE164: cleanE164,
        googleContactId: cleanContactId,
      );
    }

    final savedRow = await (_db.select(
      _db.clients,
    )..where((c) => c.id.equals(resolvedId))).getSingle();
    await _pushClientRowToCloud(savedRow);
    return (await watchClientById(resolvedId).first)!;
  }

  Future<void> updateGeneralNotes(int clientId, String? notes) async {
    final current =
        await (_db.select(_db.clients)
              ..where((c) => c.id.equals(clientId))
              ..limit(1))
            .getSingleOrNull();
    if (current == null ||
        current.syncStatus == AppConstants.syncStatusPendingDelete) {
      return;
    }

    final cleanNotes = _trimOrNull(notes);
    final now = _truncateUtcSeconds(DateTime.now());
    final nextStatus =
        current.syncStatus == AppConstants.syncStatusPendingCreate
        ? AppConstants.syncStatusPendingCreate
        : AppConstants.syncStatusPendingUpdate;

    await (_db.update(_db.clients)..where((c) => c.id.equals(clientId))).write(
      ClientsCompanion(
        generalNotes: Value(cleanNotes),
        syncStatus: Value(nextStatus),
        lastModified: Value(now),
      ),
    );

    final updated = await (_db.select(
      _db.clients,
    )..where((c) => c.id.equals(clientId))).getSingle();
    await _pushClientRowToCloud(updated);
  }

  Future<void> deleteClient(ClientEntity client) async {
    final now = _truncateUtcSeconds(DateTime.now());
    final attachments = await (_db.select(
      _db.clientAttachments,
    )..where((a) => a.clientId.equals(client.id))).get();
    final appointments = await (_db.select(
      _db.appointments,
    )..where((a) => a.clientId.equals(client.id))).get();

    for (final att in attachments) {
      await _deleteLocalFileSafely(att.localPath);
    }

    await _db.transaction(() async {
      await (_db.update(
        _db.clients,
      )..where((c) => c.id.equals(client.id))).write(
        ClientsCompanion(
          syncStatus: const Value(AppConstants.syncStatusPendingDelete),
          lastModified: Value(now),
        ),
      );
      for (final appt in appointments) {
        await (_db.update(
          _db.appointments,
        )..where((a) => a.id.equals(appt.id))).write(
          AppointmentsCompanion(
            syncStatus: const Value(AppConstants.syncStatusPendingDelete),
            lastModified: Value(now),
          ),
        );
      }
      for (final att in attachments) {
        await (_db.update(
          _db.clientAttachments,
        )..where((a) => a.id.equals(att.id))).write(
          ClientAttachmentsCompanion(
            syncStatus: const Value(AppConstants.syncStatusPendingDelete),
            lastModified: Value(now),
          ),
        );
      }
    });

    final uid = _userIdProvider?.call();
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(false));
    if (uid == null || uid.isEmpty || !online) {
      return;
    }

    try {
      for (final appt in appointments) {
        await _firestore.markAppointmentDeleted(
          uid,
          syncId: appt.syncId,
          deletedAt: now,
          googleCalendarEventId: appt.googleCalendarEventId,
        );
      }
      for (final att in attachments) {
        if (att.driveFileId != null && att.driveFileId!.isNotEmpty) {
          try {
            await _drive.deleteFile(att.driveFileId!);
          } catch (_) {}
        }
        await _firestore.markClientAttachmentDeleted(
          uid,
          syncId: att.syncId,
          deletedAt: now,
        );
      }
      await _firestore.markClientDeleted(
        uid,
        syncId: client.syncId,
        deletedAt: now,
      );
      await (_db.delete(
        _db.clients,
      )..where((c) => c.id.equals(client.id))).go();
    } catch (_) {
      // Remains queued as `pending_delete` until reconnect.
    }
  }

  /// Stores a copy of [sourceFile] inside app documents, records metadata in
  /// Drift, and uploads to Google Drive + Cloud Firestore when connected.
  Future<({ClientAttachmentEntity attachment, String? warning})> addAttachment({
    required ClientEntity client,
    required File sourceFile,
    required String originalFileName,
    required String mimeType,
  }) async {
    final attachmentsDir = await _attachmentsDirProvider();
    final safeName = _sanitizeFileName(originalFileName);
    final syncId = generateAppointmentSyncId();
    final targetPath = p.join(attachmentsDir.path, '${syncId}_$safeName');
    if (!p.isWithin(attachmentsDir.path, targetPath)) {
      throw ArgumentError('Nombre de archivo inválido.');
    }

    final copiedFile = await sourceFile.copy(targetPath);
    final sizeBytes = await copiedFile.length();
    final now = _truncateUtcSeconds(DateTime.now());

    final insertedId = await _db
        .into(_db.clientAttachments)
        .insert(
          ClientAttachmentsCompanion.insert(
            syncId: syncId,
            clientId: client.id,
            fileName: safeName,
            mimeType: mimeType,
            sizeBytes: Value(sizeBytes),
            localPath: Value(copiedFile.path),
            syncStatus: const Value(AppConstants.syncStatusPendingCreate),
            createdAt: now,
            lastModified: now,
          ),
        );

    String? warning;
    final uid = _userIdProvider?.call();
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(false));

    if (uid != null && uid.isNotEmpty && online) {
      try {
        // Ensure parent client exists in Firestore first.
        final clientRow = await (_db.select(
          _db.clients,
        )..where((c) => c.id.equals(client.id))).getSingle();
        await _pushClientRowToCloud(clientRow);

        final driveFileId = await _drive.uploadFile(
          file: copiedFile,
          fileName: safeName,
          mimeType: mimeType,
          requestScopeIfNeeded: true,
        );
        await _firestore.upsertClientAttachment(
          uid,
          CloudAttachmentDocument(
            syncId: syncId,
            clientSyncId: client.syncId,
            fileName: safeName,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            driveFileId: driveFileId,
            deleted: false,
            createdAt: now,
            lastModified: now,
          ),
        );
        await (_db.update(
          _db.clientAttachments,
        )..where((a) => a.id.equals(insertedId))).write(
          ClientAttachmentsCompanion(
            driveFileId: Value(driveFileId),
            syncStatus: const Value(AppConstants.syncStatusSynced),
            lastModified: Value(now),
          ),
        );
      } on DriveSyncUnavailableException catch (error) {
        warning = error.message;
      } catch (_) {
        warning =
            'Archivo guardado en el dispositivo; se subirá al sincronizar.';
      }
    }

    final entity = await _getAttachmentEntityById(insertedId);
    return (attachment: entity!, warning: warning);
  }

  /// Ensures a readable local file for [attachment], downloading from Google
  /// Drive if it was created on another device.
  Future<File> ensureLocalAttachmentFile(
    ClientAttachmentEntity attachment,
  ) async {
    final attachmentsDir = await _attachmentsDirProvider();
    final currentPath = attachment.localPath;
    if (currentPath != null && p.isWithin(attachmentsDir.path, currentPath)) {
      final existing = File(currentPath);
      if (await existing.exists()) {
        return existing;
      }
    }

    final driveId = attachment.driveFileId;
    if (driveId == null || driveId.isEmpty) {
      throw const DriveSyncUnavailableException(
        'Este archivo aún no se ha subido a Google Drive desde el otro dispositivo.',
      );
    }

    final safeName = _sanitizeFileName(attachment.fileName);
    final destinationPath = p.join(
      attachmentsDir.path,
      '${attachment.syncId}_$safeName',
    );
    if (!p.isWithin(attachmentsDir.path, destinationPath)) {
      throw ArgumentError('Ruta de destino inválida.');
    }

    final downloaded = await _drive.downloadFile(
      driveFileId: driveId,
      destination: File(destinationPath),
      requestScopeIfNeeded: true,
    );

    await (_db.update(_db.clientAttachments)
          ..where((a) => a.id.equals(attachment.id)))
        .write(ClientAttachmentsCompanion(localPath: Value(downloaded.path)));
    return downloaded;
  }

  Future<void> deleteAttachment(ClientAttachmentEntity attachment) async {
    await _deleteLocalFileSafely(attachment.localPath);
    final now = _truncateUtcSeconds(DateTime.now());

    if (attachment.syncStatus == AppointmentSyncStatus.pendingCreate &&
        (attachment.driveFileId == null || attachment.driveFileId!.isEmpty)) {
      await (_db.delete(
        _db.clientAttachments,
      )..where((a) => a.id.equals(attachment.id))).go();
      return;
    }

    await (_db.update(
      _db.clientAttachments,
    )..where((a) => a.id.equals(attachment.id))).write(
      ClientAttachmentsCompanion(
        syncStatus: const Value(AppConstants.syncStatusPendingDelete),
        lastModified: Value(now),
      ),
    );

    final uid = _userIdProvider?.call();
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(false));
    if (uid == null || uid.isEmpty || !online) {
      return;
    }

    try {
      if (attachment.driveFileId != null &&
          attachment.driveFileId!.isNotEmpty) {
        try {
          await _drive.deleteFile(attachment.driveFileId!);
        } catch (_) {}
      }
      await _firestore.markClientAttachmentDeleted(
        uid,
        syncId: attachment.syncId,
        deletedAt: now,
      );
      await (_db.delete(
        _db.clientAttachments,
      )..where((a) => a.id.equals(attachment.id))).go();
    } catch (_) {
      // Remains queued as pending_delete until reconnect.
    }
  }

  Future<void> applyCloudClients(List<CloudClientDocument> documents) async {
    if (documents.isEmpty) {
      return;
    }

    await _db.transaction(() async {
      for (final doc in documents) {
        if (doc.syncId.isEmpty) {
          continue;
        }

        var existing =
            await (_db.select(_db.clients)
                  ..where((c) => c.syncId.equals(doc.syncId))
                  ..limit(1))
                .getSingleOrNull();

        if (existing == null && doc.phoneE164.isNotEmpty) {
          existing =
              await (_db.select(_db.clients)
                    ..where((c) => c.phoneE164.equals(doc.phoneE164))
                    ..limit(1))
                  .getSingleOrNull();
        }

        if (doc.deleted) {
          if (existing != null) {
            final keepLocal =
                existing.syncStatus != AppConstants.syncStatusSynced &&
                _secondsAfter(existing.lastModified, doc.lastModified);
            if (!keepLocal) {
              await (_db.delete(
                _db.clients,
              )..where((c) => c.id.equals(existing!.id))).go();
            }
          }
          continue;
        }

        if (doc.name.trim().isEmpty) {
          continue;
        }

        final modifiedUtc = _truncateUtcSeconds(doc.lastModified);
        final remoteNotes = _trimOrNull(doc.generalNotes);

        if (existing != null) {
          if (existing.syncStatus != AppConstants.syncStatusSynced &&
              _secondsAfter(existing.lastModified, modifiedUtc)) {
            continue;
          }

          final cleanContactId =
              doc.googleContactId ?? existing.googleContactId;
          final sameData =
              existing.syncId == doc.syncId &&
              existing.name == doc.name.trim() &&
              existing.rawPhone == doc.rawPhone &&
              existing.phoneE164 == doc.phoneE164 &&
              existing.generalNotes == remoteNotes &&
              existing.googleContactId == cleanContactId &&
              existing.syncStatus == AppConstants.syncStatusSynced;
          if (sameData) {
            continue;
          }

          await (_db.update(
            _db.clients,
          )..where((c) => c.id.equals(existing!.id))).write(
            ClientsCompanion(
              syncId: Value(doc.syncId),
              googleContactId: Value(cleanContactId),
              name: Value(doc.name.trim()),
              rawPhone: Value(doc.rawPhone),
              phoneE164: Value(doc.phoneE164),
              generalNotes: Value(remoteNotes),
              syncStatus: const Value(AppConstants.syncStatusSynced),
              lastModified: Value(modifiedUtc),
            ),
          );
        } else {
          await _db
              .into(_db.clients)
              .insert(
                ClientsCompanion.insert(
                  syncId: doc.syncId,
                  googleContactId: Value(doc.googleContactId),
                  name: doc.name.trim(),
                  rawPhone: doc.rawPhone,
                  phoneE164: doc.phoneE164,
                  generalNotes: Value(remoteNotes),
                  syncStatus: const Value(AppConstants.syncStatusSynced),
                  lastModified: modifiedUtc,
                ),
              );
        }
      }
    });
  }

  Future<void> applyCloudAttachments(
    List<CloudAttachmentDocument> documents,
  ) async {
    if (documents.isEmpty) {
      return;
    }

    final toDeletePaths = <String>[];
    await _db.transaction(() async {
      for (final doc in documents) {
        if (doc.syncId.isEmpty) {
          continue;
        }

        final existing =
            await (_db.select(_db.clientAttachments)
                  ..where((a) => a.syncId.equals(doc.syncId))
                  ..limit(1))
                .getSingleOrNull();

        if (doc.deleted) {
          if (existing != null) {
            if (existing.localPath != null) {
              toDeletePaths.add(existing.localPath!);
            }
            await (_db.delete(
              _db.clientAttachments,
            )..where((a) => a.id.equals(existing.id))).go();
          }
          continue;
        }

        if (doc.clientSyncId.isEmpty || doc.fileName.trim().isEmpty) {
          continue;
        }

        final parentClient =
            await (_db.select(_db.clients)
                  ..where((c) => c.syncId.equals(doc.clientSyncId))
                  ..limit(1))
                .getSingleOrNull();
        if (parentClient == null) {
          continue;
        }

        final modifiedUtc = _truncateUtcSeconds(doc.lastModified);
        final createdUtc = _truncateUtcSeconds(doc.createdAt);

        if (existing != null) {
          if (existing.syncStatus != AppConstants.syncStatusSynced &&
              _secondsAfter(existing.lastModified, modifiedUtc)) {
            continue;
          }
          final sameData =
              existing.clientId == parentClient.id &&
              existing.fileName == doc.fileName &&
              existing.mimeType == doc.mimeType &&
              existing.sizeBytes == doc.sizeBytes &&
              existing.driveFileId == doc.driveFileId &&
              existing.syncStatus == AppConstants.syncStatusSynced;
          if (sameData) {
            continue;
          }

          await (_db.update(
            _db.clientAttachments,
          )..where((a) => a.id.equals(existing.id))).write(
            ClientAttachmentsCompanion(
              clientId: Value(parentClient.id),
              fileName: Value(doc.fileName),
              mimeType: Value(doc.mimeType),
              sizeBytes: Value(doc.sizeBytes),
              driveFileId: Value(doc.driveFileId),
              syncStatus: const Value(AppConstants.syncStatusSynced),
              lastModified: Value(modifiedUtc),
            ),
          );
        } else {
          await _db
              .into(_db.clientAttachments)
              .insert(
                ClientAttachmentsCompanion.insert(
                  syncId: doc.syncId,
                  clientId: parentClient.id,
                  fileName: doc.fileName,
                  mimeType: doc.mimeType,
                  sizeBytes: Value(doc.sizeBytes),
                  driveFileId: Value(doc.driveFileId),
                  syncStatus: const Value(AppConstants.syncStatusSynced),
                  createdAt: createdUtc,
                  lastModified: modifiedUtc,
                ),
              );
        }
      }
    });

    for (final path in toDeletePaths) {
      await _deleteLocalFileSafely(path);
    }
  }

  /// Synchronizes pending/migrated clients and attachment metadata with
  /// Cloud Firestore and Google Drive.
  Future<void> syncWithCloud() async {
    final uid = _userIdProvider?.call();
    if (uid == null || uid.isEmpty) {
      return;
    }
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(false));
    if (!online) {
      return;
    }

    final cloudClients = await _firestore.fetchClients(uid);
    final cloudClientsBySyncId = <String, CloudClientDocument>{
      for (final c in cloudClients) c.syncId: c,
    };

    // 1. Drain local client mutations and migrate existing synced clients.
    final allLocalClients = await _db.select(_db.clients).get();
    for (final client in allLocalClients) {
      if (client.syncStatus == AppConstants.syncStatusPendingDelete) {
        await _firestore.markClientDeleted(
          uid,
          syncId: client.syncId,
          deletedAt: client.lastModified,
        );
        await (_db.delete(
          _db.clients,
        )..where((c) => c.id.equals(client.id))).go();
        continue;
      }

      final isPending = client.syncStatus != AppConstants.syncStatusSynced;
      final missingInCloud = !cloudClientsBySyncId.containsKey(client.syncId);
      if (isPending || missingInCloud) {
        final remote = cloudClientsBySyncId[client.syncId];
        if (remote != null &&
            remote.deleted &&
            _secondsAfter(remote.lastModified, client.lastModified)) {
          await (_db.delete(
            _db.clients,
          )..where((c) => c.id.equals(client.id))).go();
          continue;
        }
        await _firestore.upsertClient(uid, _toCloudClient(client));
        await (_db.update(
          _db.clients,
        )..where((c) => c.id.equals(client.id))).write(
          const ClientsCompanion(
            syncStatus: Value(AppConstants.syncStatusSynced),
          ),
        );
      }
    }

    final refreshedCloudClients = await _firestore.fetchClients(uid);
    await applyCloudClients(refreshedCloudClients);

    // 2. Drain pending attachment uploads/deletes.
    final cloudAttachments = await _firestore.fetchClientAttachments(uid);
    final allAttachments = await _db.select(_db.clientAttachments).get();
    for (final att in allAttachments) {
      if (att.syncStatus == AppConstants.syncStatusPendingDelete) {
        if (att.driveFileId != null && att.driveFileId!.isNotEmpty) {
          try {
            await _drive.deleteFile(att.driveFileId!);
          } catch (_) {}
        }
        await _firestore.markClientAttachmentDeleted(
          uid,
          syncId: att.syncId,
          deletedAt: att.lastModified,
        );
        await _deleteLocalFileSafely(att.localPath);
        await (_db.delete(
          _db.clientAttachments,
        )..where((a) => a.id.equals(att.id))).go();
        continue;
      }

      if (att.syncStatus == AppConstants.syncStatusPendingCreate ||
          att.syncStatus == AppConstants.syncStatusPendingUpdate) {
        final parent =
            await (_db.select(_db.clients)
                  ..where((c) => c.id.equals(att.clientId))
                  ..limit(1))
                .getSingleOrNull();
        if (parent == null) {
          continue;
        }

        var driveFileId = att.driveFileId;
        if ((driveFileId == null || driveFileId.isEmpty) &&
            att.localPath != null) {
          final file = File(att.localPath!);
          if (await file.exists()) {
            try {
              driveFileId = await _drive.uploadFile(
                file: file,
                fileName: att.fileName,
                mimeType: att.mimeType,
                requestScopeIfNeeded: false,
              );
            } catch (_) {
              // Keep queued until user authorizes or connection recovers.
              continue;
            }
          }
        }

        await _firestore.upsertClientAttachment(
          uid,
          CloudAttachmentDocument(
            syncId: att.syncId,
            clientSyncId: parent.syncId,
            fileName: att.fileName,
            mimeType: att.mimeType,
            sizeBytes: att.sizeBytes,
            driveFileId: driveFileId,
            deleted: false,
            createdAt: att.createdAt,
            lastModified: att.lastModified,
          ),
        );
        await (_db.update(
          _db.clientAttachments,
        )..where((a) => a.id.equals(att.id))).write(
          ClientAttachmentsCompanion(
            driveFileId: Value(driveFileId),
            syncStatus: const Value(AppConstants.syncStatusSynced),
          ),
        );
      }
    }

    final refreshedCloudAttachments = cloudAttachments.isNotEmpty
        ? await _firestore.fetchClientAttachments(uid)
        : await _firestore.fetchClientAttachments(uid);
    await applyCloudAttachments(refreshedCloudAttachments);
  }

  /// Removes locally cached attachment files (e.g., when switching Google accounts).
  Future<void> clearLocalAttachmentFiles() async {
    try {
      final dir = await _attachmentsDirProvider();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _pushClientRowToCloud(Client row) async {
    final uid = _userIdProvider?.call();
    if (uid == null || uid.isEmpty) {
      return;
    }
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(false));
    if (!online) {
      return;
    }

    try {
      await _firestore.upsertClient(uid, _toCloudClient(row));
      await (_db.update(_db.clients)..where((c) => c.id.equals(row.id))).write(
        const ClientsCompanion(
          syncStatus: Value(AppConstants.syncStatusSynced),
        ),
      );
    } catch (_) {
      // Remains queued until next sync pass.
    }
  }

  CloudClientDocument _toCloudClient(Client row) {
    return CloudClientDocument(
      syncId: row.syncId,
      googleContactId: row.googleContactId,
      name: row.name,
      rawPhone: row.rawPhone,
      phoneE164: row.phoneE164,
      generalNotes: row.generalNotes,
      deleted: row.syncStatus == AppConstants.syncStatusPendingDelete,
      lastModified: row.lastModified,
    );
  }

  Future<ClientAttachmentEntity?> _getAttachmentEntityById(int id) async {
    final row =
        await (_db.select(_db.clientAttachments).join([
                innerJoin(
                  _db.clients,
                  _db.clients.id.equalsExp(_db.clientAttachments.clientId),
                ),
              ])
              ..where(_db.clientAttachments.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final att = row.readTable(_db.clientAttachments);
    final client = row.readTable(_db.clients);
    return ClientAttachmentEntity(
      id: att.id,
      syncId: att.syncId,
      clientId: att.clientId,
      clientSyncId: client.syncId,
      fileName: att.fileName,
      mimeType: att.mimeType,
      sizeBytes: att.sizeBytes,
      localPath: att.localPath,
      driveFileId: att.driveFileId,
      syncStatus: AppointmentSyncStatus.fromDbValue(att.syncStatus),
      createdAt: att.createdAt.toLocal(),
      lastModified: att.lastModified.toLocal(),
    );
  }

  ClientEntity _mapClientQueryRow(QueryRow row) {
    final data = row.data;
    final lastModifiedEpoch = (data['last_modified'] as int?) ?? 0;
    return ClientEntity(
      id: data['id'] as int,
      syncId: data['sync_id'] as String,
      googleContactId: data['google_contact_id'] as String?,
      name: data['name'] as String,
      rawPhone: data['raw_phone'] as String,
      phoneE164: data['phone_e164'] as String,
      generalNotes: data['general_notes'] as String?,
      syncStatus: AppointmentSyncStatus.fromDbValue(
        (data['sync_status'] as String?) ?? AppConstants.syncStatusSynced,
      ),
      lastModified: DateTime.fromMillisecondsSinceEpoch(
        lastModifiedEpoch * 1000,
        isUtc: true,
      ).toLocal(),
      appointmentCount: (data['appointment_count'] as int?) ?? 0,
      attachmentCount: (data['attachment_count'] as int?) ?? 0,
    );
  }

  Future<void> _deleteLocalFileSafely(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      final attachmentsDir = await _attachmentsDirProvider();
      if (!p.isWithin(attachmentsDir.path, path)) {
        return;
      }
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  String _sanitizeFileName(String raw) {
    final base = p.basename(raw.trim());
    final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'archivo';
    }
    return cleaned.length > 80
        ? cleaned.substring(cleaned.length - 80)
        : cleaned;
  }

  String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  DateTime _truncateUtcSeconds(DateTime value) {
    final utc = value.toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      (utc.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
  }

  bool _secondsAfter(DateTime a, DateTime b) {
    return (a.toUtc().millisecondsSinceEpoch ~/ 1000) >
        (b.toUtc().millisecondsSinceEpoch ~/ 1000);
  }
}

final clientsRepositoryProvider = Provider<ClientsRepository>((Ref ref) {
  return ClientsRepository(
    ref.watch(appDatabaseProvider),
    localAppointmentsDatasource: ref.watch(localAppointmentsDatasourceProvider),
    firestoreDatasource: ref.watch(firestoreSyncDatasourceProvider),
    driveDatasource: ref.watch(googleDriveFilesDatasourceProvider),
    currentUserId: () => ref.read(authControllerProvider).user?.id,
    isOnline: () => ref.read(connectivityServiceProvider).isOnline,
  );
});

final clientsListProvider = StreamProvider<List<ClientEntity>>((Ref ref) {
  return ref.watch(clientsRepositoryProvider).watchClients();
});

final clientDetailProvider = StreamProvider.family<ClientEntity?, int>((
  Ref ref,
  int clientId,
) {
  return ref.watch(clientsRepositoryProvider).watchClientById(clientId);
});

final clientAppointmentsProvider =
    StreamProvider.family<List<AppointmentEntity>, int>((
      Ref ref,
      int clientId,
    ) {
      return ref
          .watch(clientsRepositoryProvider)
          .watchAppointmentsForClient(clientId);
    });

final clientAttachmentsProvider =
    StreamProvider.family<List<ClientAttachmentEntity>, int>((
      Ref ref,
      int clientId,
    ) {
      return ref
          .watch(clientsRepositoryProvider)
          .watchAttachmentsForClient(clientId);
    });
