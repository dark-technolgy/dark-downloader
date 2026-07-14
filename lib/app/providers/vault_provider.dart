import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../../src/rust/api/security.dart' as rust_security;
import '../services/secure_storage_service.dart';

enum VaultStatus { locked, unlocked, setupRequired }

class VaultState {
  final VaultStatus status;
  final List<File> encryptedFiles;
  final String? errorMessage;
  final bool isLoading;

  VaultState({
    this.status = VaultStatus.locked,
    this.encryptedFiles = const [],
    this.errorMessage,
    this.isLoading = false,
  });

  VaultState copyWith({
    VaultStatus? status,
    List<File>? encryptedFiles,
    String? errorMessage,
    bool? isLoading,
  }) {
    return VaultState(
      status: status ?? this.status,
      encryptedFiles: encryptedFiles ?? this.encryptedFiles,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class VaultNotifier extends Notifier<VaultState> {
  late Directory _vaultDir;
  String? _cachedPin;

  static const _pinHashKey = 'vault_pin_hash_v1';

  @override
  VaultState build() {
    _init();
    return VaultState();
  }

  /// Hash PIN with SHA-256 for secure comparison
  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    _vaultDir = Directory(p.join(docs.path, 'DarkDownloader', '.vault'));
    if (!_vaultDir.existsSync()) {
      _vaultDir.createSync(recursive: true);
    }

    // Check if PIN has been set up
    final storedHash = await SecureStorageService.read(_pinHashKey);
    if (storedHash == null || storedHash.isEmpty) {
      state = state.copyWith(status: VaultStatus.setupRequired);
    }

    _refreshFiles();
  }

  void _refreshFiles() {
    if (!_vaultDir.existsSync()) return;
    final files = _vaultDir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.dvault')
        .toList();
    state = state.copyWith(encryptedFiles: files);
  }

  /// Set up a new PIN (first time only)
  Future<bool> setupPin(String pin) async {
    if (pin.length < 4) return false;
    state = state.copyWith(isLoading: true, errorMessage: null);

    final hash = _hashPin(pin);
    await SecureStorageService.write(_pinHashKey, hash);

    _cachedPin = pin;
    state = state.copyWith(status: VaultStatus.unlocked, isLoading: false);
    return true;
  }

  /// Unlock vault with PIN verification
  Future<bool> unlock(String pin) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final storedHash = await SecureStorageService.read(_pinHashKey);

    // If no PIN was set before, treat as setup
    if (storedHash == null || storedHash.isEmpty) {
      return await setupPin(pin);
    }

    // Verify PIN hash
    final inputHash = _hashPin(pin);
    if (inputHash != storedHash) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'رمز PIN غير صحيح',
      );
      return false;
    }

    _cachedPin = pin;
    state = state.copyWith(status: VaultStatus.unlocked, isLoading: false);
    return true;
  }

  void lock() {
    _cachedPin = null;
    state = state.copyWith(status: VaultStatus.locked);
  }

  /// Change PIN (requires current PIN verification)
  Future<bool> changePin(String currentPin, String newPin) async {
    if (newPin.length < 4) return false;

    final storedHash = await SecureStorageService.read(_pinHashKey);
    final currentHash = _hashPin(currentPin);

    if (currentHash != storedHash) {
      state = state.copyWith(errorMessage: 'رمز PIN الحالي غير صحيح');
      return false;
    }

    final newHash = _hashPin(newPin);
    await SecureStorageService.write(_pinHashKey, newHash);
    _cachedPin = newPin;
    return true;
  }

  Future<void> encryptFile(File source) async {
    if (_cachedPin == null) return;
    state = state.copyWith(isLoading: true);
    
    try {
      final fileName = p.basename(source.path);
      final targetPath = p.join(_vaultDir.path, '$fileName.dvault');
      
      await rust_security.vaultEncryptFile(
        sourcePath: source.path,
        targetPath: targetPath,
        password: _cachedPin!,
      );
      
      _refreshFiles();
    } catch (e) {
      state = state.copyWith(errorMessage: 'فشل التشفير: $e');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> decryptFile(File vaultFile) async {
    if (_cachedPin == null) return;
    state = state.copyWith(isLoading: true);

    try {
      final downloads = await getDownloadsDirectory();
      final originalName = p.basenameWithoutExtension(vaultFile.path);
      final outputPath = p.join(downloads!.path, 'DarkDownloader', 'Restored_$originalName');

      await rust_security.vaultDecryptFile(
        vaultPath: vaultFile.path,
        outputPath: outputPath,
        password: _cachedPin!,
      );
      
      _refreshFiles();
    } catch (e) {
      state = state.copyWith(errorMessage: 'فشل فك التشفير: رمز خاطئ');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> deleteFileFromVault(File vaultFile) async {
    state = state.copyWith(isLoading: true);
    try {
      if (vaultFile.existsSync()) {
        vaultFile.deleteSync();
      }
      _refreshFiles();
    } catch (e) {
      state = state.copyWith(errorMessage: 'فشل حذف الملف: $e');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}

final vaultProvider = NotifierProvider<VaultNotifier, VaultState>(VaultNotifier.new);
