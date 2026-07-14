import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/toolkit_provider.dart';
import '../../providers/locale_provider.dart';
import '../../config/localization.dart';
import 'vault_screen.dart';

class ToolkitScreen extends ConsumerStatefulWidget {
  const ToolkitScreen({super.key});

  @override
  ConsumerState<ToolkitScreen> createState() => _ToolkitScreenState();
}

class _ToolkitScreenState extends ConsumerState<ToolkitScreen> {
  @override
  Widget build(BuildContext context) {
    final toolkitState = ref.watch(toolkitProvider);
    final locale = ref.watch(localeProvider);
    const t = AppLocalization.translate;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('toolkit_title', locale), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (toolkitState.status == ToolkitTaskStatus.processing)
              _buildProcessingIndicator(toolkitState.statusMessage ?? t('toolkit_processing', locale)),
            
            if (toolkitState.status == ToolkitTaskStatus.success || toolkitState.status == ToolkitTaskStatus.error)
              _buildStatusAlert(toolkitState),

            _buildSectionHeader(t('toolkit_sec_security', locale)),
            const SizedBox(height: 16),
            _buildToolCard(
              title: t('toolkit_vault_title', locale),
              description: t('toolkit_vault_desc', locale),
              icon: Icons.security_rounded,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VaultScreen())),
              accentColor: const Color(0xFF00A3FF),
            ),


            
            const SizedBox(height: 32),
            _buildSectionHeader(t('toolkit_sec_ffmpeg', locale)),
            const SizedBox(height: 16),
            _buildToolCard(
              title: t('toolkit_mp3_title', locale),
              description: t('toolkit_mp3_desc', locale),
              icon: Icons.music_note,
              onTap: () => ref.read(toolkitProvider.notifier).convertToMp3(),
            ),
            _buildToolCard(
              title: t('toolkit_compress_title', locale),
              description: t('toolkit_compress_desc', locale),
              icon: Icons.compress,
              onTap: () => ref.read(toolkitProvider.notifier).compressVideo(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
    );
  }

  Widget _buildProcessingIndicator(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF00A3FF).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00A3FF).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A3FF))),
          const SizedBox(width: 16),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildStatusAlert(ToolkitState state) {
    final isSuccess = state.status == ToolkitTaskStatus.success;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: (isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(isSuccess ? Icons.check_circle_rounded : Icons.error_rounded, color: isSuccess ? Colors.green : Colors.red),
              const SizedBox(width: 16),
              Expanded(child: Text(state.statusMessage ?? '', style: const TextStyle(color: Colors.white, fontSize: 13))),
              IconButton(onPressed: () => ref.read(toolkitProvider.notifier).reset(), icon: const Icon(Icons.close, size: 18, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
    Color accentColor = const Color(0xFF00A3FF),
  }) {
    return Card(
      color: const Color(0xFF0A0A0A),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accentColor.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accentColor),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(description, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        onTap: onTap,
      ),
    );
  }
}
