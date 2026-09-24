import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server.dart';
import '../../core/state/providers.dart';

/// Servers the user belongs to.
class ServersController extends AutoDisposeAsyncNotifier<List<Server>> {
  @override
  Future<List<Server>> build() =>
      ref.read(serverRepositoryProvider).listMine();

  Future<void> create(String name) async {
    await ref.read(serverRepositoryProvider).create(name: name.trim());
    ref.invalidateSelf();
  }

  Future<void> joinByCode(String code) async {
    await ref.read(serverRepositoryProvider).joinByCode(code.trim());
    ref.invalidateSelf();
  }

  Future<void> leave(String serverId) async {
    await ref.read(serverRepositoryProvider).leave(serverId);
    ref.invalidateSelf();
  }
}

final serversControllerProvider = AutoDisposeAsyncNotifierProvider<
    ServersController, List<Server>>(ServersController.new);

/// Channels of the currently selected server.
class ChannelsController
    extends AutoDisposeFamilyAsyncNotifier<List<Channel>, String> {
  @override
  Future<List<Channel>> build(String serverId) =>
      ref.read(serverRepositoryProvider).listChannels(serverId);

  Future<void> create(String name, bool isVoice) async {
    await ref
        .read(serverRepositoryProvider)
        .createChannel(serverId: arg, name: name, isVoice: isVoice);
    ref.invalidateSelf();
  }
}

final channelsControllerProvider = AutoDisposeAsyncNotifierProviderFamily<
    ChannelsController, List<Channel>, String>(ChannelsController.new);
