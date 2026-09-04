import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'jellyfin.dart';

List<T> materializedShuffle<T>(Iterable<T> items, {Random? random}) =>
    items.toList()..shuffle(random);

List<int>? validShuffleOrder(Object? value, int length) {
  final indices = (value as List? ?? const []).whereType<int>().toList();
  if (indices.length != length ||
      indices.toSet().length != length ||
      indices.any((value) => value < 0 || value >= length)) {
    return null;
  }
  return indices;
}

List<MediaItem> vehicleRootItems() => const [
  MediaItem(id: 'browse:listen', title: 'Listen now', playable: false),
  MediaItem(id: 'browse:library', title: 'Library', playable: false),
  MediaItem(id: 'browse:playlists', title: 'Playlists', playable: false),
  MediaItem(id: 'browse:downloads', title: 'Downloads', playable: false),
];

List<MediaItem> androidAutoRootItems() => const [
  MediaItem(
    id: 'browse:home',
    title: 'Home',
    playable: false,
    extras: {
      AndroidContentStyle.browsableHintKey:
          AndroidContentStyle.gridItemHintValue,
      AndroidContentStyle.playableHintKey:
          AndroidContentStyle.gridItemHintValue,
    },
  ),
  MediaItem(id: 'browse:recent', title: 'Recents', playable: false),
  MediaItem(id: 'browse:shuffle', title: 'Shuffle All', playable: false),
  MediaItem(id: 'browse:library', title: 'Library', playable: false),
];

List<MediaItem> vehicleCollectionActions(String type, String id) => [
  MediaItem(id: 'action:play:$type:$id', title: 'Play all', playable: true),
  MediaItem(id: 'action:mix:$id', title: 'Instant mix', playable: true),
];

Uri vehicleArtworkUri(String itemId) => Uri(
  scheme: 'content',
  host: 'com.thomaskleckner.shrimphony.artwork',
  pathSegments: [itemId],
);

MediaItem vehiclePlayingMediaItem(
  JellyfinClient api,
  JellyfinItem item,
  String id, {
  Uri? artwork,
  TargetPlatform? platform,
}) {
  final artworkId = item.artworkId;
  final android = (platform ?? defaultTargetPlatform) == TargetPlatform.android;
  final localArtwork =
      artwork ??
      (artworkId == null
          ? null
          : android
          ? vehicleArtworkUri(artworkId)
          : api.imageUri(artworkId));
  return MediaItem(
    id: id,
    title: item.name,
    album: item.album,
    artist: item.artists.join(', '),
    duration: item.duration,
    artUri: localArtwork,
    artHeaders: artworkId == null ? null : api.authorizationHeaders,
    extras: {
      'jellyfin': item.toJson(),
      if (android && localArtwork != null)
        'android.media.metadata.ALBUM_ART_URI': localArtwork.toString(),
      if (artwork != null) 'localArtUri': artwork.toString(),
      if (artworkId != null) 'remoteArtUri': api.imageUri(artworkId).toString(),
    },
  );
}

MediaItem vehicleBrowserMediaItem(
  JellyfinClient api,
  JellyfinItem item, {
  String? groupTitle,
  Uri? artwork,
}) => MediaItem(
  id: '${item.type}:${item.id}',
  title: item.name,
  album: item.album,
  artist: item.artists.join(', '),
  displaySubtitle: item.subtitle,
  duration: item.duration,
  artHeaders: api.authorizationHeaders,
  artUri:
      artwork ??
      switch (item.artworkId) {
        final id? =>
          defaultTargetPlatform == TargetPlatform.android
              ? vehicleArtworkUri(id)
              : api.imageUri(id),
        null => null,
      },
  playable: item.isAudio,
  extras: {
    'jellyfin': item.toJson(),
    'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT': ?groupTitle,
  },
);

const _androidAutoChannel = MethodChannel(
  'com.thomaskleckner.shrimphony/android_auto',
);

Future<void> _configureVehicleArtwork(JellyfinClient? api) async {
  try {
    await _androidAutoChannel.invokeMethod<void>('configureArtwork', {
      'serverUrl': api?.session.serverUrl,
      'authorization': api?.authorizationHeaders.values.first,
    });
  } on MissingPluginException {
    // Android-only integration.
  } on PlatformException {
    // Browsing still works without artwork if the native bridge is unavailable.
  }
}

class JellyfinAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  JellyfinAudioHandler(this._store, {AudioPlayer? player})
    : _player =
          player ??
          AudioPlayer(
            userAgent: '$appName/$appVersion',
            maxSkipsOnError: 0,
            useProxyForRequestHeaders: false,
          ) {
    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stack) {
        _playbackError =
            'Playback failed. Check your connection, then retry or skip.';
        _broadcastState();
      },
    );
    _player.currentIndexStream.listen(_onIndexChanged);
    _player.shuffleModeEnabledStream.listen((_) => _broadcastState());
    _player.loopModeStream.listen((_) => _broadcastState());
  }

  final JellyfinSessionStore _store;
  final AudioPlayer _player;
  final Completer<void> _initialized = Completer<void>();
  JellyfinClient? _client;
  bool _clientAttached = false;
  bool _disposed = false;
  Timer? _progressTimer;
  Timer? _saveTimer;
  Future<void> _clientTransition = Future.value();
  Future<void> _queueChanges = Future.value();
  bool _loadingLibraryQueue = false;
  Map<String, Uri> _artwork = const {};
  String? _playbackError;
  bool _persistenceFailed = false;
  bool _mutatingQueue = false;
  bool _shuffled = false;
  int _queueGeneration = 0;
  int _nextQueueItemId = 0;
  String? _reportedQueueId;
  String? _reportedItemId;
  Duration _reportedPosition = Duration.zero;

  JellyfinClient? get client => _client;
  Stream<Duration> get positionStream => _player.positionStream;

  Future<void> initialize() async {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(AudioSessionConfiguration.music());
    try {
      await _ensureClient();
    } on Object {
      // The phone UI owns sign-in errors; background audio must not block launch.
      _client = null;
    }
    await _configureVehicleArtwork(_client);
    try {
      await _restoreQueue();
    } on Object {
      _playbackError = 'Saved playback could not load. Retry or choose a song.';
    }
    _broadcastState();
    _initialized.complete();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_player.playing) unawaited(_report('progress'));
      unawaited(_persist());
    });
  }

  void attachClient(JellyfinClient? value) {
    _clientAttached = true;
    final previous = _client;
    _client = value;
    unawaited(_configureVehicleArtwork(value));
    if (!_sameSession(previous?.session, value?.session)) {
      _reportedQueueId = null;
      _reportedItemId = null;
      _saveTimer?.cancel();
      queue.add(const []);
      mediaItem.add(null);
      _clientTransition = _clientTransition.then((_) => _replaceClient(value));
    }
    if (!identical(previous, value)) previous?.close();
  }

  Future<void> playItems(
    List<JellyfinItem> items, {
    int? initialIndex,
    bool shuffle = false,
  }) async {
    await _awaitClientTransition();
    items = items.where((item) => item.isAudio).toList();
    if (items.isEmpty) return;
    final api = await _ensureClient();
    if (api == null) {
      throw const JellyfinException('Sign in before playing music.');
    }
    final generation = ++_queueGeneration;
    final requestedIndex = initialIndex?.clamp(0, items.length - 1);
    final playbackItems = shuffle ? materializedShuffle(items) : items;
    final safeIndex = requestedIndex == null
        ? 0
        : playbackItems.indexOf(items[requestedIndex]);
    final sources = await _audioSources(api, playbackItems);
    final mediaItems = playbackItems
        .map((item) => _queueMediaItem(api, item))
        .toList();
    _reportedPosition = _player.position;
    unawaited(_reportStopped());
    await _queueChanges;
    if (generation != _queueGeneration) return;
    await _editQueue(() async {
      if (generation != _queueGeneration) return;
      _shuffled = shuffle;
      _playbackError = null;
      queue.add(mediaItems);
      mediaItem.add(mediaItems[safeIndex]);
      try {
        await _player.setShuffleModeEnabled(false);
        await _player.setAudioSources(
          sources,
          initialIndex: safeIndex,
          initialPosition: Duration.zero,
          preload: true,
        );
      } on Object {
        _playbackError =
            'Playback failed. Check your connection, then retry or skip.';
        rethrow;
      }
    });
    if (generation == _queueGeneration) await play();
  }

  Future<void> playItem(JellyfinItem item, {List<JellyfinItem>? context}) {
    final items = context ?? [item];
    final identicalIndex = items.indexOf(item);
    final index = identicalIndex < 0
        ? items.indexWhere((candidate) => candidate.id == item.id)
        : identicalIndex;
    return playItems(items, initialIndex: index < 0 ? 0 : index);
  }

  Future<void> _editQueue(Future<void> Function() edit) {
    final api = _client;
    final operation = _queueChanges.then((_) async {
      if (!identical(api, _client)) return;
      _mutatingQueue = true;
      try {
        await edit();
      } finally {
        _mutatingQueue = false;
        if (queue.value.isEmpty) {
          mediaItem.add(null);
        } else {
          _onIndexChanged(_player.currentIndex);
        }
        _broadcastState();
        if (identical(api, _client)) await _persist();
      }
    });
    _queueChanges = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<void> playNext(JellyfinItem item) async {
    await _awaitClientTransition();
    final api = await _ensureClient();
    if (api == null || !item.isAudio) return;
    final source = await _audioSource(api, item);
    await _editQueue(() async {
      final index = ((_player.currentIndex ?? -1) + 1).clamp(
        0,
        queue.value.length,
      );
      await _player.insertAudioSource(index, source);
      final updated = [...queue.value]
        ..insert(index, _queueMediaItem(api, item));
      queue.add(updated);
    });
  }

  Future<void> clearQueue() async {
    await _awaitClientTransition();
    ++_queueGeneration;
    await _editQueue(() async {
      _reportedPosition = _player.position;
      unawaited(_reportStopped());
      await _player.stop();
      await _player.clearAudioSources();
      queue.add(const []);
      _playbackError = null;
    });
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final original = _original(mediaItem);
    if (original != null) await addItemToQueue(original);
  }

  Future<void> addItemToQueue(JellyfinItem item) async {
    await _awaitClientTransition();
    final api = await _ensureClient();
    if (api == null || !item.isAudio) return;
    final source = await _audioSource(api, item);
    await _editQueue(() async {
      await _player.addAudioSource(source);
      queue.add([...queue.value, _queueMediaItem(api, item)]);
    });
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    await _awaitClientTransition();
    await _editQueue(() async {
      final index = queue.value.indexWhere((value) => value.id == mediaItem.id);
      if (index < 0) return;
      await _player.removeAudioSourceAt(index);
      queue.add([...queue.value]..removeAt(index));
    });
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    await _awaitClientTransition();
    await _editQueue(() async {
      if (oldIndex < 0 || oldIndex >= queue.value.length) return;
      final destination = newIndex.clamp(0, queue.value.length - 1);
      if (oldIndex == destination) return;
      await _player.moveAudioSource(oldIndex, destination);
      final updated = [...queue.value];
      updated.insert(destination, updated.removeAt(oldIndex));
      queue.add(updated);
    });
  }

  Future<void> retryPlayback() async {
    await _awaitClientTransition();
    final api = await _ensureClient();
    if (api == null || queue.value.isEmpty) return;
    await _editQueue(() async {
      _playbackError = null;
      final items = queue.value
          .map(_original)
          .whereType<JellyfinItem>()
          .toList();
      final index =
          (_player.currentIndex ?? playbackState.value.queueIndex ?? 0).clamp(
            0,
            items.length - 1,
          );
      try {
        await _player.setAudioSources(
          await _audioSources(api, items),
          initialIndex: index,
          initialPosition: _player.position,
        );
      } on Object {
        _playbackError =
            'Playback failed. Check your connection, then retry or skip.';
        rethrow;
      }
    });
    await play();
  }

  @override
  Future<void> play() async {
    await _initialized.future;
    await _awaitClientTransition();
    if (_player.sequence.isEmpty) return;
    if (_playbackError != null) {
      await retryPlayback();
      return;
    }
    if (_player.processingState == ProcessingState.idle) {
      await _editQueue(() async {
        final index = _player.currentIndex;
        final position = _player.position;
        await _player.load();
        await _player.seek(position, index: index);
      });
    }
    unawaited(
      _player.play().catchError((Object error) {
        _playbackError =
            'Playback failed. Check your connection, then retry or skip.';
        _broadcastState();
      }),
    );
    unawaited(
      _report(_reportedQueueId == mediaItem.value?.id ? 'progress' : 'start'),
    );
  }

  @override
  Future<void> pause() async {
    await _awaitClientTransition();
    await _player.pause();
    unawaited(_report('progress'));
    await _persist();
  }

  @override
  Future<void> stop() async {
    await _awaitClientTransition();
    _reportedPosition = _player.position;
    unawaited(_reportStopped());
    await _player.stop();
    await _persist();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _awaitClientTransition();
    await _player.seek(position);
    unawaited(_report('progress'));
    _scheduleSave();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _awaitClientTransition();
    if (index < 0 || index >= queue.value.length) return;
    _reportedPosition = _player.position;
    _playbackError = null;
    await _player.seek(Duration.zero, index: index);
    _scheduleSave();
  }

  @override
  Future<void> skipToNext() async {
    await _awaitClientTransition();
    if (_player.hasNext) {
      _reportedPosition = _player.position;
      _playbackError = null;
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    await _awaitClientTransition();
    _reportedPosition = _player.position;
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _awaitClientTransition();
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled == _shuffled) return;
    await _editQueue(() async {
      _shuffled = enabled;
      if (enabled && queue.value.length > 1) {
        final index = _player.currentIndex ?? 0;
        final updated = [
          ...queue.value.take(index + 1),
          ...materializedShuffle(queue.value.skip(index + 1)),
        ];
        final byId = {
          for (var i = 0; i < queue.value.length; i++)
            queue.value[i].id: _player.audioSources[i],
        };
        final sources = [for (final item in updated) byId[item.id]!];
        final position = _player.position;
        queue.add(updated);
        await _player.setAudioSources(
          sources,
          initialIndex: index,
          initialPosition: position,
        );
      }
      // The displayed queue is the play order, including explicit edits after shuffle.
      await _player.setShuffleModeEnabled(false);
    });
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _awaitClientTransition();
    await _player.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group => LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
    });
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    _scheduleSave();
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    var parent = parentMediaId;
    var offset = 0;
    if (parent.startsWith('page:')) {
      final separator = parent.indexOf(':', 5);
      if (separator < 0) return [];
      offset = int.tryParse(parent.substring(5, separator)) ?? 0;
      parent = parent.substring(separator + 1);
    }
    if (offset < 0) return [];
    final items = await _getChildren(parent, options);
    const pageSize = 80;
    return [
      ...items.skip(offset).take(pageSize),
      if (offset + pageSize < items.length)
        MediaItem(
          id: 'page:${offset + pageSize}:$parent',
          title: 'More',
          playable: false,
        ),
    ];
  }

  Future<List<MediaItem>> _getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      return androidAutoRootItems();
    }
    await _initialized.future;
    if (parentMediaId == 'browse:listen') {
      final current = mediaItem.value;
      final original = current == null ? null : _original(current);
      return [
        if (current != null)
          MediaItem(
            id: 'action:resume',
            title: 'Resume ${current.title}',
            playable: true,
          ),
        if (original != null)
          MediaItem(
            id: 'action:mix:${original.id}',
            title: 'Instant mix from ${current?.title ?? 'current song'}',
            playable: true,
          ),
        MediaItem(
          id: 'browse:recent',
          title: 'Recently played',
          playable: false,
        ),
        MediaItem(id: 'browse:added', title: 'Recently added', playable: false),
        MediaItem(id: 'browse:favorites', title: 'Favorites', playable: false),
        MediaItem(
          id: 'action:shuffle',
          title: 'Shuffle all songs',
          playable: true,
        ),
      ];
    }
    if (parentMediaId == 'browse:library') {
      return const [
        MediaItem(id: 'browse:albums', title: 'Albums', playable: false),
        MediaItem(id: 'browse:artists', title: 'Artists', playable: false),
        MediaItem(id: 'browse:genres', title: 'Genres', playable: false),
        MediaItem(id: 'browse:playlists', title: 'Playlists', playable: false),
        MediaItem(id: 'browse:downloads', title: 'Downloads', playable: false),
      ];
    }
    if (parentMediaId == 'browse:shuffle') {
      return const [
        MediaItem(
          id: 'action:shuffle',
          title: 'Shuffle all songs',
          playable: true,
        ),
      ];
    }
    final api = await _ensureClient();
    if (api == null) return const [];
    if (parentMediaId == 'browse:downloads' ||
        parentMediaId.startsWith('offline:')) {
      final catalog = parentMediaId == 'browse:downloads'
          ? await _store.offlineCatalog(api.session)
          : await _store.collectionItems(
              api,
              JellyfinItem(
                id: _parseBrowserId(parentMediaId.substring(8))?.$2 ?? '',
                name: '',
                type: _parseBrowserId(parentMediaId.substring(8))?.$1 ?? '',
              ),
              offlineOnly: true,
            );
      final artwork = await _store.downloadedArtwork(api.session);
      return [
        if (parentMediaId.startsWith('offline:'))
          MediaItem(
            id: 'action:offline:${parentMediaId.substring(8)}',
            title: 'Play downloaded songs',
            playable: true,
          ),
        for (final item in catalog)
          vehicleBrowserMediaItem(
            api,
            item,
            artwork: artwork[item.artworkId],
          ).copyWith(id: 'offline:${item.type}:${item.id}'),
      ];
    }
    if (parentMediaId == 'browse:home') {
      final sections = await Future.wait([
        api.recentlyAdded(limit: 10),
        api.randomSongs(limit: 10),
      ]);
      return [
        ...sections[0].map(
          (item) =>
              vehicleBrowserMediaItem(api, item, groupTitle: 'Newly added'),
        ),
        ...sections[1].map(
          (item) => vehicleBrowserMediaItem(
            api,
            item,
            groupTitle: 'Suggested for you',
          ),
        ),
      ];
    }
    final items = switch (parentMediaId) {
      'browse:recent' => await api.recentlyPlayed(limit: 30),
      'browse:added' => await api.recentlyAdded(limit: 30),
      'browse:favorites' => await api.favorites(),
      'browse:albums' => await api.albums(),
      'browse:artists' => await api.artists(),
      'browse:playlists' => await api.playlists(),
      'browse:genres' => await api.genres(),
      'browse:downloads' => (await _store.loadDownloads(api.session)).items,
      _ => await _childrenForBrowserId(api, parentMediaId),
    };
    final parsed = _parseBrowserId(parentMediaId);
    return [
      if (parsed != null &&
          const {
            'MusicAlbum',
            'MusicArtist',
            'Artist',
            'MusicGenre',
            'Playlist',
          }.contains(parsed.$1))
        ...vehicleCollectionActions(parsed.$1, parsed.$2),
      ...items.map((item) => vehicleBrowserMediaItem(api, item)),
    ];
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    await _initialized.future;
    final api = await _ensureClient();
    if (api == null) return const [];
    try {
      return (await api.search(
        query,
        limit: 60,
      )).map((item) => vehicleBrowserMediaItem(api, item)).toList();
    } on JellyfinException catch (error) {
      if (error.isAuthenticationError) rethrow;
      return searchLocalMusic(await _store.offlineCatalog(api.session), query)
          .map(
            (item) => vehicleBrowserMediaItem(
              api,
              item,
            ).copyWith(id: 'offline:${item.type}:${item.id}'),
          )
          .toList();
    }
  }

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    await _initialized.future;
    if (query.trim().isEmpty) {
      await play();
      return;
    }
    final results = await search(query, extras);
    if (results.isEmpty) return;
    final firstSong = results.where((item) => item.playable == true);
    await playFromMediaId(
      firstSong.isEmpty ? results.first.id : firstSong.first.id,
    );
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    await _initialized.future;
    final api = await _ensureClient();
    if (api == null) return;
    if (mediaId.startsWith('offline:') ||
        mediaId.startsWith('action:offline:')) {
      final parsed = _parseBrowserId(
        mediaId.substring(mediaId.startsWith('action:') ? 15 : 8),
      );
      if (parsed == null) return;
      final (type, id) = parsed;
      final items = type == 'Audio'
          ? (await _store.loadDownloads(
              api.session,
            )).items.where((item) => item.id == id).toList()
          : await _store.collectionItems(
              api,
              JellyfinItem(id: id, name: '', type: type),
              offlineOnly: true,
            );
      if (items.isEmpty) {
        throw const JellyfinException('This music is not downloaded.');
      }
      await playItems(items);
      return;
    }
    if (mediaId == 'action:resume') {
      await play();
      return;
    }
    if (mediaId == 'action:shuffle') {
      await shuffleLibrary();
      return;
    }
    if (mediaId.startsWith('action:mix:')) {
      await playItems(await api.instantMix(mediaId.substring(11)));
      return;
    }
    final playCollection = mediaId.startsWith('action:play:');
    final parsed = _parseBrowserId(
      playCollection ? mediaId.substring(12) : mediaId,
    );
    if (parsed == null) return;
    final (type, id) = parsed;
    await playItems(await _playableItemsForBrowserId(api, type, id));
  }

  Future<List<Map<String, Object?>>> vehicleCatalog(String id) async {
    final items = id == 'root' ? vehicleRootItems() : await getChildren(id);
    return items
        .map(
          (item) => <String, Object?>{
            'id': item.id,
            'title': item.title,
            'subtitle': item.displaySubtitle ?? item.artist ?? item.album ?? '',
            'browsable': item.playable == false,
            'artworkUri': item.artUri?.toString(),
            'artworkHeaders': item.artHeaders,
          },
        )
        .toList();
  }

  Future<void> vehiclePlay(String id) => playFromMediaId(id);

  Future<void> playOnDevice(JellyfinDevice device) async {
    await _awaitClientTransition();
    final api = await _ensureClient();
    if (api == null) return;
    final items = queue.value.map(_original).whereType<JellyfinItem>().toList();
    if (items.isEmpty) {
      throw const JellyfinException('Start a queue before choosing a device.');
    }
    await api.playOnDevice(
      device,
      items,
      startIndex: _player.currentIndex ?? 0,
      position: _player.position,
    );
    await pause();
  }

  Future<JellyfinClient?> _ensureClient() async {
    if (_client != null || _clientAttached) return _client;
    final session = await _store.load();
    if (session == null) return null;
    final preferences = await _store.loadPreferences(session);
    return _client = JellyfinClient(session, preferences: preferences);
  }

  bool _sameSession(JellyfinSession? a, JellyfinSession? b) =>
      a?.serverUrl == b?.serverUrl &&
      a?.userId == b?.userId &&
      a?.deviceId == b?.deviceId &&
      a?.accessToken == b?.accessToken;

  Future<void> _clearPlayer() async {
    ++_queueGeneration;
    await _queueChanges;
    await _player.stop();
    await _player.clearAudioSources();
    _broadcastState();
  }

  Future<void> shuffleLibrary() async {
    await _awaitClientTransition();
    final api = await _ensureClient();
    if (api == null) return;
    try {
      final initial = await api.randomSongs();
      await playItems(initial, shuffle: true);
      final generation = _queueGeneration;
      _loadingLibraryQueue = true;
      unawaited(_appendLibrary(api, initial, generation));
    } on JellyfinException catch (error) {
      if (error.isAuthenticationError) rethrow;
      final offline = (await _store.loadDownloads(api.session)).items;
      if (offline.isEmpty) rethrow;
      await playItems(offline, shuffle: true);
    }
  }

  Future<void> _appendLibrary(
    JellyfinClient api,
    List<JellyfinItem> initial,
    int generation,
  ) async {
    final seen = initial.map((item) => item.id).toSet();
    try {
      await for (final batch in api.songBatches()) {
        if (generation != _queueGeneration || !identical(api, _client)) return;
        final additions = materializedShuffle(
          batch.where((item) => seen.add(item.id)),
        );
        final sources = await _audioSources(api, additions);
        await _editQueue(() async {
          if (generation != _queueGeneration || !identical(api, _client)) {
            return;
          }
          await _player.addAudioSources(sources);
          queue.add([
            ...queue.value,
            ...additions.map((item) => _queueMediaItem(api, item)),
          ]);
        });
      }
    } on Object {
      if (generation == _queueGeneration) {
        customEvent.add({
          'type': 'queueLoadingError',
          'message':
              'The rest of the library could not load. Retry Shuffle your library when connected.',
        });
      }
    } finally {
      if (generation == _queueGeneration) {
        _loadingLibraryQueue = false;
        await _persist();
      }
    }
  }

  Future<void> _replaceClient(JellyfinClient? value) async {
    await _clearPlayer();
    if (value != null && identical(_client, value)) await _restoreQueue();
  }

  Future<void> _awaitClientTransition() async {
    while (true) {
      final transition = _clientTransition;
      await transition;
      if (identical(transition, _clientTransition)) return;
    }
  }

  Future<List<JellyfinItem>> _childrenForBrowserId(
    JellyfinClient api,
    String mediaId,
  ) async {
    final parsed = _parseBrowserId(mediaId);
    if (parsed == null) return const [];
    final (type, id) = parsed;
    return _store.collectionItems(
      api,
      JellyfinItem(id: id, name: '', type: type),
    );
  }

  Future<List<JellyfinItem>> _playableItemsForBrowserId(
    JellyfinClient api,
    String type,
    String id,
  ) async {
    if (type == 'Audio') {
      final local = (await _store.loadDownloads(
        api.session,
      )).items.where((item) => item.id == id);
      return [local.firstOrNull ?? await api.item(id)];
    }
    return (await _store.collectionItems(
      api,
      JellyfinItem(id: id, name: '', type: type),
    )).where((item) => item.isAudio).toList();
  }

  (String, String)? _parseBrowserId(String mediaId) {
    final separator = mediaId.indexOf(':');
    if (separator < 1 || separator == mediaId.length - 1) return null;
    return (mediaId.substring(0, separator), mediaId.substring(separator + 1));
  }

  MediaItem _queueMediaItem(JellyfinClient api, JellyfinItem item) =>
      vehiclePlayingMediaItem(
        api,
        item,
        'queue:${_nextQueueItemId++}',
        artwork: _artwork[item.artworkId],
      );

  Future<List<AudioSource>> _audioSources(
    JellyfinClient api,
    List<JellyfinItem> items,
  ) async {
    _artwork = await _store.downloadedArtwork(api.session);
    final local = await _store.downloadedUris(
      api.session,
      items.map((item) => item.id),
    );
    return [for (final item in items) _sourceForUri(api, item, local[item.id])];
  }

  Future<AudioSource> _audioSource(
    JellyfinClient api,
    JellyfinItem item,
  ) async {
    _artwork = await _store.downloadedArtwork(api.session);
    final local = await _store.downloadedUris(api.session, [item.id]);
    return _sourceForUri(api, item, local[item.id]);
  }

  AudioSource _sourceForUri(
    JellyfinClient api,
    JellyfinItem item,
    Uri? local,
  ) => AudioSource.uri(
    local ??
        api.streamUri(
          item.id,
          sourceContainer: item.container,
          mediaSourceId: item.mediaSourceId,
          audioBitDepth: item.audioBitDepth,
        ),
    headers: local == null ? api.authorizationHeaders : null,
    tag: item.id,
  );

  JellyfinItem? _original(MediaItem item) {
    final value = item.extras?['jellyfin'];
    if (value is! Map) return null;
    return JellyfinItem.fromJson(value.cast<String, dynamic>());
  }

  void _onIndexChanged(int? index) {
    if (_disposed || _mutatingQueue) return;
    if (index == null || index < 0 || index >= queue.value.length) return;
    final next = queue.value[index];
    if (_reportedQueueId != null && _reportedQueueId != next.id) {
      unawaited(_reportStopped());
    }
    mediaItem.add(next);
    if (_player.playing && _reportedQueueId != next.id) {
      unawaited(_report('start'));
    }
    _broadcastState();
    _scheduleSave();
  }

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        errorMessage: _playbackError,
        processingState: _playbackError != null
            ? AudioProcessingState.error
            : switch (_player.processingState) {
                ProcessingState.idle =>
                  queue.value.isEmpty
                      ? AudioProcessingState.idle
                      : AudioProcessingState.ready,
                ProcessingState.loading => AudioProcessingState.loading,
                ProcessingState.buffering => AudioProcessingState.buffering,
                ProcessingState.ready => AudioProcessingState.ready,
                ProcessingState.completed => AudioProcessingState.completed,
              },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
        shuffleMode: _shuffled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (_player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
      ),
    );
  }

  Future<void> _report(String event) async {
    final api = _client;
    final item = mediaItem.value;
    final original = item == null ? null : _original(item);
    if (api == null || item == null || original == null) return;
    if (event == 'start') {
      _reportedQueueId = item.id;
      _reportedItemId = original.id;
    }
    final position = _player.position;
    _reportedPosition = position;
    try {
      await api.reportPlayback(
        event,
        original.id,
        position,
        paused: !_player.playing,
      );
    } on Object catch (error) {
      customEvent.add({'type': 'reportingError', 'message': '$error'});
    }
  }

  Future<void> _reportStopped() async {
    final id = _reportedItemId;
    final api = _client;
    if (id == null || api == null) return;
    _reportedQueueId = null;
    _reportedItemId = null;
    try {
      await api.reportPlayback('stop', id, _reportedPosition);
    } on Object catch (error) {
      customEvent.add({'type': 'reportingError', 'message': '$error'});
    }
  }

  void _scheduleSave() {
    if (_disposed) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_persist()),
    );
  }

  Future<void> _persist() async {
    if (_disposed || _mutatingQueue) return;
    final api = _client;
    if (api == null) return;
    try {
      await _store.savePlayback({
        'serverUrl': api.session.serverUrl,
        'userId': api.session.userId,
        'queue': [
          for (final item in queue.value)
            if (_original(item) case final original?) original.toJson(),
        ],
        'index': _player.currentIndex ?? 0,
        'positionUs': _player.position.inMicroseconds,
        'shuffle': _shuffled,
        'queueOrderVersion': 2,
        'libraryQueueIncomplete': _loadingLibraryQueue,
        'repeat': _player.loopMode.name,
      });
      _persistenceFailed = false;
    } on Object {
      if (!_persistenceFailed) {
        customEvent.add({
          'type': 'queueSaveError',
          'message':
              'Playback state could not be saved. Free device storage before closing the app.',
        });
      }
      _persistenceFailed = true;
    }
  }

  Future<void> _restoreQueue() async {
    final api = _client;
    final saved = await _store.loadPlayback();
    if (api == null ||
        saved == null ||
        (saved['serverUrl'] is String &&
            saved['serverUrl'] != api.session.serverUrl) ||
        (saved['userId'] is String && saved['userId'] != api.session.userId)) {
      return;
    }
    var items = (saved['queue'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => JellyfinItem.fromJson(value.cast<String, dynamic>()))
        .where((item) => item.id.isNotEmpty)
        .toList();
    if (items.isEmpty) return;
    var index = ((saved['index'] as num?)?.toInt() ?? 0).clamp(
      0,
      items.length - 1,
    );
    if (saved['shuffle'] == true && saved['queueOrderVersion'] != 2) {
      final order = validShuffleOrder(saved['shuffleOrder'], items.length);
      if (order != null) {
        items = [for (final oldIndex in order) items[oldIndex]];
        index = order.indexOf(index);
      }
    }
    final position = Duration(
      microseconds: max(0, (saved['positionUs'] as num?)?.toInt() ?? 0),
    );
    final sources = await _audioSources(api, items);
    queue.add(items.map((item) => _queueMediaItem(api, item)).toList());
    mediaItem.add(queue.value[index]);
    _shuffled = saved['shuffle'] == true;
    await _player.setShuffleModeEnabled(false);
    await _player.setAudioSources(
      sources,
      initialIndex: index,
      initialPosition: position,
      preload: false,
    );
    // just_audio leaves the idle player's cursor at zero until explicitly sought.
    await _player.seek(position, index: index);
    if (saved['libraryQueueIncomplete'] == true) {
      _loadingLibraryQueue = true;
      unawaited(_appendLibrary(api, items, _queueGeneration));
    }
    await _player.setLoopMode(switch (saved['repeat']) {
      'one' => LoopMode.one,
      'all' => LoopMode.all,
      _ => LoopMode.off,
    });
    mediaItem.add(queue.value[index]);
    _broadcastState();
    _scheduleSave();
  }

  Future<void> disposePlayer() async {
    if (_disposed) return;
    _disposed = true;
    _progressTimer?.cancel();
    _saveTimer?.cancel();
    ++_queueGeneration;
    await _queueChanges;
    unawaited(_reportStopped());
    await _player.dispose();
    await _store.flushPlayback();
  }
}
