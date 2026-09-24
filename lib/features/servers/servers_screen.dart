import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server.dart';
import '../home/user_panel.dart';
import '../servers/servers_controller.dart';
import '../voice/voice_participants_list.dart';

/// Vertical server rail (desktop).
///
/// Layout: [home/friends button] [server icons…] [flex gap] [pinned
/// add/join button]. The add button is pinned to the BOTTOM so it stays in
/// the same place with zero or many servers and never dominates the rail.
class ServerRail extends ConsumerStatefulWidget {
  const ServerRail({
    super.key,
    required this.selectedServer,
    required this.onServerSelected,
    this.onHomeSelected,
  });

  final Server? selectedServer;
  final ValueChanged<Server?> onServerSelected;

  /// Invoked when the home (friends) button is tapped. Deselecting the
  /// server (null) shows the friends home + empty-state sidebar.
  final VoidCallback? onHomeSelected;

  @override
  ConsumerState<ServerRail> createState() => _ServerRailState();
}

class _ServerRailState extends ConsumerState<ServerRail> {
  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversControllerProvider);
    final theme = Theme.of(context);
    final homeSelected = widget.selectedServer == null;

    return Container(
      width: 72,
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Tooltip(
            message: 'Friends',
            waitDuration: const Duration(milliseconds: 400),
            child: _ServerIcon(
              label: 'Friends',
              icon: Icons.forum_outlined,
              selected: homeSelected,
              onTap: widget.onHomeSelected ??
                  () => widget.onServerSelected(null),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 8, indent: 16, endIndent: 16),
          const SizedBox(height: 4),
          serversAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Expanded(
              child: Center(
                child: IconButton(
                  tooltip: 'Retry',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(serversControllerProvider),
                ),
              ),
            ),
            data: (servers) => Expanded(
              child: servers.isEmpty
                  // Helpful empty state instead of a bare rail.
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'No servers yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final server in servers)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ServerIcon(
                              label: server.name,
                              monogram: server.name.isEmpty
                                  ? '?'
                                  : server.name[0].toUpperCase(),
                              selected:
                                  widget.selectedServer?.id == server.id,
                              onTap: () => widget.onServerSelected(server),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          // Pinned add/join button (bottom of the rail, Discord-style).
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Tooltip(
              message: 'Add / join server',
              waitDuration: const Duration(milliseconds: 400),
              child: _ServerIcon(
                label: 'Add Server',
                icon: Icons.add,
                selected: false,
                onTap: () => _showAddServerDialog(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddServerDialog(BuildContext context) async {
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
              decoration: const InputDecoration(hintText: 'Create: server name'),
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
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('AppException(', ''))),
      );
    }
  }
}

class _ServerIcon extends StatelessWidget {
  const _ServerIcon({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.monogram,
  });

  /// Tooltip/semantics label (e.g. server name or 'Add Server').
  final String label;
  final IconData? icon;
  final String? monogram;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: selected ? theme.colorScheme.primary : theme.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: icon != null
                  ? Icon(
                      icon,
                      size: 24,
                      color: selected
                          ? Colors.white
                          : theme.colorScheme.onSurface,
                    )
                  : Text(
                      monogram ?? '?',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Channel list for the selected server (desktop sidebar + mobile page).
/// The [UserPanel] is pinned to the bottom so account access is always
/// visible while a server is selected.
class ChannelSidebar extends ConsumerStatefulWidget {
  const ChannelSidebar({
    super.key,
    required this.server,
    required this.selectedChannelId,
    required this.onChannelSelected,
  });

  final Server server;
  final String? selectedChannelId;
  final void Function(String channelId, bool isVoice, [String? name])
      onChannelSelected;

  @override
  ConsumerState<ChannelSidebar> createState() => _ChannelSidebarState();
}

class _ChannelSidebarState extends ConsumerState<ChannelSidebar> {
  @override
  Widget build(BuildContext context) {
    final channelsAsync =
        ref.watch(channelsControllerProvider(widget.server.id));
    final theme = Theme.of(context);

    return Container(
      width: 220,
      color: theme.cardTheme.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.server.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Invite code: ${widget.server.inviteCode}',
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text('Invite code: ${widget.server.inviteCode}'),
                    ));
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: channelsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$e', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => ref
                          .invalidate(channelsControllerProvider(
                              widget.server.id)),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (channels) {
                final textChannels =
                    channels.where((c) => !c.isVoice).toList();
                final voiceChannels =
                    channels.where((c) => c.isVoice).toList();
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _sectionLabel(context, 'TEXT CHANNELS'),
                    for (final c in textChannels)
                      _ChannelTile(
                        icon: Icons.tag,
                        label: c.name,
                        selected:
                            widget.selectedChannelId == c.id,
                        onTap: () =>
                            widget.onChannelSelected(c.id, false, c.name),
                      ),
                    const SizedBox(height: 10),
                    _sectionLabel(context, 'VOICE CHANNELS'),
                    for (final c in voiceChannels) ...[
                      _ChannelTile(
                        icon: Icons.volume_up_outlined,
                        label: c.name,
                        selected: widget.selectedChannelId == c.id,
                        onTap: () =>
                            widget.onChannelSelected(c.id, true, c.name),
                      ),
                      // Show participants under the voice channel.
                      VoiceChannelParticipants(channelId: c.id),
                    ],
                  ],
                );
              },
            ),
          ),
          // Account panel pinned at the sidebar's bottom: always-visible
          // access to settings/logout while a server is open.
          const Divider(height: 1),
          const UserPanel(),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).hintColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.hintColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.hintColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mobile: full servers + channels page.
class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({
    super.key,
    required this.selectedServer,
    required this.selectedChannelId,
    required this.onServerSelected,
    required this.onChannelSelected,
  });

  final Server? selectedServer;
  final String? selectedChannelId;
  final ValueChanged<Server?> onServerSelected;
  final void Function(String channelId, bool isVoice, [String? name])
      onChannelSelected;

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversControllerProvider);

    return serversAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text('$e')),
      ),
      data: (servers) {
        // No server selected → show the SERVER LIST. The list stays the
        // primary state; a server is only "entered" by tapping it, and its
        // app bar has an explicit back button. (Previously the first server
        // was auto-selected, making the list unreachable.)
        if (widget.selectedServer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Servers')),
            body: serversAsync.isLoading
                ? const Center(child: CircularProgressIndicator())
                : servers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('No servers yet'),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => _showAddDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Create Server'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final server in servers)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                child: Text(
                                  server.name.isEmpty
                                      ? '?'
                                      : server.name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(server.name),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => widget.onServerSelected(server),
                            ),
                          const SizedBox(height: 8),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: OutlinedButton.icon(
                              onPressed: () => _showAddDialog(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Server'),
                            ),
                          ),
                        ],
                      ),
          );
        }
        // A server is open: full-screen channel sidebar with a back button
        // that returns to the server list.
        final server = widget.selectedServer!;
        return Scaffold(
          appBar: AppBar(
            title: Text(server.name),
            leading: IconButton(
              tooltip: 'Back to servers',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => widget.onServerSelected(null),
            ),
          ),
          body: ChannelSidebar(
            server: server,
            selectedChannelId: widget.selectedChannelId,
            onChannelSelected: widget.onChannelSelected,
          ),
        );
      },
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    // Same dialog as desktop — extracted for reuse.
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
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK')),
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
}
