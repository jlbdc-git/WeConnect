import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/server.dart';
import '../chat/chat_screen.dart';
import '../servers/servers_controller.dart';
import '../friends/friends_screen.dart';
import '../servers/servers_screen.dart';
import '../settings/settings_screen.dart';
import '../voice/voice_panel.dart';
import 'user_panel.dart';

/// Main navigation shell.
///
/// Desktop: [server rail | channel sidebar + user panel | main content].
/// The user panel is ALWAYS visible at the sidebar's bottom (Discord-style),
/// so account/settings/logout never depend on a server being selected.
/// Mobile: bottom navigation between Friends / Servers / You (settings).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _mobileIndex = 0;
  Server? _selectedServer;
  String? _selectedChannelId;
  bool _isVoiceChannelSelected = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    if (isDesktop) return _buildDesktop(context);
    return _buildMobile(context);
  }

  void _selectServer(Server? s) => setState(() {
        _selectedServer = s;
        _selectedChannelId = null;
      });

  void _selectChannel(String id, bool isVoice, [String? name]) =>
      setState(() {
        _selectedChannelId = id;
        _isVoiceChannelSelected = isVoice;
        _mobileChannelName = name;
      });

  // -------------------------------------------------------------------------
  // Desktop: server rail | (header + sidebar + user panel) | main content
  // -------------------------------------------------------------------------
  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          ServerRail(
            selectedServer: _selectedServer,
            onServerSelected: _selectServer,
            onHomeSelected: () => _selectServer(null),
          ),
          // Channel sidebar with the account panel pinned at its bottom.
          if (_selectedServer != null)
            ChannelSidebar(
              server: _selectedServer!,
              selectedChannelId: _selectedChannelId,
              onChannelSelected: _selectChannel,
            )
          else
            SizedBox(
              width: 240,
              child: Column(
                children: [
                  Expanded(
                    child: _SidebarHome(
                      selected: true,
                      onHomeSelected: () {},
                      onAddServer: () => _showAddServerSheet(context),
                    ),
                  ),
                  const UserPanel(),
                ],
              ),
            ),
          // Main area
          Expanded(
            child: _selectedChannelId == null
                ? _selectedServer == null
                    ? const FriendsScreen() // desktop home = Friends
                    : const _EmptyMain()
                : _isVoiceChannelSelected
                    ? VoicePanel(
                        channelId: _selectedChannelId!,
                        serverId: _selectedServer!.id,
                      )
                    : ChatScreen(
                        channelId: _selectedChannelId!,
                        serverId: _selectedServer!.id,
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddServerSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration:
                  const InputDecoration(hintText: 'Create: server name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: codeCtrl,
              decoration:
                  const InputDecoration(hintText: 'Or join: invite code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (created != true) return;
    try {
      if (codeCtrl.text.trim().isNotEmpty) {
        await ref
            .read(serversControllerProvider.notifier)
            .joinByCode(codeCtrl.text);
      } else if (nameCtrl.text.trim().isNotEmpty) {
        await ref
            .read(serversControllerProvider.notifier)
            .create(nameCtrl.text);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // -------------------------------------------------------------------------
  // Mobile: bottom navigation, full-screen pages. Selecting a channel
  // pushes a full-screen chat/voice view with an explicit back button.
  // -------------------------------------------------------------------------
  Widget _buildMobile(BuildContext context) {
    final pages = [
      const FriendsScreen(),
      ServersScreen(
        selectedServer: _selectedServer,
        selectedChannelId: _selectedChannelId,
        onServerSelected: _selectServer,
        onChannelSelected: _selectChannel,
      ),
      const SettingsIndex(),
    ];

    return Scaffold(
      body: _selectedChannelId != null && _selectedServer != null
          // Channel open → full-screen view with back navigation.
          ? _MobileChannelView(
              channelId: _selectedChannelId!,
              serverId: _selectedServer!.id,
              channelName: _selectedChannelName ?? 'channel',
              isVoice: _isVoiceChannelSelected,
              onBack: () => setState(() => _selectedChannelId = null),
            )
          : IndexedStack(index: _mobileIndex, children: pages),
      bottomNavigationBar: _selectedChannelId != null
          ? null // hide nav while a channel is open; back returns first
          : NavigationBar(
              selectedIndex: _mobileIndex,
              onDestinationSelected: (i) => setState(() => _mobileIndex = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.people_outline), label: 'Friends'),
                NavigationDestination(
                    icon: Icon(Icons.dns_outlined), label: 'Servers'),
                NavigationDestination(
                    icon: Icon(Icons.settings_outlined), label: 'You'),
              ],
            ),
    );
  }

  String? get _selectedChannelName {
    // Resolved by the channel list when tapped; kept simple: the sidebar
    // passes the name via the callback closure below if available.
    return _mobileChannelName;
  }

  String? _mobileChannelName;
}

/// Full-screen channel view on mobile with an explicit back button.
class _MobileChannelView extends StatelessWidget {
  const _MobileChannelView({
    required this.channelId,
    required this.serverId,
    required this.channelName,
    required this.isVoice,
    required this.onBack,
  });

  final String channelId;
  final String serverId;
  final String channelName;
  final bool isVoice;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isVoice ? 'Voice: $channelName' : channelName),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: isVoice
          ? VoicePanel(channelId: channelId, serverId: serverId)
          : ChatScreen(channelId: channelId, serverId: serverId),
    );
  }
}

class _EmptyMain extends StatelessWidget {
  const _EmptyMain();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 48, color: Theme.of(context).hintColor),
          const SizedBox(height: 12),
          Text('Select a channel to start',
              style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

// Re-exported so home_shell can navigate to settings quickly on desktop.
class SettingsIndex extends ConsumerWidget {
  const SettingsIndex({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsScreen(
      onOpenFullSettings: () => context.go('/settings'),
    );
  }
}

// imported by servers_screen for the desktop empty-sidebar; kept here to
// avoid a circular import servers_screen ↔ home_shell.
class _SidebarHome extends StatelessWidget {
  const _SidebarHome({
    required this.selected,
    required this.onHomeSelected,
    required this.onAddServer,
  });

  final bool selected;
  final VoidCallback onHomeSelected;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.cardTheme.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(
              children: [
                Icon(Icons.forum, size: 18, color: theme.hintColor),
                const SizedBox(width: 8),
                Text(
                  'WeConnect',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _SidebarNavItem(
              icon: Icons.people_outline,
              label: 'Friends',
              selected: selected,
              onTap: onHomeSelected,
            ),
          ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: Text(
              'DIRECT MESSAGES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: theme.hintColor,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Direct messages are not available yet.\n'
                  'Pick a server on the left to chat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.hintColor, fontSize: 13),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: OutlinedButton.icon(
              onPressed: onAddServer,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Server'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nav item shared by the sidebar (also used by ServerRail's home button).
class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.surfaceContainerHighest
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.hintColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.hintColor,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
