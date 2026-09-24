import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server.dart';
import '../servers/servers_controller.dart';
import '../voice/voice_participants_list.dart';

/// Vertical server rail (desktop).
class ServerRail extends ConsumerStatefulWidget {
  const ServerRail({
    super.key,
    required this.selectedServer,
    required this.onServerSelected,
  });

  final Server? selectedServer;
  final ValueChanged<Server?> onServerSelected;

  @override
  ConsumerState<ServerRail> createState() => _ServerRailState();
}

class _ServerRailState extends ConsumerState<ServerRail> {
  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversControllerProvider);
    final theme = Theme.of(context);

    return Container(
      width: 72,
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          const SizedBox(height: 12),
          serversAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Expanded(
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(serversControllerProvider),
                ),
              ),
            ),
            data: (servers) => Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final server in servers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ServerIcon(
                        server: server,
                        selected: widget.selectedServer?.id == server.id,
                        onTap: () => widget.onServerSelected(server),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Add / join server',
                    icon: const Icon(Icons.add),
                    onPressed: () => _showAddServerDialog(context),
                  ),
                ],
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
    required this.server,
    required this.selected,
    required this.onTap,
  });

  final Server server;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary : theme.cardTheme.color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Text(
              server.name.isEmpty ? '?' : server.name[0].toUpperCase(),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// Channel list for the selected server (desktop sidebar + mobile page).
class ChannelSidebar extends ConsumerStatefulWidget {
  const ChannelSidebar({
    super.key,
    required this.server,
    required this.selectedChannelId,
    required this.onChannelSelected,
  });

  final Server server;
  final String? selectedChannelId;
  final void Function(String channelId, bool isVoice) onChannelSelected;

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
              error: (e, _) => Center(child: Text('$e')),
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
                            widget.onChannelSelected(c.id, false),
                      ),
                    const SizedBox(height: 10),
                    _sectionLabel(context, 'VOICE CHANNELS'),
                    for (final c in voiceChannels) ...[
                      _ChannelTile(
                        icon: Icons.volume_up_outlined,
                        label: c.name,
                        selected: widget.selectedChannelId == c.id,
                        onTap: () =>
                            widget.onChannelSelected(c.id, true),
                      ),
                      // Show participants under the voice channel.
                      VoiceChannelParticipants(channelId: c.id),
                    ],
                  ],
                );
              },
            ),
          ),
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
  final void Function(String channelId, bool isVoice) onChannelSelected;

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
        if (servers.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Servers')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No servers yet'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _showAddDialog(context),
                    child: const Text('Create or join one'),
                  ),
                ],
              ),
            ),
          );
        }
        // Show the channel sidebar for the selected server full-screen.
        // Auto-select the first server post-frame (never setState during build).
        Server server;
        if (widget.selectedServer == null) {
          server = servers.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onServerSelected(server);
          });
        } else {
          server = widget.selectedServer!;
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(server.name),
            leading: IconButton(
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
