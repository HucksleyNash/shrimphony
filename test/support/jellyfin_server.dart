import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shrimphony/jellyfin.dart';

// A local Jellyfin contract server with real, seekable PCM audio. No music credentials.
class TestMusicServer {
  late HttpServer server;
  int status = 200;
  bool slowDownload = false;
  bool brokenAudio = false;
  Completer<void>? pageGate;
  final List<Uri> requests = [];
  final List<Map<String, dynamic>> reports = [];
  final Set<String> favorites = {};
  final int songCount;
  late final List<Map<String, dynamic>> tracks;
  final Uint8List audio = wavAudio();

  TestMusicServer({this.songCount = 12}) {
    tracks = List.generate(
      songCount,
      (i) => {
        'Id': 'song-$i',
        'Name': i == 0
            ? 'Z first'
            : i == 1
            ? 'A second'
            : 'Song $i',
        'Type': 'Audio',
        'Album': 'Test Album',
        'AlbumId': 'album',
        'AlbumPrimaryImageTag': 'art',
        'Artists': ['Test Artist'],
        'ArtistItems': [
          {'Id': 'artist', 'Name': 'Test Artist'},
        ],
        'AlbumArtist': 'Test Artist',
        'Genres': ['Rock'],
        'ParentIndexNumber': i ~/ 6 + 1,
        'IndexNumber': i % 6 + 1,
        'Container': 'wav',
        'RunTimeTicks': 300000000,
        'DateCreated': '2026-09-01T00:00:00Z',
        'UserData': {
          'IsFavorite': false,
          'LastPlayedDate': '2026-09-01T00:00:00Z',
        },
      },
    );
  }

  JellyfinSession get session => JellyfinSession(
    serverUrl: 'http://127.0.0.1:${server.port}',
    accessToken: 'test-token',
    userId: 'test-user',
    username: 'Tester',
    deviceId: 'test-device',
  );

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await _respond(request);
      } on Object {
        try {
          await request.response.close();
        } on Object {
          /* cancelled request */
        }
      }
    });
  }

  Future<void> close() => server.close(force: true);

  Future<void> _respond(HttpRequest request) async {
    requests.add(request.uri);
    final body = await utf8.decoder.bind(request).join();
    final path = request.uri.path;
    final query = request.uri.queryParameters;
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (status != 200) {
      response.statusCode = status;
      await response.close();
      return;
    }
    if (path.endsWith('/AuthenticateByName')) {
      if ((jsonDecode(body) as Map)['Pw'] != 'test-password') {
        response.statusCode = 401;
      } else {
        response.write(
          jsonEncode({
            'AccessToken': 'test-token',
            'User': {'Id': 'test-user', 'Name': 'Tester'},
          }),
        );
      }
    } else if (path.endsWith('/Images/Primary')) {
      response.headers.contentType = ContentType('image', 'png');
      response.add(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aP3sAAAAASUVORK5CYII=',
        ),
      );
    } else if (path.endsWith('/Download') || path.startsWith('/Audio/')) {
      if (brokenAudio) {
        response.statusCode = 503;
        await response.close();
        return;
      }
      response.headers.contentType = ContentType('audio', 'wav');
      response.headers.set('accept-ranges', 'bytes');
      final range = request.headers.value('range');
      final start = range == null
          ? 0
          : int.tryParse(range.split('=')[1].split('-')[0]) ?? 0;
      final requestedEnd = range == null
          ? null
          : int.tryParse(range.split('=')[1].split('-').last);
      final end = min(requestedEnd ?? audio.length - 1, audio.length - 1);
      if (start >= audio.length) {
        response.statusCode = 416;
        await response.close();
        return;
      }
      if (range != null) {
        response.statusCode = 206;
        response.headers.set(
          'content-range',
          'bytes $start-$end/${audio.length}',
        );
      }
      response.contentLength = end - start + 1;
      for (var offset = start; offset <= end; offset += 16384) {
        response.add(audio.sublist(offset, min(offset + 16384, end + 1)));
        if (slowDownload) {
          await response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }
    } else if (path == '/UserViews') {
      response.write(
        jsonEncode({
          'Items': [
            {'Id': 'music', 'Name': 'Music', 'CollectionType': 'music'},
          ],
        }),
      );
    } else if (path.startsWith('/Sessions/Playing')) {
      reports.add({
        'path': path,
        if (body.isNotEmpty) ...jsonDecode(body) as Map<String, dynamic>,
      });
    } else if (path == '/Sessions') {
      response.write('[]');
    } else if (path.contains('/FavoriteItems/')) {
      final id = path.split('/').last;
      if (request.method == 'POST') {
        favorites.add(id);
      } else {
        favorites.remove(id);
      }
    } else if (path.startsWith('/Items/song-') &&
        !path.endsWith('/InstantMix')) {
      response.write(
        jsonEncode(
          tracks.firstWhere((item) => item['Id'] == path.split('/').last),
        ),
      );
    } else {
      final type = query['IncludeItemTypes'] ?? '';
      var items = path == '/MusicGenres'
          ? <Map<String, dynamic>>[
              {'Id': 'genre', 'Name': 'Rock', 'Type': 'MusicGenre'},
            ]
          : (type == 'MusicArtist' || path == '/Artists')
          ? <Map<String, dynamic>>[
              {'Id': 'artist', 'Name': 'Test Artist', 'Type': 'MusicArtist'},
            ]
          : type == 'MusicAlbum'
          ? <Map<String, dynamic>>[
              {
                'Id': 'album',
                'Name': 'Test Album',
                'Type': 'MusicAlbum',
                'ImageTags': {'Primary': 'art'},
              },
            ]
          : type == 'Playlist'
          ? <Map<String, dynamic>>[
              {'Id': 'playlist', 'Name': 'Test Playlist', 'Type': 'Playlist'},
            ]
          : path.contains('/Playlists/')
          ? <Map<String, dynamic>>[
              for (var i = 0; i < 3; i++)
                {...tracks[i % 2], 'PlaylistItemId': 'entry-$i'},
            ]
          : tracks;
      final search = query['SearchTerm'];
      if (search != null) {
        items = items
            .where(
              (item) => '${item['Name']} ${item['Artists']}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
            )
            .toList();
      }
      if (query['Filters'] == 'IsFavorite') {
        items = items.where((item) => favorites.contains(item['Id'])).toList();
      }
      final start = int.tryParse(query['StartIndex'] ?? '') ?? 0;
      if (start > 0 && pageGate != null) await pageGate!.future;
      final limit = int.tryParse(query['Limit'] ?? '') ?? 250;
      response.write(
        jsonEncode({
          'Items': items.skip(start).take(limit).toList(),
          'TotalRecordCount': items.length,
        }),
      );
    }
    await response.close();
  }
}

Uint8List wavAudio() {
  const sampleRate = 8000;
  const samples = sampleRate * 30;
  final data = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
      44 + i * 2,
      (sin(i * 2 * pi * 440 / sampleRate) * 100).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
