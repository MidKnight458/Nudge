import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';

/// Exception thrown when Google Drive API access is not authorized or enabled.
class DriveSyncUnavailableException implements Exception {
  const DriveSyncUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Manages client attachments inside a dedicated `Nudge` folder in the user's
/// Google Drive (`drive.file` scope).
abstract interface class GoogleDriveFilesDatasource {
  Future<String> uploadFile({
    required File file,
    required String fileName,
    required String mimeType,
    bool requestScopeIfNeeded = false,
  });

  Future<File> downloadFile({
    required String driveFileId,
    required File destination,
    bool requestScopeIfNeeded = true,
  });

  Future<void> deleteFile(String driveFileId);
}

class GoogleDriveFilesDatasourceImpl implements GoogleDriveFilesDatasource {
  GoogleDriveFilesDatasourceImpl(this._authRepository);

  final AuthRepository _authRepository;

  Future<String> _ensureNudgeFolderId(drive.DriveApi api) async {
    const query =
        "name = '${AppConstants.driveFolderName}' "
        "and mimeType = 'application/vnd.google-apps.folder' "
        'and trashed = false';
    final listed = await api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
      pageSize: 1,
    );
    final existing = listed.files?.firstOrNull;
    if (existing?.id != null && existing!.id!.isNotEmpty) {
      return existing.id!;
    }

    final folder = drive.File(
      name: AppConstants.driveFolderName,
      mimeType: 'application/vnd.google-apps.folder',
    );
    final created = await api.files.create(folder, $fields: 'id');
    final id = created.id;
    if (id == null || id.isEmpty) {
      throw const DriveSyncUnavailableException(
        'No se pudo crear la carpeta Nudge en Google Drive.',
      );
    }
    return id;
  }

  @override
  Future<String> uploadFile({
    required File file,
    required String fileName,
    required String mimeType,
    bool requestScopeIfNeeded = false,
  }) async {
    final handle = await _authRepository.openDriveClient(
      requestScopeIfNeeded: requestScopeIfNeeded,
    );
    if (handle == null) {
      throw const DriveSyncUnavailableException(
        'Permiso de Google Drive no disponible.',
      );
    }

    try {
      final folderId = await _ensureNudgeFolderId(handle.api);
      final length = await file.length();
      final media = drive.Media(file.openRead(), length);
      final metadata = drive.File(
        name: fileName,
        mimeType: mimeType,
        parents: <String>[folderId],
      );
      final created = await handle.api.files.create(
        metadata,
        uploadMedia: media,
        $fields: 'id',
      );
      final id = created.id;
      if (id == null || id.isEmpty) {
        throw const DriveSyncUnavailableException(
          'Google Drive no devolvió el identificador del archivo.',
        );
      }
      return id;
    } on drive.DetailedApiRequestError catch (error) {
      if (error.status == 403) {
        throw const DriveSyncUnavailableException(
          'Habilita Google Drive API en Google Cloud Console (HTTP 403).',
        );
      }
      if (error.status == 401) {
        throw const DriveSyncUnavailableException(
          'Sesión de Google Drive expirada (HTTP 401).',
        );
      }
      throw DriveSyncUnavailableException(
        'Error al subir archivo a Google Drive (HTTP ${error.status}).',
      );
    } finally {
      handle.close();
    }
  }

  @override
  Future<File> downloadFile({
    required String driveFileId,
    required File destination,
    bool requestScopeIfNeeded = true,
  }) async {
    final handle = await _authRepository.openDriveClient(
      requestScopeIfNeeded: requestScopeIfNeeded,
    );
    if (handle == null) {
      throw const DriveSyncUnavailableException(
        'Conecta tu cuenta de Google para descargar archivos desde Drive.',
      );
    }

    try {
      final response = await handle.api.files.get(
        driveFileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (response is! drive.Media) {
        throw const DriveSyncUnavailableException(
          'Google Drive no devolvió el contenido del archivo.',
        );
      }
      await destination.parent.create(recursive: true);
      final sink = destination.openWrite();
      try {
        await sink.addStream(response.stream);
      } finally {
        await sink.flush();
        await sink.close();
      }
      return destination;
    } on drive.DetailedApiRequestError catch (error) {
      if (error.status == 403) {
        throw const DriveSyncUnavailableException(
          'Habilita Google Drive API en Google Cloud Console (HTTP 403).',
        );
      }
      if (error.status == 404) {
        throw const DriveSyncUnavailableException(
          'El archivo ya no existe en Google Drive.',
        );
      }
      throw DriveSyncUnavailableException(
        'Error al descargar desde Google Drive (HTTP ${error.status}).',
      );
    } finally {
      handle.close();
    }
  }

  @override
  Future<void> deleteFile(String driveFileId) async {
    if (driveFileId.isEmpty) {
      return;
    }
    final handle = await _authRepository.openDriveClient(
      requestScopeIfNeeded: false,
    );
    if (handle == null) {
      return;
    }

    try {
      await handle.api.files.delete(driveFileId);
    } on drive.DetailedApiRequestError catch (error) {
      if (error.status != 404 && error.status != 410) {
        rethrow;
      }
    } finally {
      handle.close();
    }
  }
}

final googleDriveFilesDatasourceProvider = Provider<GoogleDriveFilesDatasource>(
  (Ref ref) {
    return GoogleDriveFilesDatasourceImpl(ref.watch(authRepositoryProvider));
  },
);
