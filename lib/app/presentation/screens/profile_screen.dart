import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/localization.dart';
import '../../providers/locale_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../config/company_info.dart';
import '../../services/update_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _editingName = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? dt, Locale locale) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    const t = AppLocalization.translate;
    final months = [
      t('month_jan', locale),
      t('month_feb', locale),
      t('month_mar', locale),
      t('month_apr', locale),
      t('month_may', locale),
      t('month_jun', locale),
      t('month_jul', locale),
      t('month_aug', locale),
      t('month_sep', locale),
      t('month_oct', locale),
      t('month_nov', locale),
      t('month_dec', locale),
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  String _formatDateTime(DateTime? dt, Locale locale) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final date = _formatDate(dt, locale);
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$date — $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    final locale = ref.watch(localeProvider);
    final themeState = ref.watch(themeProvider);
    const t = AppLocalization.translate;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = themeState.mode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('profile', locale)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(authProvider.notifier).refreshProfile(),
            tooltip: locale.languageCode == 'ar' ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ─── بطاقة المستخدم الرئيسية ───
          _buildUserCard(context, state, locale, colorScheme, theme),
          const SizedBox(height: 20),

          // ─── معلومات الموقع والجهاز ───
          if (state.isAuthenticated) ...[
            _buildInfoSection(context, state, locale, colorScheme, theme),
            const SizedBox(height: 20),
          ],

          // ─── الإعدادات ───
          _buildSettingsSection(
            context,
            ref,
            locale,
            themeState,
            isDark,
            colorScheme,
            theme,
          ),
          const SizedBox(height: 20),

          // ─── التحديثات ───
          _buildUpdateCheck(context, ref, locale, colorScheme),
          const SizedBox(height: 20),

          // ─── معلومات الشركة ───
          _buildCompanyInfo(context, locale, colorScheme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    AuthState state,
    Locale locale,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final initials = state.displayName.isNotEmpty
        ? state.displayName[0].toUpperCase()
        : '?';
    final userId = state.user?.id ?? '';
    final shortId = userId.length > 8 ? userId.substring(0, 8) : userId;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // أفاتار المستخدم
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // اسم المستخدم (قابل للتعديل)
          if (_editingName)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      hintText: locale.languageCode == 'ar'
                          ? 'أدخل اسمك'
                          : 'Enter name',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                    onSubmitted: (_) => _saveNewName(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.check_rounded, color: Colors.white),
                  onPressed: _saveNewName,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => setState(() => _editingName = false),
                ),
              ],
            )
          else
            GestureDetector(
              onTap: () {
                _nameController.text = state.displayName == 'مستخدم'
                    ? ''
                    : state.displayName;
                setState(() => _editingName = true);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit_rounded,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 16,
                  ),
                ],
              ),
            ),

          // معرف المستخدم
          if (shortId.isNotEmpty)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: userId));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      locale.languageCode == 'ar'
                          ? 'تم نسخ المعرّف'
                          : 'ID Copied',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fingerprint_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ID: $shortId…',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.copy_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
    BuildContext context,
    AuthState state,
    Locale locale,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final isAr = locale.languageCode == 'ar';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _infoTile(
              icon: Icons.calendar_today_rounded,
              label: isAr ? 'تاريخ الانضمام' : 'Joined',
              value: _formatDate(state.joinedAt, locale),
              color: colorScheme.primary,
            ),
            const Divider(height: 1, indent: 56),
            _infoTile(
              icon: Icons.access_time_rounded,
              label: isAr ? 'آخر نشاط' : 'Last active',
              value: _formatDateTime(state.lastSignIn, locale),
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context,
    WidgetRef ref,
    Locale locale,
    AppThemeState themeState,
    bool isDark,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    const t = AppLocalization.translate;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.language_rounded,
                color: Colors.purple,
                size: 20,
              ),
            ),
            title: Text(t('language', locale)),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('EN')),
                ButtonSegment(value: 'ar', label: Text('ع')),
              ],
              selected: {locale.languageCode},
              onSelectionChanged: (s) {
                ref.read(localeProvider.notifier).setLocale(Locale(s.first));
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: Colors.indigo,
                size: 20,
              ),
            ),
            title: Text(t('theme', locale)),
            trailing: Switch(
              value: isDark,
              onChanged: (val) {
                ref
                    .read(themeProvider.notifier)
                    .setMode(val ? ThemeMode.dark : ThemeMode.light);
              },
            ),
          ),
          if (state.isAuthenticated) ...[
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              title: Text(locale.languageCode == 'ar' ? 'تسجيل الخروج' : 'Log Out', style: const TextStyle(color: Colors.red)),
              onTap: () async {
                await ref.read(authProvider.notifier).signOut();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpdateCheck(
    BuildContext context,
    WidgetRef ref,
    Locale locale,
    ColorScheme colorScheme,
  ) {
    final isAr = locale.languageCode == 'ar';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.system_update_rounded,
            color: colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(isAr ? 'البحث عن تحديثات' : 'Check for updates'),
        subtitle: Text(
          isAr
              ? 'تأكد أنك تستخدم أحدث نسخة'
              : 'Make sure you are on the latest version',
        ),
        onTap: () async {
          final update = await UpdateService.checkForUpdate();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  update != null
                      ? (isAr ? 'يوجد تحديث جديد متاح!' : 'Update available!')
                      : (isAr
                            ? 'أنت تستخدم أحدث نسخة ✅'
                            : 'You are up to date ✅'),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildCompanyInfo(
    BuildContext context,
    Locale locale,
    ColorScheme colorScheme,
  ) {
    const t = AppLocalization.translate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t('company_info', locale),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.business_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: const Text(CompanyInfo.companyName),
                subtitle: const Text(CompanyInfo.address),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.phone_rounded,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
                title: const Text(CompanyInfo.phoneNumber),
                onTap: () =>
                    launchUrl(Uri.parse('tel:${CompanyInfo.phoneNumber}')),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.language_rounded,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                title: const Text(CompanyInfo.website),
                onTap: () => launchUrl(Uri.parse(CompanyInfo.website)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _saveNewName() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      ref.read(authProvider.notifier).updateDisplayName(name);
    }
    setState(() => _editingName = false);
  }
}
