import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/data/local_appointments_datasource.dart';
import 'package:nudge/features/clients/data/clients_repository.dart';
import 'package:nudge/features/clients/data/google_drive_files_datasource.dart';

class _InMemoryGoogleDriveDatasource implements GoogleDriveFilesDatasource {
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  int _counter = 1;

  @override
  Future<String> uploadFile({
    required File file,
    required String fileName,
    required String mimeType,
    bool requestScopeIfNeeded = false,
  }) async {
    final id = 'drive_${_counter++}';
    _files[id] = await file.readAsBytes();
    return id;
  }

  @override
  Future<File> downloadFile({
    required String driveFileId,
    required File destination,
    bool requestScopeIfNeeded = true,
  }) async {
    final bytes = _files[driveFileId];
    if (bytes == null) {
      throw const DriveSyncUnavailableException('No encontrado en Drive fake.');
    }
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes);
    return destination;
  }

  @override
  Future<void> deleteFile(String driveFileId) async {
    _files.remove(driveFileId);
  }
}

class _InMemoryClientsFirestore implements FirestoreSyncDatasource {
  final Map<String, CloudClientDocument> _clients =
      <String, CloudClientDocument>{};
  final Map<String, CloudAttachmentDocument> _attachments =
      <String, CloudAttachmentDocument>{};

  @override
  Future<List<CloudClientDocument>> fetchClients(String userId) async =>
      _clients.values.toList(growable: false);

  @override
  Stream<List<CloudClientDocument>> watchClients(String userId) =>
      const Stream<List<CloudClientDocument>>.empty();

  @override
  Future<void> upsertClient(String userId, CloudClientDocument document) async {
    _clients[document.syncId] = document;
  }

  @override
  Future<void> markClientDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
  }) async {
    final prev = _clients[syncId];
    _clients[syncId] = CloudClientDocument(
      syncId: syncId,
      googleContactId: prev?.googleContactId,
      name: prev?.name ?? '',
      rawPhone: prev?.rawPhone ?? '',
      phoneE164: prev?.phoneE164 ?? '',
      generalNotes: prev?.generalNotes,
      deleted: true,
      lastModified: deletedAt.toUtc(),
    );
  }

  @override
  Future<List<CloudAttachmentDocument>> fetchClientAttachments(
    String userId,
  ) async => _attachments.values.toList(growable: false);

  @override
  Stream<List<CloudAttachmentDocument>> watchClientAttachments(String userId) =>
      const Stream<List<CloudAttachmentDocument>>.empty();

  @override
  Future<void> upsertClientAttachment(
    String userId,
    CloudAttachmentDocument document,
  ) async {
    _attachments[document.syncId] = document;
  }

  @override
  Future<void> markClientAttachmentDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
  }) async {
    final prev = _attachments[syncId];
    _attachments[syncId] = CloudAttachmentDocument(
      syncId: syncId,
      clientSyncId: prev?.clientSyncId ?? '',
      fileName: prev?.fileName ?? '',
      mimeType: prev?.mimeType ?? 'application/pdf',
      sizeBytes: prev?.sizeBytes ?? 0,
      driveFileId: prev?.driveFileId,
      deleted: true,
      createdAt:
          prev?.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastModified: deletedAt.toUtc(),
    );
  }

  @override
  Future<List<CloudAppointmentDocument>> fetchAppointments(
    String userId,
  ) async => const <CloudAppointmentDocument>[];

  @override
  Stream<List<CloudAppointmentDocument>> watchAppointments(String userId) =>
      const Stream<List<CloudAppointmentDocument>>.empty();

  @override
  Future<void> upsertAppointment(
    String userId,
    CloudAppointmentDocument document,
  ) async {}

  @override
  Future<void> markAppointmentDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
    String? googleCalendarEventId,
  }) async {}

  @override
  Future<CloudSettingsDocument?> fetchSettings(String userId) async => null;

  @override
  Stream<CloudSettingsDocument?> watchSettings(String userId) =>
      const Stream<CloudSettingsDocument?>.empty();

  @override
  Future<void> upsertSettings(
    String userId,
    CloudSettingsDocument document,
  ) async {}

  @override
  Future<List<CloudTemplateDocument>> fetchTemplates(String userId) async =>
      const <CloudTemplateDocument>[];

  @override
  Stream<List<CloudTemplateDocument>> watchTemplates(String userId) =>
      const Stream<List<CloudTemplateDocument>>.empty();

  @override
  Future<void> upsertTemplate(
    String userId,
    CloudTemplateDocument document,
  ) async {}
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('ClientsRepository notes & Drive attachments', () {
    test(
      'syncs general notes and PDF/photo attachments across two devices',
      () async {
        final dbA = AppDatabase(NativeDatabase.memory());
        final dbB = AppDatabase(NativeDatabase.memory());
        final firestore = _InMemoryClientsFirestore();
        final drive = _InMemoryGoogleDriveDatasource();
        final tempDirA = await Directory.systemTemp.createTemp('nudge_test_a_');
        final tempDirB = await Directory.systemTemp.createTemp('nudge_test_b_');
        final sourceDir = await Directory.systemTemp.createTemp('nudge_src_');

        try {
          final repoA = ClientsRepository(
            dbA,
            localAppointmentsDatasource: LocalAppointmentsDatasource(dbA),
            firestoreDatasource: firestore,
            driveDatasource: drive,
            currentUserId: () => 'uid_1',
            isOnline: () async => true,
            attachmentsDirectoryProvider: () async => tempDirA,
          );
          final repoB = ClientsRepository(
            dbB,
            localAppointmentsDatasource: LocalAppointmentsDatasource(dbB),
            firestoreDatasource: firestore,
            driveDatasource: drive,
            currentUserId: () => 'uid_1',
            isOnline: () async => true,
            attachmentsDirectoryProvider: () async => tempDirB,
          );

          final clientA = await repoA.createOrUpdateClient(
            name: 'Paciente Laura',
            rawPhone: '5512345678',
            phoneE164: '5215512345678',
          );
          await repoA.updateGeneralNotes(clientA.id, 'Alergia a penicilina');

          final pdfFile = File('${sourceDir.path}/expediente.pdf');
          await pdfFile.writeAsBytes(Uint8List.fromList(<int>[1, 2, 3, 4]));

          final added = await repoA.addAttachment(
            client: clientA,
            sourceFile: pdfFile,
            originalFileName: '../expediente.pdf',
            mimeType: 'application/pdf',
          );
          expect(added.warning, isNull);
          expect(added.attachment.fileName, 'expediente.pdf');
          expect(added.attachment.driveFileId, isNotNull);

          await repoB.syncWithCloud();

          final clientsB = await repoB.watchClients().first;
          expect(clientsB, hasLength(1));
          expect(clientsB.single.generalNotes, 'Alergia a penicilina');
          expect(clientsB.single.attachmentCount, 1);

          final attachmentsB = await repoB
              .watchAttachmentsForClient(clientsB.single.id)
              .first;
          expect(attachmentsB, hasLength(1));
          expect(attachmentsB.single.localPath, isNull);

          final downloaded = await repoB.ensureLocalAttachmentFile(
            attachmentsB.single,
          );
          expect(await downloaded.exists(), isTrue);
          expect(
            await downloaded.readAsBytes(),
            Uint8List.fromList(<int>[1, 2, 3, 4]),
          );

          await repoB.deleteAttachment(attachmentsB.single);
          await repoA.syncWithCloud();
          expect(
            await repoA.watchAttachmentsForClient(clientA.id).first,
            isEmpty,
          );
        } finally {
          await dbA.close();
          await dbB.close();
          if (await tempDirA.exists()) await tempDirA.delete(recursive: true);
          if (await tempDirB.exists()) await tempDirB.delete(recursive: true);
          if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
        }
      },
    );
  });
}
