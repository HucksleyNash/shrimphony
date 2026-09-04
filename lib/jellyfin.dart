import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

const appName = 'Shrimphony';
const appVersion = '1.0.0';

enum AppStatus { booting, signedOut, loading, ready, error }

enum StreamingQuality { original, high, normal, dataSaver }

extension StreamingQualityDetails on StreamingQuality {
  String get label => switch (this) {
    StreamingQuality.original => 'Original / server decides',
    StreamingQuality.high => 'High (320 kbps)',
    StreamingQuality.normal => 'Normal (192 kbps)',
    StreamingQuality.dataSaver => 'Data saver (96 kbps)',
  };

  int get maxBitrate => switch (this) {
    StreamingQuality.original => 140000000,
    StreamingQuality.high => 320000,
    StreamingQuality.normal => 192000,
    StreamingQuality.dataSaver => 96000,
  };
}

class AppPreferences {
  const AppPreferences({
    this.musicLibraryIds = const {},
    this.streamingQuality = StreamingQuality.original,
    this.downloadLimitBytes = 0,
    this.wifiOnlyDownloads = false,
  });

  final Set<String> musicLibraryIds;
  final StreamingQuality streamingQuality;
  final int downloadLimitBytes;
  final bool wifiOnlyDownloads;

  AppPreferences copyWith({
    Set<String>? musicLibraryIds,
    StreamingQuality? streamingQuality,
    int? downloadLimitBytes,
    bool? wifiOnlyDownloads,
  }) => AppPreferences(
    musicLibraryIds: musicLibraryIds ?? this.musicLibraryIds,
    streamingQuality: streamingQuality ?? this.streamingQuality,
    downloadLimitBytes: downloadLimitBytes ?? this.downloadLimitBytes,
    wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
  );

  Map<String, dynamic> toJson() => {
    'musicLibraryIds': musicLibraryIds.toList(),
    'streamingQuality': streamingQuality.name,
    'downloadLimitBytes': downloadLimitBytes,
    'wifiOnlyDownloads': wifiOnlyDownloads,
  };

  factory AppPreferences.fromJson(Map<String, dynamic> json) => AppPreferences(
    downloadLimitBytes: max(
      0,
      (json['downloadLimitBytes'] as num?)?.toInt() ?? 0,
    ),
    wifiOnlyDownloads: json['wifiOnlyDownloads'] == true,
    musicLibraryIds: (json['musicLibraryIds'] as List? ?? const [])
        .whereType<String>()
        .toSet(),
    streamingQuality: StreamingQuality.values.firstWhere(
      (value) => value.name == json['streamingQuality'],
      orElse: () => StreamingQuality.original,
    ),
  );
}

class JellyfinLibrary {
  const JellyfinLibrary({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory JellyfinLibrary.fromJson(Map<String, dynamic> json) =>
      JellyfinLibrary(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Music',
      );
}

class JellyfinDevice {
  const JellyfinDevice({
    required this.id,
    required this.name,
    required this.client,
  });

  final String id;
  final String name;
  final String client;
}

class JellyfinException implements Exception {
  const JellyfinException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isAuthenticationError => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class JellyfinSession {
  const JellyfinSession({
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
    required this.username,
    required this.deviceId,
  });

  final String serverUrl;
  final String accessToken;
  final String userId;
  final String username;
  final String deviceId;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'accessToken': accessToken,
    'userId': userId,
    'username': username,
    'deviceId': deviceId,
  };

  factory JellyfinSession.fromJson(Map<String, dynamic> json) =>
      JellyfinSession(
        serverUrl: json['serverUrl'] as String,
        accessToken: json['accessToken'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        deviceId: json['deviceId'] as String,
      );
}

class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.name,
    required this.type,
    this.sortName,
    this.albumArtist,
    this.genreNames = const [],
    this.album,
    this.albumId,
    this.albumImageTag,
    this.artists = const [],
    this.artistIds = const [],
    this.duration = Duration.zero,
    this.productionYear,
    this.indexNumber,
    this.parentIndexNumber,
    this.imageTag,
    this.overview,
    this.isFavorite = false,
    this.dateCreated,
    this.lastPlayedDate,
    this.playbackPosition = Duration.zero,
    this.container,
    this.mediaSourceId,
    this.audioBitDepth,
    this.playlistItemId,
  });

  final String id;
  final String name;
  final String type;
  final String? sortName;
  final String? albumArtist;
  final List<String> genreNames;
  final String? album;
  final String? albumId;
  final String? albumImageTag;
  final List<String> artists;
  final List<String> artistIds;
  final Duration duration;
  final int? productionYear;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? imageTag;
  final String? overview;
  final bool isFavorite;
  final DateTime? dateCreated;
  final DateTime? lastPlayedDate;
  final Duration playbackPosition;
  final String? container;
  final String? mediaSourceId;
  final int? audioBitDepth;
  final String? playlistItemId;

  bool get isAudio => type == 'Audio';
  bool get isAlbum => type == 'MusicAlbum';
  bool get isArtist => type == 'MusicArtist' || type == 'Artist';
  bool get isPlaylist => type == 'Playlist';
  bool get isGenre => type == 'MusicGenre';
  bool get isBrowsable => isAlbum || isArtist || isPlaylist || isGenre;
  String? get artworkId => imageTag?.isNotEmpty == true && id.isNotEmpty
      ? id
      : albumImageTag?.isNotEmpty == true && albumId?.isNotEmpty == true
      ? albumId
      : null;

  String get subtitle {
    if (isAudio) {
      return [if (artists.isNotEmpty) artists.join(', '), ?album].join(' • ');
    }
    if (artists.isNotEmpty) return artists.join(', ');
    if (productionYear != null) return '$productionYear';
    if (isAlbum) return 'Album';
    if (isArtist) return 'Artist';
    if (isPlaylist) return 'Playlist';
    if (isGenre) return 'Genre';
    return '';
  }

  JellyfinItem copyWith({String? name, bool? isFavorite}) => JellyfinItem(
    id: id,
    name: name ?? this.name,
    type: type,
    sortName: sortName,
    albumArtist: albumArtist,
    genreNames: genreNames,
    album: album,
    albumId: albumId,
    albumImageTag: albumImageTag,
    artists: artists,
    artistIds: artistIds,
    duration: duration,
    productionYear: productionYear,
    indexNumber: indexNumber,
    parentIndexNumber: parentIndexNumber,
    imageTag: imageTag,
    overview: overview,
    isFavorite: isFavorite ?? this.isFavorite,
    dateCreated: dateCreated,
    lastPlayedDate: lastPlayedDate,
    playbackPosition: playbackPosition,
    container: container,
    mediaSourceId: mediaSourceId,
    audioBitDepth: audioBitDepth,
    playlistItemId: playlistItemId,
  );

  Map<String, dynamic> toJson() => {
    'Id': id,
    'Name': name,
    'Type': type,
    'SortName': sortName,
    'AlbumArtist': albumArtist,
    'Genres': genreNames,
    'Album': album,
    'AlbumId': albumId,
    'AlbumPrimaryImageTag': albumImageTag,
    'Artists': artists,
    'ArtistItems': [
      for (var i = 0; i < artistIds.length; i++)
        {'Id': artistIds[i], 'Name': i < artists.length ? artists[i] : ''},
    ],
    'RunTimeTicks': duration.inMicroseconds * 10,
    'ProductionYear': productionYear,
    'IndexNumber': indexNumber,
    'ParentIndexNumber': parentIndexNumber,
    if (imageTag != null) 'ImageTags': {'Primary': imageTag},
    'Overview': overview,
    'DateCreated': dateCreated?.toUtc().toIso8601String(),
    'Container': container,
    'MediaSourceId': mediaSourceId,
    'AudioBitDepth': audioBitDepth,
    'PlaylistItemId': playlistItemId,
    'UserData': {
      'IsFavorite': isFavorite,
      'LastPlayedDate': lastPlayedDate?.toUtc().toIso8601String(),
      'PlaybackPositionTicks': playbackPosition.inMicroseconds * 10,
    },
  };

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    final artistItems = (json['ArtistItems'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    final artists = (json['Artists'] as List? ?? const [])
        .whereType<String>()
        .toList();
    if (artists.isEmpty) {
      artists.addAll(
        artistItems.map((item) => item['Name']).whereType<String>(),
      );
    }
    final imageTags = (json['ImageTags'] as Map?)?.cast<String, dynamic>();
    final userData = (json['UserData'] as Map?)?.cast<String, dynamic>();
    final mediaSources = (json['MediaSources'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => value.cast<String, dynamic>())
        .toList();
    final audioStream =
        ((json['MediaStreams'] ?? mediaSources.firstOrNull?['MediaStreams'])
                    as List? ??
                const [])
            .whereType<Map>()
            .where((stream) => stream['Type'] == 'Audio')
            .firstOrNull;
    final ticks = (json['RunTimeTicks'] as num?)?.toInt() ?? 0;
    return JellyfinItem(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? 'Untitled',
      type: json['Type'] as String? ?? 'Unknown',
      sortName: json['SortName'] as String?,
      albumArtist: json['AlbumArtist'] as String?,
      genreNames: (json['Genres'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      album: json['Album'] as String?,
      albumId: json['AlbumId'] as String?,
      albumImageTag: json['AlbumPrimaryImageTag'] as String?,
      artists: artists,
      artistIds: artistItems
          .map((item) => item['Id'])
          .whereType<String>()
          .toList(),
      duration: Duration(microseconds: ticks ~/ 10),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      imageTag: imageTags?['Primary'] as String?,
      overview: json['Overview'] as String?,
      isFavorite: userData?['IsFavorite'] as bool? ?? false,
      dateCreated: DateTime.tryParse(json['DateCreated'] as String? ?? ''),
      lastPlayedDate: DateTime.tryParse(
        userData?['LastPlayedDate'] as String? ?? '',
      ),
      playbackPosition: Duration(
        microseconds:
            ((userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0) ~/ 10,
      ),
      audioBitDepth:
          ((json['AudioBitDepth'] ?? audioStream?['BitDepth']) as num?)
              ?.toInt(),
      mediaSourceId:
          json['MediaSourceId'] as String? ??
          mediaSources.firstOrNull?['Id'] as String?,
      container:
          json['Container'] as String? ??
          (mediaSources.isEmpty
              ? null
              : mediaSources.first['Container'] as String?),
      playlistItemId: json['PlaylistItemId'] as String?,
    );
  }
}

String safeAudioExtension(String? value) {
  final candidate = (value ?? '')
      .split(',')
      .first
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]'), '');
  return switch (candidate) {
    'mpeg' => 'mp3',
    'mp4' || 'xmp4' => 'm4a',
    'xflac' => 'flac',
    'wave' || 'xwav' => 'wav',
    'mp3' ||
    'm4a' ||
    'aac' ||
    'flac' ||
    'ogg' ||
    'opus' ||
    'wav' ||
    'webm' => candidate,
    _ => 'audio',
  };
}

bool canPlayOriginalOffline(String? container, {int? audioBitDepth}) =>
    !(Platform.isIOS &&
        safeAudioExtension(container) == 'flac' &&
        (audioBitDepth ?? 0) > 24) &&
    const {
      'mp3',
      'm4a',
      'aac',
      'flac',
      'wav',
    }.contains(safeAudioExtension(container));

List<JellyfinItem> pendingAudioDownloads(
  Iterable<JellyfinItem> items,
  Iterable<String> excludedIds,
) {
  final seen = excludedIds.toSet();
  return [
    for (final item in items)
      if (item.isAudio && item.id.isNotEmpty && seen.add(item.id)) item,
  ];
}

void sortJellyfinItems(
  List<JellyfinItem> items,
  String sortBy, {
  bool descending = false,
}) {
  final keys = sortBy.split(',');
  int text(String? a, String? b) =>
      (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());
  items.sort((a, b) {
    for (final key in keys) {
      final comparison = switch (key) {
        'DateCreated' => (a.dateCreated ?? DateTime(1970)).compareTo(
          b.dateCreated ?? DateTime(1970),
        ),
        'DatePlayed' => (a.lastPlayedDate ?? DateTime(1970)).compareTo(
          b.lastPlayedDate ?? DateTime(1970),
        ),
        'ProductionYear' => (a.productionYear ?? 0).compareTo(
          b.productionYear ?? 0,
        ),
        'ParentIndexNumber' => (a.parentIndexNumber ?? 0).compareTo(
          b.parentIndexNumber ?? 0,
        ),
        'IndexNumber' => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0),
        'AlbumArtist' => text(
          a.albumArtist ?? a.artists.firstOrNull,
          b.albumArtist ?? b.artists.firstOrNull,
        ),
        'Album' => text(a.album, b.album),
        _ => text(a.sortName ?? a.name, b.sortName ?? b.name),
      };
      if (comparison != 0) return descending ? -comparison : comparison;
    }
    return a.id.compareTo(b.id);
  });
}

List<JellyfinItem> searchLocalMusic(Iterable<JellyfinItem> items, String term) {
  final words = term.trim().toLowerCase().split(RegExp(r'\s+'));
  if (term.trim().isEmpty) return [];
  return {
    for (final item in items)
      if (words.every(
        ('${item.name} ${item.subtitle} ${item.genreNames.join(' ')}')
            .toLowerCase()
            .contains,
      ))
        item.id: item,
  }.values.toList();
}

class JellyfinSessionStore {
  JellyfinSessionStore({FlutterSecureStorage? storage, this.supportDirectory})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'jellyfin_session';
  static const _serversKey = 'jellyfin_servers';
  static const _preferencesKey = 'jellyfin_preferences';
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _storage;
  final Directory? supportDirectory;
  Future<void> _playbackWrite = Future.value();
  Future<void> _dataWrite = Future.value();
  Future<void> _downloadWrite = Future.value();

  Future<JellyfinSession?> load() async {
    final value = await _storage.read(key: _sessionKey, iOptions: _iosOptions);
    if (value == null) return null;
    try {
      return JellyfinSession.fromJson(
        (jsonDecode(value) as Map).cast<String, dynamic>(),
      );
    } on Object {
      await _storage.delete(key: _sessionKey, iOptions: _iosOptions);
      return null;
    }
  }

  Future<List<JellyfinSession>> loadAll() async {
    final value = await _storage.read(key: _serversKey, iOptions: _iosOptions);
    if (value == null) {
      final active = await load();
      return [?active];
    }
    try {
      return (jsonDecode(value) as List)
          .whereType<Map>()
          .map(
            (value) => JellyfinSession.fromJson(value.cast<String, dynamic>()),
          )
          .toList();
    } on Object {
      await _storage.delete(key: _serversKey, iOptions: _iosOptions);
      final active = await load();
      return [?active];
    }
  }

  Future<void> save(
    JellyfinSession session, {
    String? replacingDeviceId,
  }) async {
    final active = await load();
    final servers = await loadAll();
    servers.removeWhere(
      (saved) =>
          saved.deviceId == replacingDeviceId ||
          (saved.serverUrl == session.serverUrl &&
              saved.username == session.username),
    );
    servers.insert(0, session);
    await _storage.write(
      key: _serversKey,
      value: jsonEncode(servers.map((server) => server.toJson()).toList()),
      iOptions: _iosOptions,
    );
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
      iOptions: _iosOptions,
    );
    if (active != null && active.deviceId != session.deviceId) {
      await _playbackWrite;
      final playback = await _playbackFile();
      if (await playback.exists()) await playback.delete();
    }
  }

  Future<void> remove(JellyfinSession session) async {
    await clearAccountData(session);
    final servers = await loadAll();
    servers.removeWhere((saved) => saved.deviceId == session.deviceId);
    await _storage.write(
      key: _serversKey,
      value: jsonEncode(servers.map((server) => server.toJson()).toList()),
      iOptions: _iosOptions,
    );
    if ((await load())?.deviceId == session.deviceId) await deactivate();
  }

  Future<void> deactivate({bool clearPlayback = true}) async {
    await _storage.delete(key: _sessionKey, iOptions: _iosOptions);
    if (!clearPlayback) return;
    await _playbackWrite;
    // ponytail: one queue belongs to the active server; clear it on switches.
    final playback = await _playbackFile();
    if (await playback.exists()) await playback.delete();
  }

  Future<Map<String, dynamic>?> loadPlayback() async {
    final file = await _playbackFile();
    if (!await file.exists()) return null;
    try {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
    } on Object {
      return null;
    }
  }

  Future<void> savePlayback(Map<String, dynamic> state) {
    final write = _playbackWrite.then((_) => _writePlayback(state));
    _playbackWrite = write.then<void>((_) {}, onError: (_, _) {});
    return write;
  }

  Future<void> flushPlayback() => _playbackWrite;

  Future<void> _writePlayback(Map<String, dynamic> state) async {
    final file = await _playbackFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(state), flush: true);
    await temporary.rename(file.path);
  }

  Future<AppPreferences> loadPreferences(JellyfinSession session) async {
    final value = await _storage.read(
      key: _preferencesKey,
      iOptions: _iosOptions,
    );
    if (value == null) return const AppPreferences();
    try {
      final all = (jsonDecode(value) as Map).cast<String, dynamic>();
      final saved = all[_preferenceId(session)];
      return saved is Map
          ? AppPreferences.fromJson(saved.cast<String, dynamic>())
          : const AppPreferences();
    } on Object {
      return const AppPreferences();
    }
  }

  Future<void> savePreferences(
    JellyfinSession session,
    AppPreferences preferences,
  ) async {
    final value = await _storage.read(
      key: _preferencesKey,
      iOptions: _iosOptions,
    );
    Map<String, dynamic> all;
    try {
      all = value == null
          ? <String, dynamic>{}
          : (jsonDecode(value) as Map).cast<String, dynamic>();
    } on Object {
      all = <String, dynamic>{};
    }
    all[_preferenceId(session)] = preferences.toJson();
    await _storage.write(
      key: _preferencesKey,
      value: jsonEncode(all),
      iOptions: _iosOptions,
    );
  }

  Future<Map<String, dynamic>?> loadLibraryCache(
    JellyfinSession session,
  ) async {
    final file = await _libraryCacheFile(session);
    if (!await file.exists()) return null;
    try {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
    } on Object {
      return null;
    }
  }

  Future<void> saveLibraryCache(
    JellyfinSession session,
    Map<String, dynamic> value,
  ) async {
    final file = await _libraryCacheFile(session);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }

  Future<({List<JellyfinItem> items, int bytes})> loadDownloads(
    JellyfinSession session,
  ) async {
    final directory = await _downloadDirectory(session);
    final items = <JellyfinItem>[];
    var bytes = 0;
    for (final record in await _downloadRecords(session)) {
      final item = record['item'];
      final name = record['file'];
      if (item is! Map || name is! String || !_safeDownloadName(name)) continue;
      final file = File('${directory.path}/$name');
      if (!await file.exists()) continue;
      final parsed = JellyfinItem.fromJson(item.cast<String, dynamic>());
      if (!parsed.isAudio || parsed.id.isEmpty) continue;
      items.add(parsed);
      bytes += await file.length();
    }
    return (items: items, bytes: bytes);
  }

  Future<Map<String, Uri>> downloadedUris(
    JellyfinSession session,
    Iterable<String> itemIds,
  ) async {
    final wanted = itemIds.toSet();
    final directory = await _downloadDirectory(session);
    final result = <String, Uri>{};
    for (final record in await _downloadRecords(session)) {
      final item = record['item'];
      final name = record['file'];
      if (item is! Map || name is! String || !_safeDownloadName(name)) continue;
      final id = item['Id'];
      if (id is! String || !wanted.contains(id)) continue;
      final file = File('${directory.path}/$name');
      if (await file.exists()) result[id] = file.uri;
    }
    return result;
  }

  Future<void> downloadTrack(
    JellyfinSession session,
    JellyfinClient client,
    JellyfinItem item, {
    void Function(int received, int? total)? onProgress,
    int? maxBytes,
  }) {
    final operation = _downloadWrite.then((_) async {
      if (!item.isAudio || item.id.isEmpty) {
        throw const JellyfinException('Only songs can be downloaded.');
      }
      if ((await downloadedUris(session, [item.id])).containsKey(item.id)) {
        return;
      }
      final detailed = item.container == null
          ? await client.item(item.id)
          : item;
      final directory = await _downloadDirectory(session);
      await directory.create(recursive: true);
      final id = _fileId(item.id);
      final partial = File('${directory.path}/$id.part');
      File? completed;
      try {
        final detected = await client.downloadItem(
          item.id,
          partial,
          sourceContainer: detailed.container,
          audioBitDepth: detailed.audioBitDepth,
          onProgress: onProgress,
          maxBytes: maxBytes,
        );
        final extension = safeAudioExtension(detected);
        completed = File('${directory.path}/$id.$extension');
        await partial.rename(completed.path);
        final records = await _downloadRecords(session);
        records
          ..removeWhere((record) => (record['item'] as Map?)?['Id'] == item.id)
          ..add({
            'item': detailed.toJson(),
            'file': completed.uri.pathSegments.last,
          });
        await _saveDownloadRecords(session, records);
      } on Object {
        if (await partial.exists()) await partial.delete();
        if (completed != null && await completed.exists()) {
          await completed.delete();
        }
        rethrow;
      }
      // Artwork is optional; an unavailable image must not discard valid audio.
      final artworkId = detailed.artworkId;
      if (artworkId != null) {
        try {
          final file = File('${directory.path}/${_fileId(artworkId)}.art');
          if (!await file.exists()) {
            final temporary = File('${file.path}.part');
            try {
              await client.downloadArtwork(artworkId, temporary);
              await temporary.rename(file.path);
            } finally {
              if (await temporary.exists()) await temporary.delete();
            }
          }
        } on Object {
          /* Audio remains available when artwork cannot be cached. */
        }
      }
    });
    _downloadWrite = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<void> removeDownload(JellyfinSession session, String itemId) {
    final operation = _downloadWrite.then((_) async {
      final directory = await _downloadDirectory(session);
      final records = await _downloadRecords(session);
      final names = records
          .where((record) => (record['item'] as Map?)?['Id'] == itemId)
          .map((record) => record['file'])
          .whereType<String>()
          .toList();
      records.removeWhere(
        (record) => (record['item'] as Map?)?['Id'] == itemId,
      );
      await _saveDownloadRecords(session, records);
      for (final name in names.where(_safeDownloadName)) {
        final file = File('${directory.path}/$name');
        if (await file.exists()) await file.delete();
      }
    });
    _downloadWrite = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<void> clearAccountData(JellyfinSession session) async {
    await _downloadWrite;
    await _dataWrite;
    final directory = await _downloadDirectory(session);
    if (await directory.exists()) await directory.delete(recursive: true);
    final cache = await _libraryCacheFile(session);
    if (await cache.exists()) await cache.delete();
    final value = await _storage.read(
      key: _preferencesKey,
      iOptions: _iosOptions,
    );
    if (value != null) {
      final all = (jsonDecode(value) as Map).cast<String, dynamic>()
        ..remove(_preferenceId(session));
      await _storage.write(
        key: _preferencesKey,
        value: jsonEncode(all),
        iOptions: _iosOptions,
      );
    }
  }

  Future<void> clearDownloads(JellyfinSession session) async {
    await _downloadWrite;
    await _dataWrite;
    final directory = await _downloadDirectory(session);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  String _fileId(String value) =>
      base64UrlEncode(utf8.encode(value)).replaceAll('=', '');

  Future<Map<String, Uri>> downloadedArtwork(JellyfinSession session) async {
    final directory = await _downloadDirectory(session);
    if (!await directory.exists()) return {};
    final result = <String, Uri>{};
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.art')) continue;
      try {
        final name = file.uri.pathSegments.last;
        final id = utf8.decode(
          base64Url.decode(
            base64Url.normalize(name.substring(0, name.length - 4)),
          ),
        );
        result[id] = file.uri;
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> loadDownloadJobs(
    JellyfinSession session,
  ) async =>
      await _readJson(
        File('${(await _downloadDirectory(session)).path}/jobs.json'),
      ) ??
      {};

  Future<void> saveDownloadJobs(
    JellyfinSession session,
    Map<String, dynamic> jobs,
  ) async => _writeJson(
    File('${(await _downloadDirectory(session)).path}/jobs.json'),
    jobs,
  );

  Future<Map<String, dynamic>?> _readJson(File file) async {
    try {
      if (!await file.exists()) return null;
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeJson(File file, Map<String, dynamic> value) {
    final encoded = jsonEncode(value);
    final operation = _dataWrite.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    });
    _dataWrite = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<List<JellyfinItem>> offlineCatalog(JellyfinSession session) async {
    final tracks = (await loadDownloads(session)).items;
    final catalog = {for (final track in tracks) track.id: track};
    for (final track in tracks) {
      if (track.albumId case final id?) {
        catalog.putIfAbsent(
          id,
          () => JellyfinItem(
            id: id,
            name: track.album ?? 'Album',
            type: 'MusicAlbum',
            imageTag: track.albumImageTag,
            artists: track.artists,
          ),
        );
      }
      for (var i = 0; i < track.artistIds.length; i++) {
        final id = track.artistIds[i];
        catalog.putIfAbsent(
          id,
          () => JellyfinItem(
            id: id,
            name: i < track.artists.length ? track.artists[i] : 'Artist',
            type: 'MusicArtist',
          ),
        );
      }
    }
    final directory = await _downloadDirectory(session);
    if (await directory.exists()) {
      await for (final file in directory.list()) {
        if (file is! File || !file.path.endsWith('.collection.json')) continue;
        final saved = await _readJson(file);
        final children = (saved?['children'] as List? ?? const [])
            .whereType<Map>();
        if (!children.any((child) => catalog[child['Id']]?.isAudio == true)) {
          continue;
        }
        if (saved?['item'] case final Map item) {
          final parsed = JellyfinItem.fromJson(item.cast<String, dynamic>());
          catalog[parsed.id] = parsed;
        }
      }
    }
    return catalog.values.toList();
  }

  Future<List<JellyfinItem>> collectionItems(
    JellyfinClient api,
    JellyfinItem item, {
    bool offlineOnly = false,
  }) async {
    final file = File(
      '${(await _downloadDirectory(api.session)).path}/${_fileId(item.id)}.collection.json',
    );
    if (!offlineOnly) {
      try {
        final children = item.isArtist
            ? [
                ...await api.songsForArtist(item.id),
                ...await api.albumsForArtist(item.id),
              ]
            : item.isGenre
            ? await api.songsForGenre(item.id)
            : item.isPlaylist
            ? await api.playlistItems(item.id)
            : await api.children(item.id);
        try {
          await _writeJson(file, {
            'item': item.toJson(),
            'children': children.map((child) => child.toJson()).toList(),
          });
        } on FileSystemException {
          /* Keep live browsing available on a full disk. */
        }
        return children;
      } on JellyfinException catch (error) {
        if (error.isAuthenticationError) rethrow;
        final local = await collectionItems(api, item, offlineOnly: true);
        if (local.isEmpty) rethrow;
        return local;
      }
    }
    final tracks = (await loadDownloads(api.session)).items;
    final ids = tracks.map((track) => track.id).toSet();
    final saved = await _readJson(file);
    if (saved != null) {
      return (saved['children'] as List? ?? const [])
          .whereType<Map>()
          .map((child) => JellyfinItem.fromJson(child.cast<String, dynamic>()))
          .where((child) => child.isAudio && ids.contains(child.id))
          .toList();
    }
    final matches = tracks
        .where(
          (track) => item.isAlbum
              ? track.albumId == item.id
              : item.isArtist
              ? track.artistIds.contains(item.id)
              : item.isGenre
              ? track.genreNames.contains(item.name)
              : false,
        )
        .toList();
    sortJellyfinItems(
      matches,
      'AlbumArtist,Album,ParentIndexNumber,IndexNumber,SortName',
    );
    return matches;
  }

  Future<List<Map<String, dynamic>>> _downloadRecords(
    JellyfinSession session,
  ) async {
    final file = await _downloadManifest(session);
    if (!await file.exists()) return [];
    try {
      final json = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
      return (json['downloads'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => value.cast<String, dynamic>())
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _saveDownloadRecords(
    JellyfinSession session,
    List<Map<String, dynamic>> records,
  ) async {
    await _writeJson(await _downloadManifest(session), {'downloads': records});
  }

  bool _safeDownloadName(String value) =>
      value.isNotEmpty &&
      !value.startsWith('.') &&
      !value.contains('/') &&
      !value.contains('\\');

  Future<File> _playbackFile() async {
    final directory = await _applicationSupportDirectory();
    return File('${directory.path}/playback.json');
  }

  Future<Directory> _applicationSupportDirectory() async =>
      supportDirectory ?? await getApplicationSupportDirectory();

  String _preferenceId(JellyfinSession session) =>
      '${session.serverUrl}|${session.userId}';

  String _accountId(JellyfinSession session) =>
      base64UrlEncode(utf8.encode(_preferenceId(session))).replaceAll('=', '');

  Future<Directory> _downloadDirectory(JellyfinSession session) async {
    final directory = await _applicationSupportDirectory();
    return Directory('${directory.path}/downloads-${_accountId(session)}');
  }

  Future<File> _downloadManifest(JellyfinSession session) async =>
      File('${(await _downloadDirectory(session)).path}/downloads.json');

  Future<File> _libraryCacheFile(JellyfinSession session) async {
    final directory = await _applicationSupportDirectory();
    return File('${directory.path}/library-${_accountId(session)}.json');
  }
}

class JellyfinClient {
  JellyfinClient(this.session, {this.preferences = const AppPreferences()}) {
    _http.idleTimeout = const Duration(seconds: 15);
    _http.userAgent = '$appName/$appVersion';
  }

  final JellyfinSession session;
  final HttpClient _http = HttpClient();
  AppPreferences preferences;

  void updatePreferences(AppPreferences value) => preferences = value;

  static String normalizeServerUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Enter a server address.');
    }
    if (!normalized.contains('://')) {
      final host = Uri.tryParse('//$normalized')?.host ?? '';
      normalized =
          '${_isLocalNetworkHost(host) ? 'http' : 'https'}://$normalized';
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('Use an http:// or https:// server address.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Enter credentials separately, not in the server address.',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const FormatException(
        'The server address cannot include a query or fragment.',
      );
    }
    if (uri.scheme == 'http' && !_isLocalNetworkHost(uri.host)) {
      throw const FormatException(
        'HTTP is allowed only for private or local-network Jellyfin servers.',
      );
    }
    normalized = uri.toString();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool _isLocalNetworkHost(String value) {
    final host = value.toLowerCase();
    if (host == 'localhost' ||
        (!host.contains('.') && !host.contains(':')) ||
        host.endsWith('.local') ||
        host.endsWith('.lan') ||
        host.endsWith('.home') ||
        host.endsWith('.home.arpa') ||
        host.endsWith('.ts.net') ||
        host.endsWith('.internal')) {
      return true;
    }

    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    final bytes = address.rawAddress;
    if (bytes.length == 4) return _isPrivateIpv4(bytes);
    if (bytes.length != 16) return false;
    if (bytes.take(15).every((byte) => byte == 0) && bytes.last == 1) {
      return true;
    }
    if ((bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80)) {
      return true;
    }
    final mappedIpv4 =
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    return mappedIpv4 && _isPrivateIpv4(bytes.sublist(12));
  }

  static bool _isPrivateIpv4(List<int> bytes) =>
      bytes[0] == 10 ||
      bytes[0] == 127 ||
      (bytes[0] == 169 && bytes[1] == 254) ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127);

  static Future<JellyfinSession> authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final normalized = normalizeServerUrl(serverUrl);
    final deviceId = _newDeviceId();
    final pending = JellyfinSession(
      serverUrl: normalized,
      accessToken: '',
      userId: '',
      username: username.trim(),
      deviceId: deviceId,
    );
    final client = JellyfinClient(pending);
    try {
      final result = await client._requestJson(
        'POST',
        '/Users/AuthenticateByName',
        body: {'Username': username.trim(), 'Pw': password},
        authenticated: false,
      );
      final user = (result['User'] as Map?)?.cast<String, dynamic>();
      final token = result['AccessToken'] as String?;
      final userId = user?['Id'] as String?;
      if (token == null || userId == null) {
        throw const JellyfinException(
          'The server returned an incomplete login response.',
        );
      }
      return JellyfinSession(
        serverUrl: normalized,
        accessToken: token,
        userId: userId,
        username: user?['Name'] as String? ?? username.trim(),
        deviceId: deviceId,
      );
    } finally {
      client.close();
    }
  }

  Uri uri(String path, [Map<String, String?> query = const {}]) {
    final base = Uri.parse(session.serverUrl);
    final root = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final child = path.startsWith('/') ? path : '/$path';
    return base.replace(
      path: '$root$child',
      queryParameters: {
        for (final entry in query.entries)
          if (entry.value != null) entry.key: entry.value!,
      },
    );
  }

  Uri imageUri(String itemId, {int width = 600}) => uri(
    '/Items/$itemId/Images/Primary',
    {'maxWidth': '$width', 'quality': '88'},
  );

  Uri streamUri(
    String itemId, {
    String? sourceContainer,
    String? mediaSourceId,
    int? audioBitDepth,
  }) {
    final directContainers = Platform.isIOS
        ? const {'mp3', 'aac', 'm4a', 'flac', 'wav'}
        : const {
            'opus',
            'mp3',
            'aac',
            'm4a',
            'flac',
            'webma',
            'webm',
            'wav',
            'ogg',
          };
    final container = sourceContainer?.toLowerCase();
    final direct =
        preferences.streamingQuality == StreamingQuality.original &&
        directContainers.contains(container) &&
        !(Platform.isIOS && container == 'flac' && (audioBitDepth ?? 0) > 24);
    // Explicit extensions let native players select the correct demuxer, and
    // HLS retains seeking for transcoded audio. Unknown formats use AAC fallback.
    return uri(
      '/Audio/$itemId/${direct ? 'stream.$container' : 'master.m3u8'}',
      {
        'UserId': session.userId,
        'DeviceId': session.deviceId,
        'MediaSourceId': mediaSourceId ?? itemId,
        'MaxStreamingBitrate': '${preferences.streamingQuality.maxBitrate}',
        if (direct) 'Static': 'true',
        if (!direct)
          'AudioBitRate':
              '${min(preferences.streamingQuality.maxBitrate, 320000)}',
        if (!direct) 'AudioCodec': 'aac',
        if (!direct) 'SegmentContainer': 'ts',
        if (!direct) 'EnableAutoStreamCopy': 'false',
        'PlaySessionId': _playSessionId(itemId),
        'EnableRemoteMedia': 'false',
      },
    );
  }

  Map<String, String> get authorizationHeaders => {
    HttpHeaders.authorizationHeader: _authorizationValue(authenticated: true),
  };

  Future<String?> downloadItem(
    String itemId,
    File destination, {
    String? sourceContainer,
    int? audioBitDepth,
    void Function(int received, int? total)? onProgress,
    int? maxBytes,
  }) async {
    final portable = canPlayOriginalOffline(
      sourceContainer,
      audioBitDepth: audioBitDepth,
    );
    try {
      final request = await _http
          .getUrl(
            portable
                ? uri('/Items/$itemId/Download')
                : uri('/Audio/$itemId/stream.m4a', {
                    'Static': 'false',
                    'AudioCodec': 'aac',
                    'Container': 'm4a',
                    'AudioBitRate':
                        '${min(preferences.streamingQuality.maxBitrate, 320000)}',
                    'DeviceId': session.deviceId,
                    'PlaySessionId': _playSessionId(itemId),
                  }),
          )
          .timeout(const Duration(seconds: 12));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        _authorizationValue(authenticated: true),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw JellyfinException(
          'Jellyfin could not download this song (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      final expected = response.contentLength;
      if (maxBytes != null && expected > maxBytes) {
        throw const JellyfinException('Download storage limit reached.');
      }
      var received = 0;
      final output = destination.openWrite();
      try {
        await output.addStream(
          response.timeout(const Duration(seconds: 30)).map((chunk) {
            received += chunk.length;
            if (maxBytes != null && received > maxBytes) {
              throw const JellyfinException('Download storage limit reached.');
            }
            onProgress?.call(received, expected < 0 ? null : expected);
            return chunk;
          }),
        );
        await output.flush();
      } finally {
        await output.close();
      }
      if (received == 0 || (expected >= 0 && received != expected)) {
        throw const JellyfinException(
          'The download was incomplete. Retry this song.',
        );
      }
      return portable ? safeAudioExtension(sourceContainer) : 'm4a';
    } on TimeoutException {
      throw const JellyfinException('The download took too long to start.');
    } on SocketException {
      throw const JellyfinException(
        'The download stopped because the server connection was lost.',
      );
    } on HttpException {
      throw const JellyfinException(
        'The connection to Jellyfin was interrupted. Retry when connected.',
      );
    } on HandshakeException {
      throw const JellyfinException(
        'The server certificate could not be verified.',
      );
    }
  }

  Future<void> downloadArtwork(String itemId, File destination) async {
    final request = await _http
        .getUrl(imageUri(itemId))
        .timeout(const Duration(seconds: 12));
    authorizationHeaders.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        response.headers.contentType?.primaryType != 'image') {
      await response.drain<void>();
      throw const JellyfinException('Artwork unavailable.');
    }
    var bytes = 0;
    await response
        .timeout(const Duration(seconds: 15))
        .map((chunk) {
          bytes += chunk.length;
          if (bytes > 10 * 1024 * 1024) {
            throw const JellyfinException('Artwork too large.');
          }
          return chunk;
        })
        .pipe(destination.openWrite());
  }

  Future<List<JellyfinLibrary>> musicLibraries() async {
    final json = await _requestJson(
      'GET',
      '/UserViews',
      query: {
        'userId': session.userId,
        'includeExternalContent': 'false',
        'includeHidden': 'false',
      },
    );
    return (json['Items'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => value.cast<String, dynamic>())
        .where(
          (value) =>
              (value['CollectionType'] as String?)?.toLowerCase() == 'music',
        )
        .map(
          (value) => JellyfinLibrary(
            id: value['Id'] as String? ?? '',
            name: value['Name'] as String? ?? 'Music',
          ),
        )
        .where((value) => value.id.isNotEmpty)
        .toList();
  }

  Future<List<JellyfinItem>> recentlyAdded({int limit = 18}) => _limitedItems({
    'IncludeItemTypes': 'Audio,MusicAlbum',
    'Recursive': 'true',
    'SortBy': 'DateCreated',
    'SortOrder': 'Descending',
  }, limit);

  Future<List<JellyfinItem>> recentlyPlayed({int limit = 18}) async =>
      (await _limitedItems({
        'IncludeItemTypes': 'Audio',
        'Recursive': 'true',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
      }, limit)).where((item) => item.lastPlayedDate != null).toList();

  Future<List<JellyfinItem>> albums({int? limit}) => _collectionItems({
    'IncludeItemTypes': 'MusicAlbum',
    'Recursive': 'true',
    'SortBy': 'SortName',
    'SortOrder': 'Ascending',
  }, limit: limit);

  Future<List<JellyfinItem>> artists({int? limit}) => _collectionItems(
    {'Recursive': 'true', 'SortBy': 'SortName', 'SortOrder': 'Ascending'},
    limit: limit,
    path: '/Artists',
  );

  Future<List<JellyfinItem>> songs({int? limit}) => _collectionItems({
    'IncludeItemTypes': 'Audio',
    'Recursive': 'true',
    'SortBy': 'SortName',
    'SortOrder': 'Ascending',
  }, limit: limit);

  Future<List<JellyfinItem>> randomSongs({int limit = 100}) => _limitedItems({
    'IncludeItemTypes': 'Audio',
    'Recursive': 'true',
    'SortBy': 'Random',
  }, limit);

  Stream<List<JellyfinItem>> songBatches({int batchSize = 250}) =>
      _itemBatches({
        'IncludeItemTypes': 'Audio',
        'Recursive': 'true',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
      }, batchSize: batchSize);

  Future<List<JellyfinItem>> playlists({int? limit}) => _collectionItems({
    'IncludeItemTypes': 'Playlist',
    'Recursive': 'true',
    'SortBy': 'SortName',
    'SortOrder': 'Ascending',
  }, limit: limit);

  Future<List<JellyfinItem>> playlistItems(String playlistId) => _allItems(
    const {},
    path: '/Playlists/$playlistId/Items',
    scopeToLibraries: false,
  );

  Future<List<JellyfinItem>> instantMix(
    String itemId, {
    int limit = 100,
  }) async => (await _itemPage(
    query: {'Limit': '$limit', 'EnableTotalRecordCount': 'false'},
    path: '/Items/$itemId/InstantMix',
  )).items;

  Future<JellyfinItem> createPlaylist(
    String name, [
    Iterable<String> itemIds = const [],
  ]) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const JellyfinException('Enter a playlist name.');
    }
    final json = await _requestJson(
      'POST',
      '/Playlists',
      body: {
        'Name': trimmed,
        'Ids': itemIds.toList(),
        'UserId': session.userId,
        'MediaType': 'Audio',
        'IsPublic': false,
      },
    );
    final id = json['Id'] as String?;
    if (id == null || id.isEmpty) {
      throw const JellyfinException(
        'Jellyfin created the playlist without returning its ID.',
      );
    }
    return item(id);
  }

  Future<void> addToPlaylist(
    String playlistId,
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return;
    await _requestJson(
      'POST',
      '/Playlists/$playlistId/Items',
      query: {'ids': ids.join(','), 'userId': session.userId},
    );
  }

  Future<void> removeFromPlaylist(
    String playlistId,
    Iterable<String> entryIds,
  ) async {
    final ids = entryIds.toList();
    if (ids.isEmpty) return;
    await _requestJson(
      'DELETE',
      '/Playlists/$playlistId/Items',
      query: {'entryIds': ids.join(',')},
    );
  }

  Future<void> movePlaylistItem(
    String playlistId,
    String entryId,
    int newIndex,
  ) async {
    await _requestJson(
      'POST',
      '/Playlists/$playlistId/Items/$entryId/Move/$newIndex',
    );
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const JellyfinException('Enter a playlist name.');
    }
    await _requestJson(
      'POST',
      '/Playlists/$playlistId',
      body: {'Name': trimmed},
    );
  }

  Future<List<JellyfinDevice>> devices() async {
    final json = await _requestList(
      'GET',
      '/Sessions',
      query: {'controllableByUserId': session.userId},
    );
    return json
        .whereType<Map>()
        .map((value) => value.cast<String, dynamic>())
        .where(
          (value) =>
              value['Id'] is String &&
              value['DeviceId'] != session.deviceId &&
              value['SupportsRemoteControl'] != false,
        )
        .map(
          (value) => JellyfinDevice(
            id: value['Id'] as String,
            name: value['DeviceName'] as String? ?? 'Jellyfin device',
            client: value['Client'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<void> playOnDevice(
    JellyfinDevice device,
    List<JellyfinItem> items, {
    int startIndex = 0,
    Duration position = Duration.zero,
  }) async {
    if (items.isEmpty) return;
    await _requestJson(
      'POST',
      '/Sessions/${device.id}/Playing',
      query: {
        'playCommand': 'PlayNow',
        'itemIds': items.map((item) => item.id).join(','),
        'startIndex': '${startIndex.clamp(0, items.length - 1)}',
        'startPositionTicks': '${position.inMicroseconds * 10}',
      },
    );
  }

  Future<List<JellyfinItem>> favorites({int? limit}) => _collectionItems({
    'IncludeItemTypes': 'Audio,MusicAlbum,MusicArtist,Playlist',
    'Filters': 'IsFavorite',
    'Recursive': 'true',
    'SortBy': 'SortName',
    'SortOrder': 'Ascending',
  }, limit: limit);

  Future<List<JellyfinItem>> genres({int? limit, String? searchTerm}) =>
      _collectionItems(
        {
          'Recursive': 'true',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
          'SearchTerm': ?searchTerm,
        },
        limit: limit,
        path: '/MusicGenres',
      );

  Future<List<JellyfinItem>> search(String term, {int limit = 60}) {
    final query = term.trim();
    if (query.isEmpty) return Future.value(const []);
    return Future.wait([
      _limitedItems({
        'SearchTerm': query,
        'IncludeItemTypes': 'Audio,MusicAlbum,MusicArtist,Playlist',
        'Recursive': 'true',
        'SortBy': 'SortName',
      }, limit),
      genres(limit: limit, searchTerm: query),
    ]).then((parts) => _merge(parts.expand((part) => part), limit: limit));
  }

  Future<JellyfinItem> item(String id) async {
    final json = await _requestJson(
      'GET',
      '/Items/$id',
      query: {'userId': session.userId},
    );
    return JellyfinItem.fromJson(json);
  }

  Future<List<JellyfinItem>> children(String parentId) => _allItems({
    'ParentId': parentId,
    'IncludeItemTypes': 'Audio,MusicAlbum',
    'Recursive': 'true',
    'SortBy': 'ParentIndexNumber,IndexNumber,SortName',
    'SortOrder': 'Ascending',
  }, scopeToLibraries: false);

  Future<List<JellyfinItem>> albumsForArtist(String artistId) => _allItems({
    'ArtistIds': artistId,
    'IncludeItemTypes': 'MusicAlbum',
    'Recursive': 'true',
    'SortBy': 'ProductionYear,SortName',
    'SortOrder': 'Descending',
  });

  Future<List<JellyfinItem>> songsForArtist(String artistId) => _allItems({
    'ArtistIds': artistId,
    'IncludeItemTypes': 'Audio',
    'Recursive': 'true',
    'SortBy': 'AlbumArtist,Album,ParentIndexNumber,IndexNumber,SortName',
    'SortOrder': 'Ascending',
  });

  Future<List<JellyfinItem>> songsForGenre(String genreId) => _allItems({
    'GenreIds': genreId,
    'IncludeItemTypes': 'Audio',
    'Recursive': 'true',
    'SortBy': 'AlbumArtist,Album,ParentIndexNumber,IndexNumber,SortName',
    'SortOrder': 'Ascending',
  });

  Future<void> setFavorite(String itemId, bool favorite) async {
    await _requestJson(
      favorite ? 'POST' : 'DELETE',
      '/Users/${session.userId}/FavoriteItems/$itemId',
    );
  }

  Future<void> reportPlayback(
    String event,
    String itemId,
    Duration position, {
    bool paused = false,
  }) async {
    await _requestJson(
      'POST',
      '/Sessions/Playing${event == 'start'
          ? ''
          : event == 'stop'
          ? '/Stopped'
          : '/Progress'}',
      body: {
        'ItemId': itemId,
        'PositionTicks': position.inMicroseconds * 10,
        'IsPaused': paused,
        'PlaySessionId': _playSessionId(itemId),
      },
    );
  }

  Future<List<JellyfinItem>> _collectionItems(
    Map<String, String> query, {
    int? limit,
    String path = '/Items',
  }) => limit == null
      ? _allItems(query, path: path)
      : _limitedItems(query, limit, path: path);

  Future<List<JellyfinItem>> _limitedItems(
    Map<String, String> query,
    int limit, {
    String path = '/Items',
  }) async {
    final parents = preferences.musicLibraryIds.isEmpty
        ? const <String?>[null]
        : preferences.musicLibraryIds.map<String?>((id) => id);
    final pages = await Future.wait([
      for (final parent in parents)
        _itemPage(
          query: {
            ...query,
            'ParentId': ?parent,
            'Limit': '$limit',
            'EnableTotalRecordCount': 'false',
          },
          path: path,
        ),
    ]);
    return _merge(
      pages.expand((page) => page.items),
      query: query,
      limit: limit,
      sortMerged: pages.length > 1,
    );
  }

  Future<List<JellyfinItem>> _allItems(
    Map<String, String> query, {
    String path = '/Items',
    bool scopeToLibraries = true,
  }) async {
    final results = <JellyfinItem>[];
    await for (final batch in _itemBatches(
      query,
      path: path,
      scopeToLibraries: scopeToLibraries,
    )) {
      results.addAll(batch);
    }
    return _merge(
      results,
      query: query,
      sortMerged: scopeToLibraries && preferences.musicLibraryIds.length > 1,
    );
  }

  Stream<List<JellyfinItem>> _itemBatches(
    Map<String, String> query, {
    String path = '/Items',
    bool scopeToLibraries = true,
    int batchSize = 250,
  }) async* {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    final parents = !scopeToLibraries || preferences.musicLibraryIds.isEmpty
        ? const <String?>[null]
        : preferences.musicLibraryIds.map<String?>((id) => id);
    for (final parent in parents) {
      var start = 0;
      while (true) {
        final page = await _itemPage(
          query: {
            ...query,
            'ParentId': ?parent,
            'StartIndex': '$start',
            'Limit': '$batchSize',
            'EnableTotalRecordCount': 'true',
          },
          path: path,
        );
        if (page.items.isNotEmpty) yield page.items;
        start += page.items.length;
        if (page.items.isEmpty ||
            page.items.length < batchSize ||
            (page.total != null && start >= page.total!)) {
          break;
        }
      }
    }
  }

  Future<({List<JellyfinItem> items, int? total})> _itemPage({
    required Map<String, String> query,
    String path = '/Items',
  }) async {
    final json = await _requestJson(
      'GET',
      path,
      query: {
        'userId': session.userId,
        'Fields': _itemFields,
        'EnableUserData': 'true',
        ...query,
      },
    );
    return (
      items: _parseItems(json),
      total: (json['TotalRecordCount'] as num?)?.toInt(),
    );
  }

  List<JellyfinItem> _merge(
    Iterable<JellyfinItem> values, {
    Map<String, String> query = const {},
    int? limit,
    bool sortMerged = false,
  }) {
    final sorted = query.containsKey('SortBy');
    final result = sorted
        ? {for (final item in values) item.id: item}.values.toList()
        : values.toList(); // Playlist entries may intentionally repeat a song.
    if (sortMerged && sorted && query['SortBy'] != 'Random') {
      sortJellyfinItems(
        result,
        query['SortBy']!,
        descending: query['SortOrder'] == 'Descending',
      );
    }
    return limit == null ? result : result.take(limit).toList();
  }

  List<JellyfinItem> _parseItems(Map<String, dynamic> json) =>
      (json['Items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => JellyfinItem.fromJson(item.cast<String, dynamic>()))
          .where((item) => item.id.isNotEmpty)
          .toList();

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final decoded = await _requestDecoded(
      method,
      path,
      query: query,
      body: body,
      authenticated: authenticated,
    );
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const JellyfinException('Jellyfin returned an unexpected response.');
  }

  Future<List<dynamic>> _requestList(
    String method,
    String path, {
    Map<String, String> query = const {},
  }) async {
    final decoded = await _requestDecoded(method, path, query: query);
    if (decoded is List) return decoded;
    throw const JellyfinException('Jellyfin returned an unexpected response.');
  }

  Future<Object?> _requestDecoded(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final target = uri(path, query);
    try {
      final request = await _http
          .openUrl(method, target)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        _authorizationValue(authenticated: authenticated),
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = switch (response.statusCode) {
          401 || 403 =>
            authenticated
                ? 'Your Jellyfin session expired. Sign in again.'
                : 'Incorrect username or password.',
          404 => 'The requested music is no longer available.',
          _ =>
            'Jellyfin returned ${response.statusCode}${text.isEmpty ? '.' : ': $text'}',
        };
        throw JellyfinException(message, statusCode: response.statusCode);
      }
      if (text.isEmpty) return const <String, dynamic>{};
      return jsonDecode(text);
    } on TimeoutException {
      throw const JellyfinException(
        'The Jellyfin server took too long to respond.',
      );
    } on SocketException {
      throw const JellyfinException(
        'Cannot reach the Jellyfin server. Check its address and your network.',
      );
    } on HttpException {
      throw const JellyfinException(
        'The connection to Jellyfin was interrupted. Retry when connected.',
      );
    } on HandshakeException {
      throw const JellyfinException(
        'The server certificate could not be verified.',
      );
    } on FormatException {
      throw const JellyfinException('Jellyfin returned invalid data.');
    }
  }

  void close() => _http.close(force: true);

  String _playSessionId(String itemId) => '${session.deviceId}-$itemId';

  String _authorizationValue({required bool authenticated}) =>
      'MediaBrowser Client="$appName", Device="Flutter", '
      'DeviceId="${session.deviceId}", Version="$appVersion"'
      '${authenticated && session.accessToken.isNotEmpty ? ', Token="${session.accessToken}"' : ''}';

  static String _newDeviceId() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static const _itemFields =
      'Overview,Genres,SortName,AlbumArtist,DateCreated,MediaSources,ParentId,PrimaryImageAspectRatio';
}

class AppController extends ChangeNotifier {
  AppController(this.store);

  final JellyfinSessionStore store;
  AppStatus status = AppStatus.booting;
  JellyfinSession? session;
  JellyfinClient? client;
  JellyfinSession? editingServer;
  bool managingServers = false;
  AppStatus? _statusBeforeServerManagement;
  String? _errorBeforeServerManagement;
  String? errorMessage;
  List<JellyfinSession> servers = const [];
  List<JellyfinItem> recentlyAdded = const [];
  List<JellyfinItem> recentlyPlayed = const [];
  List<JellyfinItem> randomAlbums = const [];
  List<JellyfinItem> albums = const [];
  List<JellyfinItem> artists = const [];
  List<JellyfinItem> songs = const [];
  List<JellyfinItem> playlists = const [];
  List<JellyfinItem> favorites = const [];
  List<JellyfinItem> genres = const [];
  List<JellyfinItem> downloads = const [];
  List<JellyfinItem> downloadedCatalog = const [];
  Map<String, Uri> artworkUris = const {};
  List<JellyfinItem> failedDownloads = const [];
  bool downloadsPaused = false;
  int downloadReceivedBytes = 0;
  int? downloadTotalBytes;
  JellyfinClient? _downloadClient;
  final Set<String> _cancelledDownloads = {};
  bool _disposed = false;
  int downloadedBytes = 0;
  List<JellyfinItem> downloadQueue = const [];
  JellyfinItem? downloadingItem;
  String? downloadError;
  Future<void>? _downloadWorker;
  int _downloadGeneration = 0;
  JellyfinClient? _refreshingClient;
  List<JellyfinLibrary> musicLibraries = const [];
  AppPreferences preferences = const AppPreferences();

  String? get downloadingId => downloadingItem?.id;

  bool isQueuedForDownload(String itemId) =>
      downloadingId == itemId || downloadQueue.any((item) => item.id == itemId);

  bool get canCancelServerManagement => managingServers && session != null;

  Future<void> initialize() async {
    try {
      servers = await store.loadAll();
      final restored = await store.load();
      if (restored == null) {
        status = AppStatus.signedOut;
      } else {
        await connect(restored);
      }
    } catch (error) {
      status = AppStatus.signedOut;
      errorMessage = 'Saved login could not be restored: $error';
    }
    notifyListeners();
  }

  Future<void> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    status = AppStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final authenticated = await JellyfinClient.authenticate(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );
      await store.save(
        authenticated,
        replacingDeviceId: editingServer?.deviceId,
      );
      editingServer = null;
      servers = await store.loadAll();
      await connect(authenticated);
    } on JellyfinException catch (error) {
      status = AppStatus.signedOut;
      errorMessage = error.message;
    } on FormatException catch (error) {
      status = AppStatus.signedOut;
      errorMessage = error.message;
    } on Object {
      status = AppStatus.signedOut;
      errorMessage = 'Login failed because the server response was invalid.';
    }
    notifyListeners();
  }

  Future<void> connect(JellyfinSession value) async {
    JellyfinClient.normalizeServerUrl(value.serverUrl);
    managingServers = false;
    editingServer = null;
    _statusBeforeServerManagement = null;
    _errorBeforeServerManagement = null;
    _disconnect();
    session = value;
    status = AppStatus.loading;
    errorMessage = null;
    notifyListeners();
    final loadedPreferences = await store.loadPreferences(value);
    if (session?.deviceId != value.deviceId) return;
    final next = JellyfinClient(value, preferences: loadedPreferences);
    final offline = await store.loadDownloads(value);
    if (session?.deviceId != value.deviceId) {
      next.close();
      return;
    }
    preferences = loadedPreferences;
    client = next;
    downloads = offline.items;
    downloadedBytes = offline.bytes;
    downloadedCatalog = await store.offlineCatalog(value);
    artworkUris = await store.downloadedArtwork(value);
    final jobs = await store.loadDownloadJobs(value);
    List<JellyfinItem> jobItems(String key) => (jobs[key] as List? ?? const [])
        .whereType<Map>()
        .map((item) => JellyfinItem.fromJson(item.cast<String, dynamic>()))
        .toList();
    downloadQueue = pendingAudioDownloads(
      jobItems('pending'),
      downloads.map((item) => item.id),
    );
    failedDownloads = pendingAudioDownloads(
      jobItems('failed'),
      downloads.map((item) => item.id),
    );
    downloadsPaused = jobs['paused'] == true;
    if (failedDownloads.isNotEmpty) {
      downloadError = 'Some downloads need retrying.';
    }
    if (!identical(client, next)) return;
    try {
      await _restoreLibraryCache(value);
    } on Object {
      // Cache failure must not block a live server connection.
    }
    if (!identical(client, next)) return;
    notifyListeners();
    _startDownloads();
    await refresh();
  }

  Future<void> refresh() async {
    final api = client;
    if (api == null || identical(_refreshingClient, api)) return;
    _refreshingClient = api;
    status = AppStatus.loading;
    notifyListeners();
    try {
      final availableLibraries = await api.musicLibraries();
      if (!identical(client, api)) return;
      final availableIds = availableLibraries.map((value) => value.id).toSet();
      final selectedIds = preferences.musicLibraryIds.intersection(
        availableIds,
      );
      if (preferences.musicLibraryIds.isNotEmpty &&
          selectedIds.length != preferences.musicLibraryIds.length) {
        preferences = preferences.copyWith(musicLibraryIds: selectedIds);
        api.updatePreferences(preferences);
        if (session case final active?) {
          await store.savePreferences(active, preferences);
        }
        if (!identical(client, api)) return;
      }
      musicLibraries = availableLibraries;
      Future<void> publish(
        Future<List<JellyfinItem>> request,
        void Function(List<JellyfinItem>) assign,
      ) async {
        final result = await request;
        if (!identical(client, api)) return;
        assign(result);
        notifyListeners();
      }

      Future<void> loadSongs() async {
        final seen = <String, JellyfinItem>{};
        await for (final batch in api.songBatches()) {
          if (!identical(client, api)) return;
          for (final item in batch) {
            seen[item.id] = item;
          }
          songs = seen.values.toList();
          notifyListeners();
        }
        if (identical(client, api)) {
          songs = seen.values.toList();
          sortJellyfinItems(songs, 'SortName');
        }
      }

      await Future.wait([
        publish(api.recentlyAdded(), (items) => recentlyAdded = items),
        publish(api.recentlyPlayed(), (items) => recentlyPlayed = items),
        publish(api.albums(), (items) {
          albums = items;
          randomAlbums = [...items]..shuffle(Random());
        }),
        publish(api.artists(), (items) => artists = items),
        loadSongs(),
        publish(api.playlists(), (items) => playlists = items),
        publish(api.favorites(), (items) => favorites = items),
        publish(api.genres(), (items) => genres = items),
      ]);
      if (!identical(client, api)) return;
      status = AppStatus.ready;
      errorMessage = null;
      if (session case final active?) {
        try {
          await store.saveLibraryCache(active, _libraryCacheJson());
        } on Object {
          // A fresh library is still useful when local cache storage is full.
        }
      }
    } on JellyfinException catch (error) {
      if (!identical(client, api)) return;
      errorMessage = error.message;
      if (error.isAuthenticationError) {
        final expired = session;
        _disconnect();
        if (expired != null) {
          editingServer = expired;
          await store.deactivate(clearPlayback: false);
        }
        servers = await store.loadAll();
        status = AppStatus.signedOut;
        notifyListeners();
        return;
      } else {
        status = AppStatus.error;
      }
    } on Object {
      if (!identical(client, api)) return;
      errorMessage = 'Jellyfin returned music data the app could not read.';
      status = AppStatus.error;
    } finally {
      if (identical(_refreshingClient, api)) _refreshingClient = null;
    }
    if (!identical(client, api)) return;
    notifyListeners();
  }

  Future<List<JellyfinItem>> search(String term) async {
    final api = client;
    if (api == null) return const [];
    if (status == AppStatus.error) {
      return searchLocalMusic(downloadedCatalog, term);
    }
    try {
      return await api.search(term);
    } on JellyfinException catch (error) {
      if (error.isAuthenticationError) rethrow;
      final local = searchLocalMusic(downloadedCatalog, term);
      if (local.isEmpty) rethrow;
      return local;
    }
  }

  Future<List<JellyfinItem>> children(JellyfinItem item) async {
    final api = client;
    if (api == null) return const [];
    return store.collectionItems(
      api,
      item,
      offlineOnly: status == AppStatus.error,
    );
  }

  bool isDownloaded(String itemId) =>
      downloads.any((item) => item.id == itemId);

  Future<int> enqueueDownload(JellyfinItem item) async {
    final api = client;
    if (api == null) throw const JellyfinException('Sign in first.');
    final items = item.isAudio ? [item] : await children(item);
    return enqueueDownloads(items);
  }

  Future<int> enqueueDownloads(Iterable<JellyfinItem> values) async {
    if (session == null || client == null) return 0;
    final items = pendingAudioDownloads(values, [
      ...downloads.map((item) => item.id),
      ...downloadQueue.map((item) => item.id),
    ]);
    if (items.isEmpty) return 0;
    final ids = items.map((item) => item.id).toSet();
    failedDownloads = failedDownloads
        .where((item) => !ids.contains(item.id))
        .toList();
    downloadQueue = [...downloadQueue, ...items];
    downloadError = null;
    await _saveDownloadJobs();
    notifyListeners();
    _startDownloads();
    return items.length;
  }

  Future<void> _saveDownloadJobs() async {
    final active = session;
    if (active == null) return;
    await store.saveDownloadJobs(active, {
      'pending': downloadQueue.map((item) => item.toJson()).toList(),
      'failed': failedDownloads.map((item) => item.toJson()).toList(),
      'paused': downloadsPaused,
    });
  }

  void _startDownloads() {
    final active = session;
    if (active == null ||
        _downloadWorker != null ||
        downloadsPaused ||
        downloadQueue.isEmpty) {
      return;
    }
    _downloadWorker = _processDownloadQueue(active, _downloadGeneration);
  }

  Future<void> _reloadDownloads(JellyfinSession active) async {
    final offline = await store.loadDownloads(active);
    final catalog = await store.offlineCatalog(active);
    final artwork = await store.downloadedArtwork(active);
    if (session?.deviceId != active.deviceId || _disposed) return;
    downloads = offline.items;
    downloadedBytes = offline.bytes;
    downloadedCatalog = catalog;
    artworkUris = artwork;
  }

  Future<void> _processDownloadQueue(
    JellyfinSession active,
    int generation,
  ) async {
    try {
      while (generation == _downloadGeneration &&
          !downloadsPaused &&
          downloadQueue.isNotEmpty) {
        final item = downloadQueue.first;
        final api = JellyfinClient(active, preferences: preferences);
        _downloadClient = api;
        downloadingItem = item;
        downloadReceivedBytes = 0;
        downloadTotalBytes = null;
        notifyListeners();
        try {
          if (preferences.wifiOnlyDownloads) {
            final allowed = await const MethodChannel(
              'com.thomaskleckner.shrimphony/network',
            ).invokeMethod<bool>('isWifi');
            if (allowed != true) {
              downloadsPaused = true;
              downloadError =
                  'Downloads paused. Connect to Wi-Fi, then resume.';
              break;
            }
          }
          final limit = preferences.downloadLimitBytes;
          final remaining = limit == 0 ? null : max(0, limit - downloadedBytes);
          if (remaining == 0) {
            throw const JellyfinException('Download storage limit reached.');
          }
          await store.downloadTrack(
            active,
            api,
            item,
            maxBytes: remaining,
            onProgress: (received, total) {
              if (generation != _downloadGeneration || _disposed) return;
              // Publish byte progress at roughly 1% intervals, not every network packet.
              if (received - downloadReceivedBytes <
                      (total ?? 10240000) ~/ 100 &&
                  received != total) {
                return;
              }
              downloadReceivedBytes = received;
              downloadTotalBytes = total;
              notifyListeners();
            },
          );
          if (generation != _downloadGeneration) return;
          await _reloadDownloads(active);
          downloadQueue = downloadQueue
              .where((value) => value.id != item.id)
              .toList();
        } on Object catch (error) {
          if (generation != _downloadGeneration) return;
          if (!_cancelledDownloads.contains(item.id) && !downloadsPaused) {
            failedDownloads = [
              ...failedDownloads.where((value) => value.id != item.id),
              item,
            ];
            downloadQueue = downloadQueue
                .where((value) => value.id != item.id)
                .toList();
            downloadError = 'Could not download ${item.name}: $error';
          }
        } finally {
          api.close();
          if (identical(_downloadClient, api)) _downloadClient = null;
          _cancelledDownloads.remove(item.id);
        }
        if (generation != _downloadGeneration) return;
        await _saveDownloadJobs();
        notifyListeners();
      }
      if (generation == _downloadGeneration) await _saveDownloadJobs();
    } on Object catch (error) {
      if (generation == _downloadGeneration) {
        downloadsPaused = true;
        downloadError = 'Downloads paused: $error';
      }
    } finally {
      if (generation == _downloadGeneration) {
        downloadingItem = null;
        _downloadWorker = null;
        notifyListeners();
      }
    }
  }

  Future<void> pauseDownloads() async {
    downloadsPaused = true;
    _downloadClient?.close();
    await _saveDownloadJobs();
    await _downloadWorker;
    notifyListeners();
  }

  Future<void> resumeDownloads() async {
    await _downloadWorker;
    downloadsPaused = false;
    downloadError = null;
    await _saveDownloadJobs();
    _startDownloads();
    notifyListeners();
  }

  Future<void> retryDownloads() async {
    final failed = [...failedDownloads];
    await enqueueDownloads(failed);
    await resumeDownloads();
  }

  Future<void> cancelDownload(String id) async {
    if (downloadingId == id) {
      _cancelledDownloads.add(id);
      _downloadClient?.close();
    }
    downloadQueue = downloadQueue.where((item) => item.id != id).toList();
    failedDownloads = failedDownloads.where((item) => item.id != id).toList();
    await _saveDownloadJobs();
    notifyListeners();
  }

  void clearDownloadError() {
    downloadError = null;
    notifyListeners();
  }

  void _resetDownloadQueue() {
    _downloadGeneration++;
    _downloadClient?.close();
    _downloadClient = null;
    downloadQueue = failedDownloads = const [];
    downloadingItem = null;
    downloadError = null;
    downloadsPaused = false;
    _downloadWorker = null;
    _cancelledDownloads.clear();
  }

  Future<void> removeDownload(JellyfinItem item) async {
    final active = session;
    if (active == null) return;
    await store.removeDownload(active, item.id);
    await _reloadDownloads(active);
    notifyListeners();
  }

  Future<void> clearDownloads() async {
    final active = session;
    if (active == null) return;
    await pauseDownloads();
    downloadQueue = failedDownloads = const [];
    await store.clearDownloads(active);
    await _reloadDownloads(active);
    downloadError = null;
    notifyListeners();
  }

  Future<JellyfinItem> createPlaylist(
    String name, {
    JellyfinItem? firstItem,
  }) async {
    final api = client;
    if (api == null) throw const JellyfinException('Sign in first.');
    final playlist = await api.createPlaylist(name, [
      if (firstItem != null) firstItem.id,
    ]);
    playlists = [...playlists, playlist]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return playlist;
  }

  Future<void> addToPlaylist(JellyfinItem playlist, JellyfinItem item) async {
    final api = client;
    if (api == null) return;
    await api.addToPlaylist(playlist.id, [item.id]);
  }

  Future<void> removeFromPlaylist(
    JellyfinItem playlist,
    JellyfinItem item,
  ) async {
    final api = client;
    if (api == null) return;
    final entryId = item.playlistItemId;
    if (entryId == null || entryId.isEmpty) {
      throw const JellyfinException(
        'Jellyfin did not provide this playlist entry ID.',
      );
    }
    await api.removeFromPlaylist(playlist.id, [entryId]);
  }

  Future<void> movePlaylistItem(
    JellyfinItem playlist,
    JellyfinItem item,
    int newIndex,
  ) async {
    final api = client;
    final entryId = item.playlistItemId;
    if (api == null) return;
    if (entryId == null || entryId.isEmpty) {
      throw const JellyfinException(
        'Jellyfin did not provide this playlist entry ID.',
      );
    }
    await api.movePlaylistItem(playlist.id, entryId, newIndex);
  }

  Future<void> renamePlaylist(JellyfinItem playlist, String name) async {
    final api = client;
    if (api == null) return;
    await api.renamePlaylist(playlist.id, name);
    playlists = playlists
        .map(
          (item) =>
              item.id == playlist.id ? item.copyWith(name: name.trim()) : item,
        )
        .toList();
    notifyListeners();
  }

  Future<List<JellyfinDevice>> devices() async {
    final api = client;
    return api == null ? const [] : api.devices();
  }

  Future<void> updatePreferences(AppPreferences value) async {
    final active = session;
    final api = client;
    if (active == null || api == null) return;
    preferences = value;
    api.updatePreferences(value);
    await store.savePreferences(active, value);
    await refresh();
  }

  Future<void> toggleFavorite(JellyfinItem item) async {
    final api = client;
    if (api == null) return;
    final favorite = !currentItem(item).isFavorite;
    await api.setFavorite(item.id, favorite);
    JellyfinItem update(JellyfinItem value) =>
        value.id == item.id ? value.copyWith(isFavorite: favorite) : value;
    recentlyAdded = recentlyAdded.map(update).toList();
    recentlyPlayed = recentlyPlayed.map(update).toList();
    randomAlbums = randomAlbums.map(update).toList();
    albums = albums.map(update).toList();
    artists = artists.map(update).toList();
    songs = songs.map(update).toList();
    playlists = playlists.map(update).toList();
    genres = genres.map(update).toList();
    downloads = downloads.map(update).toList();
    favorites = favorite
        ? [
            ...favorites.where((value) => value.id != item.id),
            item.copyWith(isFavorite: true),
          ]
        : favorites.where((value) => value.id != item.id).toList();
    notifyListeners();
  }

  JellyfinItem currentItem(JellyfinItem fallback) {
    for (final collection in [
      recentlyAdded,
      recentlyPlayed,
      randomAlbums,
      albums,
      artists,
      songs,
      playlists,
      favorites,
      genres,
      downloads,
    ]) {
      for (final item in collection) {
        if (item.id == fallback.id) return item;
      }
    }
    return fallback;
  }

  Future<void> _restoreLibraryCache(JellyfinSession active) async {
    final saved = await store.loadLibraryCache(active);
    if (saved == null || session?.deviceId != active.deviceId) return;
    List<JellyfinItem> items(String key) => (saved[key] as List? ?? const [])
        .whereType<Map>()
        .map((value) => JellyfinItem.fromJson(value.cast<String, dynamic>()))
        .where((value) => value.id.isNotEmpty)
        .toList();
    recentlyAdded = items('recentlyAdded');
    recentlyPlayed = items('recentlyPlayed');
    randomAlbums = items('randomAlbums');
    albums = items('albums');
    artists = items('artists');
    songs = items('songs');
    playlists = items('playlists');
    favorites = items('favorites');
    genres = items('genres');
    musicLibraries = (saved['musicLibraries'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => JellyfinLibrary.fromJson(value.cast<String, dynamic>()))
        .where((value) => value.id.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> _libraryCacheJson() => {
    'recentlyAdded': recentlyAdded.map((value) => value.toJson()).toList(),
    'recentlyPlayed': recentlyPlayed.map((value) => value.toJson()).toList(),
    'randomAlbums': randomAlbums.map((value) => value.toJson()).toList(),
    'albums': albums.map((value) => value.toJson()).toList(),
    'artists': artists.map((value) => value.toJson()).toList(),
    'songs': songs.map((value) => value.toJson()).toList(),
    'playlists': playlists.map((value) => value.toJson()).toList(),
    'favorites': favorites.map((value) => value.toJson()).toList(),
    'genres': genres.map((value) => value.toJson()).toList(),
    'musicLibraries': musicLibraries.map((value) => value.toJson()).toList(),
  };

  Future<void> manageServers() async {
    if (managingServers) return;
    _statusBeforeServerManagement = status;
    _errorBeforeServerManagement = errorMessage;
    editingServer = null;
    servers = await store.loadAll();
    managingServers = true;
    errorMessage = null;
    notifyListeners();
  }

  void cancelServerManagement() {
    if (!managingServers) return;
    managingServers = false;
    editingServer = null;
    status = _statusBeforeServerManagement ?? status;
    errorMessage = _errorBeforeServerManagement;
    _statusBeforeServerManagement = null;
    _errorBeforeServerManagement = null;
    notifyListeners();
  }

  Future<void> selectServer(JellyfinSession value) async {
    await store.save(value);
    servers = await store.loadAll();
    await connect(value);
  }

  void editServer(JellyfinSession value) {
    editingServer = value;
    errorMessage = null;
    notifyListeners();
  }

  void cancelServerEdit() {
    editingServer = null;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> removeServer(JellyfinSession value) async {
    final removingActive = session?.deviceId == value.deviceId;
    if (removingActive) await pauseDownloads();
    await store.remove(value);
    if (editingServer?.deviceId == value.deviceId) editingServer = null;
    if (removingActive) {
      _disconnect();
      _statusBeforeServerManagement = null;
      _errorBeforeServerManagement = null;
      status = AppStatus.signedOut;
    }
    servers = await store.loadAll();
    notifyListeners();
  }

  Future<void> logout() async {
    final active = session;
    managingServers = false;
    _statusBeforeServerManagement = null;
    _errorBeforeServerManagement = null;
    _disconnect();
    status = AppStatus.loading;
    notifyListeners();
    if (active == null) {
      await store.deactivate();
    } else {
      await store.remove(active);
    }
    servers = await store.loadAll();
    status = AppStatus.signedOut;
    errorMessage = null;
    notifyListeners();
  }

  void _disconnect() {
    client?.close();
    client = null;
    session = null;
    recentlyAdded = recentlyPlayed = randomAlbums = albums = artists = songs =
        playlists = favorites = genres = const [];
    downloads = downloadedCatalog = const [];
    artworkUris = const {};
    downloadedBytes = 0;
    _resetDownloadQueue();
    _refreshingClient = null;
    musicLibraries = const [];
    preferences = const AppPreferences();
  }

  @override
  void dispose() {
    _disposed = true;
    _resetDownloadQueue();
    client?.close();
    super.dispose();
  }
}
