import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import '../../providers/vault_provider.dart';

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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("المخزن السري | Hidden Vault", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (vaultState.status == VaultStatus.unlocked) ...[
            IconButton(
              icon: const Icon(Icons.add_moderator_rounded, color: Color(0xFF00A3FF)),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles();
                if (result != null && result.files.single.path != null) {
                  ref.read(vaultProvider.notifier).encryptFile(File(result.files.single.path!));
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
          ? _buildPinEntry() 
          : _buildVaultContent(vaultState),
    );
  }

  Widget _buildPinEntry() {
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
            const Text(
              "الخزنة مشفرة بـ AES-256",
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "أدخل رمز الحماية للوصول لملفاتك الخاصة",
              style: TextStyle(color: Colors.grey, fontSize: 14),
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
                  counterText: "",
                  hintText: "••••••",
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

  Widget _buildVaultContent(VaultState state) {
    if (state.encryptedFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off_rounded, size: 100, color: Colors.white.withValues(alpha: 0.05)),
            const SizedBox(height: 24),
            const Text("المخزن فارغ حالياً", style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 8),
            const Text("انقل الملفات من التحميلات لتشفيرها هنا", style: TextStyle(color: Colors.white24, fontSize: 12)),
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
            subtitle: const Text("محمي بتشفير عسكري", style: TextStyle(color: Colors.grey, fontSize: 11)),
            trailing: IconButton(
              icon: const Icon(Icons.unarchive_rounded, color: Colors.grey),
              onPressed: () => _showRestoreDialog(file),
            ),
          ),
        );
      },
    );
  }

  void _showRestoreDialog(dynamic file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text("فك تشفير الملف؟", style: TextStyle(color: Colors.white)),
        content: const Text("سيتم استعادة الملف إلى مجلد التحميلات الخاص بك.", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              ref.read(vaultProvider.notifier).decryptFile(file);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("جاري فك التشفير والاستعادة...")));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A3FF), foregroundColor: Colors.white),
            child: const Text("استعادة الآن"),
          ),
        ],
      ),
    );
  }
}
