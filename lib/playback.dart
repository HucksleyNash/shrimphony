import 'dart:async';
import 'dart:math';

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

int? queuePageTrimCount(
  int? currentIndex,
  int queueLength, {
  int loadAhead = 20,
  int history = 10,
}) {
  if (currentIndex == null ||
      currentIndex < 0 ||
      currentIndex >= queueLength ||
      queueLength - currentIndex - 1 > loadAhead) {
    return null;
  }
  return max(0, currentIndex - history);
}

({List<T> items, int index}) boundedQueueWindow<T>(
  List<T> items,
  int index, {
  int maxLength = 100,
  int history = 10,
}) {
  if (maxLength < 1) throw ArgumentError.value(maxLength, 'maxLength');
  if (items.isEmpty) return (items: const [], index: 0);
  final safeIndex = index.clamp(0, items.length - 1).toInt();
  if (items.length <= maxLength) return (items: items, index: safeIndex);
  final start = min(
    max(0, safeIndex - max(0, history)),
    items.length - maxLength,
  ).toInt();
  return (
    items: items.sublist(start, start + maxLength),
    index: safeIndex - start,
  );
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
  String id,
) {
  final artworkId = item.artworkId;
  final localArtwork = artworkId == null ? null : vehicleArtworkUri(artworkId);
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
      if (localArtwork != null)
        'android.media.metadata.ALBUM_ART_URI': localArtwork.toString(),
      if (artworkId != null) 'remoteArtUri': api.imageUri(artworkId).toString(),
    },
  );
}

MediaItem vehicleBrowserMediaItem(
  JellyfinClient api,
  JellyfinItem item, {
  String? groupTitle,
}) => MediaItem(
  id: '${item.type}:${item.id}',
  title: item.name,
  album: item.album,
  artist: item.artists.join(', '),
  displaySubtitle: item.subtitle,
  duration: item.duration,
  artUri: switch (item.artworkId) {
    final id? => vehicleArtworkUri(id),
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

Future<void> _configureVehicleArtwork(String? serverUrl) async {
  try {
    await _androidAutoChannel.invokeMethod<void>('configureArtwork', {
      'serverUrl': serverUrl,
    });
  } on MissingPluginException {
    // Android-only integration.
  } on PlatformException {
    // Browsing still works without artwork if the native bridge is unavailable.
  }
}

class _RestoredShuffleOrder extends DefaultShuffleOrder {
  _RestoredShuffleOrder(this._restored);

  final List<int> _restored;
  bool _used = false;

  @override
  void insert(int index, int count) {
    if (!_used && index == 0 && count == _restored.length) {
      indices.addAll(_restored);
      _used = true;
      return;
    }
    super.insert(index, count);
  }
}

class JellyfinAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  JellyfinAudioHandler(this._store)
    : _player = AudioPlayer(
        userAgent: '$appName/$appVersion',
        maxSkipsOnError: 3,
      ) {
    _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stack) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorMessage: 'Playback failed: $error',
          ),
        );
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
  Timer? _progressTimer;
  Timer? _saveTimer;
  Future<void> _clientTransition = Future.value();
  Future<void> _batchAppend = Future.value();
  StreamIterator<List<JellyfinItem>>? _shufflePages;
  final Set<String> _shuffleSeen = {};
  bool _loadingShufflePage = false;
  bool _mutatingQueue = false;
  bool _pagedShuffle = false;
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
    await _configureVehicleArtwork(_client?.session.serverUrl);
    await _restoreQueue();
    _broadcastState();
    _initialized.complete();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_player.playing) unawaited(_report('progress'));
      unawaited(_persist());
    });
  }

  void attachClient(JellyfinClient? value) {
    final previous = _client;
    _client = value;
    unawaited(_configureVehicleArtwork(value?.session.serverUrl));
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
    await _cancelShufflePaging();
    final generation = ++_queueGeneration;
    final requestedIndex = initialIndex?.clamp(0, items.length - 1);
    final playbackItems = shuffle ? materializedShuffle(items) : items;
    final safeIndex = requestedIndex == null
        ? 0
        : playbackItems.indexOf(items[requestedIndex]);
    final mediaItems = playbackItems
        .map((item) => _queueMediaItem(api, item))
        .toList();
    final sources = await _audioSources(api, playbackItems);
    _reportedPosition = _player.position;
    await _reportStopped();
    await _batchAppend;
    if (generation != _queueGeneration) return;
    queue.add(mediaItems);
    await _player.setAudioSources(
      sources,
      initialIndex: safeIndex,
      initialPosition: Duration.zero,
      preload: true,
      shuffleOrder: DefaultShuffleOrder(),
    );
    await setShuffleMode(
      shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    mediaItem.add(mediaItems[safeIndex]);
    await play();
    _scheduleSave();
  }

  Future<void> playItem(JellyfinItem item, {List<JellyfinItem>? context}) {
    final items = context ?? [item];
    final identicalIndex = items.indexOf(item);
    final index = identicalIndex < 0
        ? items.indexWhere((candidate) => candidate.id == item.id)
        : identicalIndex;
    return playItems(items, initialIndex: index < 0 ? 0 : index);
  }

  Future<void> playNext(JellyfinItem item) async {
    await _awaitClientTransition();
    final api = await _ensureClient();
    if (api == null) return;
    final index = (_player.currentIndex ?? -1) + 1;
    await _player.insertAudioSource(
      index.clamp(0, _player.sequence.length),
      await _audioSource(api, item),
    );
    final updated = [...queue.value];
    updated.insert(index.clamp(0, updated.length), _queueMediaItem(api, item));
    queue.add(updated);
    _scheduleSave();
  }

  Future<void> clearQueue() async {
    await _awaitClientTransition();
    ++_queueGeneration;
    await _cancelShufflePaging();
    await _batchAppend;
    _reportedPosition = _player.position;
    await _reportStopped();
    await _player.stop();
    await _player.clearAudioSources();
    queue.add(const []);
    mediaItem.add(null);
    await _persist();
    _broadcastState();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    await _awaitClientTransition();
    final api = await _ensureClient();
    final original = _original(mediaItem);
    if (api == null || original == null) return;
    await _player.addAudioSource(await _audioSource(api, original));
    queue.add([...queue.value, mediaItem]);
    _scheduleSave();
  }

  Future<void> addItemToQueue(JellyfinItem item) async {
    final api = await _ensureClient();
    if (api == null) return;
    await addQueueItem(_queueMediaItem(api, item));
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    await _awaitClientTransition();
    final index = queue.value.indexOf(mediaItem);
    if (index < 0) return;
    await _player.removeAudioSourceAt(index);
    final updated = [...queue.value]..removeAt(index);
    queue.add(updated);
    _scheduleSave();
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    await _awaitClientTransition();
    if (oldIndex < 0 || oldIndex >= queue.value.length) return;
    final destination = newIndex.clamp(0, queue.value.length - 1);
    if (oldIndex == destination) return;
    await _player.moveAudioSource(oldIndex, destination);
    final updated = [...queue.value];
    final item = updated.removeAt(oldIndex);
    updated.insert(destination, item);
    queue.add(updated);
    _scheduleSave();
  }

  @override
  Future<void> play() async {
    await _initialized.future;
    await _awaitClientTransition();
    if (_player.sequence.isEmpty) return;
    unawaited(_player.play());
    await _report('progress');
  }

  @override
  Future<void> pause() async {
    await _awaitClientTransition();
    await _player.pause();
    await _report('progress');
    await _persist();
  }

  @override
  Future<void> stop() async {
    await _awaitClientTransition();
    _reportedPosition = _player.position;
    await _reportStopped();
    await _player.stop();
    await _persist();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _awaitClientTransition();
    await _player.seek(position);
    await _report('progress');
    _scheduleSave();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _awaitClientTransition();
    if (index < 0 || index >= queue.value.length) return;
    _reportedPosition = _player.position;
    await _player.seek(Duration.zero, index: index);
    _scheduleSave();
  }

  @override
  Future<void> skipToNext() async {
    await _awaitClientTransition();
    if (_player.hasNext) {
      _reportedPosition = _player.position;
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
    if (_shufflePages != null || _pagedShuffle) {
      _pagedShuffle = enabled;
      await _player.setShuffleModeEnabled(false);
      playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
      _scheduleSave();
      return;
    }
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
    _scheduleSave();
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
      'browse:favorites' => await api.favorites(limit: 50),
      'browse:albums' => await api.albums(limit: 100),
      'browse:artists' => await api.artists(limit: 100),
      'browse:playlists' => await api.playlists(limit: 100),
      'browse:genres' => await api.genres(limit: 100),
      'browse:downloads' => (await _store.loadDownloads(api.session)).items,
      _ => await _childrenForBrowserId(api, parentMediaId),
    };
    final parsed = _parseBrowserId(parentMediaId);
    return [
      if (parsed != null && parsed.$1 != 'Audio')
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
    return (await api.search(
      query,
      limit: 30,
    )).map((item) => vehicleBrowserMediaItem(api, item)).toList();
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
    final firstSong = results.where((item) => item.id.startsWith('Audio:'));
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
    if (mediaId == 'action:resume') {
      await play();
      return;
    }
    if (mediaId == 'action:shuffle') {
      await _shuffleAll(api);
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
    if (_client != null) return _client;
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
    await _cancelShufflePaging();
    await _batchAppend;
    await _player.stop();
    await _player.clearAudioSources();
    _broadcastState();
  }

  Future<void> _shuffleAll(JellyfinClient api) async {
    final initial = materializedShuffle(await api.randomSongs());
    if (initial.isEmpty) return;
    final previousGeneration = _queueGeneration;
    await playItems(initial);
    final generation = _queueGeneration;
    if (generation != previousGeneration + 1 || !identical(api, _client)) {
      return;
    }
    _shuffleSeen
      ..clear()
      ..addAll(initial.map((item) => item.id));
    _shufflePages = StreamIterator(api.songBatches(batchSize: 100));
    _pagedShuffle = true;
    _broadcastState();
  }

  Future<void> _loadNextShufflePage() async {
    final pages = _shufflePages;
    final api = _client;
    final generation = _queueGeneration;
    if (_loadingShufflePage || pages == null || api == null) return;
    bool current() =>
        generation == _queueGeneration &&
        identical(api, _client) &&
        identical(pages, _shufflePages);
    _loadingShufflePage = true;
    try {
      while (current() && await pages.moveNext()) {
        final additions = materializedShuffle(
          pages.current
              .where((item) => item.isAudio && _shuffleSeen.add(item.id))
              .toList(),
        );
        if (additions.isEmpty) continue;
        final sources = await _audioSources(api, additions);
        if (!current()) return;
        final operation = _appendShufflePage(
          api,
          generation,
          additions,
          sources,
        );
        _batchAppend = operation.then<void>((_) {}, onError: (_, _) {});
        await operation;
        return;
      }
      if (current()) {
        _shufflePages = null;
        await pages.cancel();
      }
    } on Object catch (error) {
      if (current()) {
        _shufflePages = null;
        customEvent.add({'type': 'queueLoadingError', 'message': '$error'});
        await pages.cancel();
      }
    } finally {
      _loadingShufflePage = false;
    }
  }

  Future<void> _appendShufflePage(
    JellyfinClient api,
    int generation,
    List<JellyfinItem> additions,
    List<AudioSource> sources,
  ) async {
    bool current() => generation == _queueGeneration && identical(api, _client);
    if (!current()) return;
    final currentIndex = _player.currentIndex ?? 0;
    final trim = min(max(0, currentIndex - 10), queue.value.length);
    var updated = queue.value;
    _mutatingQueue = true;
    try {
      if (trim > 0) {
        await _player.removeAudioSourceRange(0, trim);
        if (!current()) return;
        updated = updated.sublist(trim);
        queue.add(updated);
      }
      await _player.addAudioSources(sources);
      if (!current()) return;
      queue.add([
        ...updated,
        ...additions.map((item) => _queueMediaItem(api, item)),
      ]);
      _scheduleSave();
    } finally {
      _mutatingQueue = false;
      if (current()) _onIndexChanged(_player.currentIndex);
    }
  }

  Future<void> _cancelShufflePaging() async {
    final pages = _shufflePages;
    _shufflePages = null;
    _pagedShuffle = false;
    _shuffleSeen.clear();
    if (pages != null) await pages.cancel();
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
    return switch (type) {
      'MusicArtist' => api.albumsForArtist(id),
      'MusicGenre' => api.songsForGenre(id),
      'Playlist' => api.playlistItems(id),
      _ => api.children(id),
    };
  }

  Future<List<JellyfinItem>> _playableItemsForBrowserId(
    JellyfinClient api,
    String type,
    String id,
  ) => switch (type) {
    'Audio' => api.item(id).then((item) => [item]),
    'MusicAlbum' => api.children(id),
    'MusicArtist' => api.songsForArtist(id),
    'MusicGenre' => api.songsForGenre(id),
    'Playlist' => api.playlistItems(id),
    _ => Future.value(const []),
  };

  (String, String)? _parseBrowserId(String mediaId) {
    final separator = mediaId.indexOf(':');
    if (separator < 1 || separator == mediaId.length - 1) return null;
    return (mediaId.substring(0, separator), mediaId.substring(separator + 1));
  }

  MediaItem _queueMediaItem(JellyfinClient api, JellyfinItem item) =>
      vehiclePlayingMediaItem(api, item, 'queue:${_nextQueueItemId++}');

  Future<List<AudioSource>> _audioSources(
    JellyfinClient api,
    List<JellyfinItem> items,
  ) async {
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
    final local = await _store.downloadedUris(api.session, [item.id]);
    return _sourceForUri(api, item, local[item.id]);
  }

  AudioSource _sourceForUri(
    JellyfinClient api,
    JellyfinItem item,
    Uri? local,
  ) => AudioSource.uri(
    local ?? api.streamUri(item.id),
    headers: local == null ? api.authorizationHeaders : null,
    tag: item.id,
  );

  JellyfinItem? _original(MediaItem item) {
    final value = item.extras?['jellyfin'];
    if (value is! Map) return null;
    return JellyfinItem.fromJson(value.cast<String, dynamic>());
  }

  void _onIndexChanged(int? index) {
    if (_mutatingQueue) return;
    if (index == null || index < 0 || index >= queue.value.length) return;
    final next = queue.value[index];
    if (_reportedQueueId != null && _reportedQueueId != next.id) {
      unawaited(_reportStopped());
    }
    mediaItem.add(next);
    if (_reportedQueueId != next.id) {
      unawaited(_report('start'));
    }
    _broadcastState();
    _scheduleSave();
    if (_shufflePages != null &&
        queuePageTrimCount(index, queue.value.length) != null) {
      unawaited(_loadNextShufflePage());
    }
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
        processingState: switch (_player.processingState) {
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
        shuffleMode: _pagedShuffle || _player.shuffleModeEnabled
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
    try {
      await api.reportPlayback(
        event,
        original.id,
        _player.position,
        paused: !_player.playing,
      );
      _reportedPosition = _player.position;
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
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_persist()),
    );
  }

  Future<void> _persist() async {
    final api = _client;
    if (api == null) return;
    await _store.savePlayback({
      'serverUrl': api.session.serverUrl,
      'userId': api.session.userId,
      'queue': [
        for (final item in queue.value)
          if (_original(item) case final original?) original.toJson(),
      ],
      'index': _player.currentIndex ?? 0,
      'positionUs': _player.position.inMicroseconds,
      'shuffle': _pagedShuffle || _player.shuffleModeEnabled,
      'shuffleOrder': _player.shuffleIndices,
      'repeat': _player.loopMode.name,
    });
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
    final savedLength = items.length;
    final window = boundedQueueWindow(items, index);
    items = window.items;
    index = window.index;
    final position = Duration(
      microseconds: max(0, (saved['positionUs'] as num?)?.toInt() ?? 0),
    );
    final shuffleOrder = savedLength == items.length
        ? validShuffleOrder(saved['shuffleOrder'], items.length)
        : null;
    queue.add(items.map((item) => _queueMediaItem(api, item)).toList());
    await _player.setAudioSources(
      await _audioSources(api, items),
      initialIndex: index,
      initialPosition: position,
      preload: false,
      shuffleOrder: shuffleOrder == null
          ? DefaultShuffleOrder()
          : _RestoredShuffleOrder(shuffleOrder),
    );
    if (saved['shuffle'] == true) {
      await _player.setShuffleModeEnabled(true);
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
    _progressTimer?.cancel();
    _saveTimer?.cancel();
    ++_queueGeneration;
    await _cancelShufflePaging();
    await _batchAppend;
    await _reportStopped();
    await _player.dispose();
  }
}
