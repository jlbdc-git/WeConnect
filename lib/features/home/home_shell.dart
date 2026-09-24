import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/server.dart';
import '../chat/chat_screen.dart';
import '../friends/friends_screen.dart';
import '../servers/servers_screen.dart';
import '../settings/settings_screen.dart';
import '../voice/voice_panel.dart';

/// Main navigation shell. Desktop: server rail + channel sidebar + content.
/// Mobile: bottom navigation between Friends / Servers / Settings.
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

  // -------------------------------------------------------------------------
  // Desktop: server rail | channel sidebar | main content + voice bar
  // -------------------------------------------------------------------------
  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Server rail
          ServerRail(
            selectedServer: _selectedServer,
            onServerSelected: (s) => setState(() {
              _selectedServer = s;
              _selectedChannelId = null;
            }),
          ),
          // Channel sidebar
          if (_selectedServer != null)
            ChannelSidebar(
              server: _selectedServer!,
              selectedChannelId: _selectedChannelId,
              onChannelSelected: (id, isVoice) => setState(() {
                _selectedChannelId = id;
                _isVoiceChannelSelected = isVoice;
              }),
            ),
          // Main area
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _selectedChannelId == null
                      ? const _EmptyMain()
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
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Mobile: bottom navigation, full-screen pages
  // -------------------------------------------------------------------------
  Widget _buildMobile(BuildContext context) {
    final pages = [
      const FriendsScreen(),
      ServersScreen(
        selectedServer: _selectedServer,
        selectedChannelId: _selectedChannelId,
        onServerSelected: (s) => setState(() {
          _selectedServer = s;
          _selectedChannelId = null;
        }),
        onChannelSelected: (id, isVoice) => setState(() {
          _selectedChannelId = id;
          _isVoiceChannelSelected = isVoice;
        }),
      ),
      const SettingsIndex(),
    ];

    return Scaffold(
      body: IndexedStack(index: _mobileIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileIndex,
        onDestinationSelected: (i) => setState(() => _mobileIndex = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.people_outline), label: 'Friends'),
          NavigationDestination(
              icon: Icon(Icons.dns_outlined), label: 'Servers'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'You'),
        ],
      ),
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
