import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import '../../providers/vault_provider.dart';
import '../../providers/locale_provider.dart';
import '../../config/localization.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider);
    final locale = ref.watch(localeProvider);
    const t = AppLocalization.translate;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(t('vault_title', locale), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (vaultState.status == VaultStatus.unlocked) ...[
            IconButton(
              icon: const Icon(Icons.add_moderator_rounded, color: Color(0xFF00A3FF)),
              onPressed: () async {
                final result = await FilePicker.pickFiles();
                if (result != null && result.files.single.path != null) {
                  await ref.read(vaultProvider.notifier).encryptFile(File(result.files.single.path!));
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF00A3FF)),
              onPressed: () => ref.read(vaultProvider.notifier).lock(),
            ),
          ],
        ],
      ),
      body: vaultState.status == VaultStatus.locked 
          ? _buildPinEntry(locale, t) 
          : _buildVaultContent(vaultState, locale, t),
    );
  }

  Widget _buildPinEntry(Locale locale, String Function(String, Locale) t) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF00A3FF).withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF00A3FF).withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.security_rounded, size: 80, color: Color(0xFF00A3FF)),
            ),
            const SizedBox(height: 32),
            Text(
              t('vault_encrypted_desc', locale),
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              t('vault_enter_pin', locale),
              style: const TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            
            SizedBox(
              width: 250,
              child: TextField(
                controller: _pinController,
                obscureText: true,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: const TextStyle(color: Colors.white10),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00A3FF), width: 1.5)),
                ),
                onChanged: (val) {
                  if (val.length == 6) {
                    ref.read(vaultProvider.notifier).unlock(val);
                    _pinController.clear();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVaultContent(VaultState state, Locale locale, String Function(String, Locale) t) {
    if (state.encryptedFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_rounded, size: 100, color: Colors.white.withValues(alpha: 0.05)),
            const SizedBox(height: 24),
            Text(t('vault_empty_title', locale), style: const TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 8),
            Text(t('vault_empty_desc', locale), style: const TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.encryptedFiles.length,
      itemBuilder: (context, index) {
        final file = state.encryptedFiles[index];
        final name = p.basenameWithoutExtension(file.path);
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.black,
              child: Icon(Icons.enhanced_encryption_rounded, color: Color(0xFF00A3FF), size: 20),
            ),
            title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text(t('vault_protected_subtitle', locale), style: const TextStyle(color: Colors.grey, fontSize: 11)),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              color: const Color(0xFF1E1E1E),
              onSelected: (value) {
                if (value == 'restore') {
                  _showRestoreDialog(file, locale, t);
                } else if (value == 'delete') {
                  _showDeleteDialog(file, locale, t);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'restore',
                  child: Row(
                    children: [
                      const Icon(Icons.unarchive_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(t('vault_decrypt_now', locale), style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Text(t('delete', locale), style: const TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRestoreDialog(dynamic file, Locale locale, String Function(String, Locale) t) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text(t('vault_decrypt_title', locale), style: const TextStyle(color: Colors.white)),
        content: Text(t('vault_decrypt_desc', locale), style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel', locale), style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              ref.read(vaultProvider.notifier).decryptFile(file);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('vault_decrypt_snack', locale))));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A3FF), foregroundColor: Colors.white),
            child: Text(t('vault_decrypt_now', locale)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(dynamic file, Locale locale, String Function(String, Locale) t) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text(t('delete', locale), style: const TextStyle(color: Colors.white)),
        content: Text(t('delete_confirm_desc', locale), style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('cancel', locale), style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              ref.read(vaultProvider.notifier).deleteFileFromVault(file);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: Text(t('delete', locale)),
          ),
        ],
      ),
    );
  }
}
