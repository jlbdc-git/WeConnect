import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// First-run screen shown when no Supabase credentials are configured.
/// Lets the user paste their project URL + anon key (stored in secure
/// storage, never committed to the repo).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (!url.startsWith('http')) {
      setState(() => _error = 'URL must start with https://');
      return;
    }
    if (!AppConfig.looksLikeValidAnonKey(key)) {
      setState(() => _error = 'That does not look like a Supabase anon key.');
      return;
    }
    await AppConfig.saveConfig(url: url, anonKey: key);
    if (mounted) {
      setState(() => _error = 'Saved. Restart the app to connect.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to WeConnect')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.settings_suggest, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'Connect your Supabase backend',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Paste the Project URL and anon public key from your '
                  'Supabase dashboard (Settings → API). These are client-safe '
                  'values — Row Level Security protects your data.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _urlCtrl,
                  decoration:
                      const InputDecoration(hintText: 'https://xxxx.supabase.co'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                      hintText: 'eyJhbGciOi... (anon public key)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save configuration'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
