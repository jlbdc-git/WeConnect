import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user_settings.dart';
import '../../core/state/providers.dart';
import '../auth/auth_controller.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.onOpenFullSettings});

  final VoidCallback? onOpenFullSettings;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
      // The authStateProvider stream emission rebuilds the router and
      // lands on /login. If this screen is still mounted after sign-out
      // (e.g. the redirect is momentarily delayed), reflect it instead of
      // leaving a dead authenticated screen behind.
      if (mounted) setState(() => _signingOut = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
        setState(() => _signingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: widget.onOpenFullSettings == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Profile ----
            profileAsync.maybeWhen(
              data: (profile) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(profile?.effectiveName ?? '…'),
                  subtitle: Text(profile == null
                      ? ''
                      : '@${profile.username}'),
                  trailing: IconButton(
                    tooltip: 'Edit display name',
                    icon: const Icon(Icons.edit),
                    onPressed: () =>
                        _editDisplayName(context, profile!.displayName),
                  ),
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // ---- Voice mode ----
            Text('Voice Mode',
                style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<VoiceMode>(
              groupValue: settings.voiceMode,
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(settingsControllerProvider.notifier)
                    .setVoiceMode(v);
              },
              child: const Column(
                children: [
                  RadioListTile<VoiceMode>(
                    title: Text('Voice Activity (automatic)'),
                    subtitle:
                        Text('Transmits when you speak (DTX + server VAD)'),
                    value: VoiceMode.voiceActivity,
                  ),
                  RadioListTile<VoiceMode>(
                    title: Text('Push-to-Talk'),
                    subtitle:
                        Text('Transmit only while holding your PTT key'),
                    value: VoiceMode.pushToTalk,
                  ),
                ],
              ),
            ),
            const Divider(),

            // ---- PTT configuration ----
            Text('Push-to-Talk Key',
                style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 8,
              children: [
                for (final key in const [
                  'V', 'B', 'Space', 'LAlt', 'LCtrl', 'CapsLock', 'Tab'
                ])
                  ChoiceChip(
                    label: Text(key),
                    selected: settings.pttKey == key,
                    onSelected: (_) {
                      ref.read(settingsControllerProvider.notifier).save(
                            settings.copyWith(pttKey: key),
                          );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Mouse button (Windows)',
                style: Theme.of(context).textTheme.bodySmall),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  0: 'None',
                  4: 'Back (XB1)',
                  5: 'Forward (XB2)',
                  6: 'Middle',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: settings.pttMouseButton == entry.key,
                    onSelected: (_) {
                      ref.read(settingsControllerProvider.notifier).save(
                            settings.copyWith(
                                pttMouseButton: entry.key),
                          );
                    },
                  ),
              ],
            ),
            const Divider(),

            // ---- Voice processing ----
            Text('Voice Processing',
                style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              title: const Text('Noise suppression'),
              value: settings.noiseSuppression,
              onChanged: (v) => ref
                  .read(settingsControllerProvider.notifier)
                  .save(settings.copyWith(noiseSuppression: v)),
            ),
            SwitchListTile(
              title: const Text('Echo cancellation'),
              value: settings.echoCancellation,
              onChanged: (v) => ref
                  .read(settingsControllerProvider.notifier)
                  .save(settings.copyWith(echoCancellation: v)),
            ),
            SwitchListTile(
              title: const Text('Automatic gain control'),
              value: settings.autoGainControl,
              onChanged: (v) => ref
                  .read(settingsControllerProvider.notifier)
                  .save(settings.copyWith(autoGainControl: v)),
            ),
            const Divider(),

            // ---- VAD sensitivity ----
            Text('Voice activity sensitivity: ${settings.vadSensitivity}',
                style: Theme.of(context).textTheme.bodyMedium),
            Slider(
              value: settings.vadSensitivity.toDouble(), // 0..100 by design
              max: 100,
              divisions: 20,
              label: '${settings.vadSensitivity}',
              onChanged: (v) => ref
                  .read(settingsControllerProvider.notifier)
                  .save(settings.copyWith(vadSensitivity: v.round())),
            ),
            const Divider(),

            // ---- Sign out ----
            ListTile(
              leading: _signingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.logout, color: Colors.red),
              title: const Text('Sign out',
                  style: TextStyle(color: Colors.red)),
              onTap: _signingOut ? null : _signOut,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editDisplayName(BuildContext context, String current) async {
    final ctrl = TextEditingController(text: current);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    await ref
        .read(profileRepositoryProvider)
        .update(id: ref.read(supabaseClientProvider).auth.currentUser!.id,
            displayName: ctrl.text.trim());
    if (mounted) {
      ref.invalidate(myProfileProvider);
    }
  }
}
