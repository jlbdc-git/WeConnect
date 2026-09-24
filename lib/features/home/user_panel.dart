import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/providers.dart';
import '../auth/auth_controller.dart';

/// Discord-style account panel: avatar + name, pinned to the bottom of the
/// sidebar so account access (settings, logout) is ALWAYS visible on
/// desktop — independent of whether a server is selected.
///
/// Tapping opens the account menu (profile info / Settings / Log out).
/// Log out calls the real Supabase sign-out; the auth-state listener lands
/// the router on /login — this panel never navigates on its own.
class UserPanel extends ConsumerWidget {
  const UserPanel({super.key});

  void _openAccountMenu(BuildContext context, WidgetRef ref) {
    final profile = ref.read(myProfileProvider).valueOrNull;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: AccountAvatar(
                  avatarUrl: profile?.avatarUrl,
                  name: profile?.effectiveName ?? '?',
                ),
                title: Text(
                  profile?.effectiveName ?? 'Account',
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: profile == null
                    ? null
                    : Text('@${profile.username}#${profile.tag}'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go('/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Log out',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  // Real sign-out: ends the Supabase session, cleans up
                  // voice/PTT, invalidates caches. The signedOut event
                  // re-runs the router redirect → /login.
                  ref.read(authControllerProvider.notifier).signOut();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _openAccountMenu(context, ref),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    AccountAvatar(
                      avatarUrl: profile?.avatarUrl,
                      name: profile?.effectiveName ?? '?',
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            profile?.effectiveName ?? 'Account',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (profile != null)
                            Text(
                              '@${profile.username}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.unfold_more,
                        size: 16, color: theme.hintColor),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () => context.go('/settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Shared avatar: network image when the profile has one, else the first
/// letter of the display name.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, this.avatarUrl, required this.name});

  final String? avatarUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    return CircleAvatar(
      radius: 16,
      backgroundImage: (url != null && url.isNotEmpty)
          ? NetworkImage(url)
          : null,
      child: (url == null || url.isEmpty)
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 14),
            )
          : null,
    );
  }
}
