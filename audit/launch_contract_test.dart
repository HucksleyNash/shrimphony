// Audit reproductions, 2026-09-04. Both expectations describe launch behavior.
// Run from Shrimphony: flutter test --no-pub <path-to-this-file>
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shrimphony/jellyfin.dart';

void main() {
  late HttpServer server;
  late JellyfinClient client;
  late Directory support;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('shrimphony-contract-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = JellyfinClient(
      JellyfinSession(
        serverUrl: 'http://127.0.0.1:${server.port}',
        accessToken: 'audit-only',
        userId: 'audit-user',
        username: 'Audit',
        deviceId: 'audit-device',
      ),
    );
    server.listen((request) async {
      final query = request.uri.queryParameters;
      final items = query['ParentId'] == 'album'
          ? [
              {
                'Id': 'disc1track1',
                'Name': 'Z first',
                'Type': 'Audio',
                'ParentIndexNumber': 1,
                'IndexNumber': 1,
              },
              {
                'Id': 'disc1track2',
                'Name': 'A second',
                'Type': 'Audio',
                'ParentIndexNumber': 1,
                'IndexNumber': 2,
              },
              {
                'Id': 'disc2track1',
                'Name': 'M third',
                'Type': 'Audio',
                'ParentIndexNumber': 2,
                'IndexNumber': 1,
              },
            ]
          : query['IncludeItemTypes'] == 'Audio'
          ? List.generate(
              12,
              (i) => {
                'Id': 'song-$i',
                'Name': 'Song ${i.toString().padLeft(2, '0')}',
                'Type': 'Audio',
              },
            )
          : <Map<String, Object>>[];
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'Items': items, 'TotalRecordCount': items.length}),
      );
      await request.response.close();
    });
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await support.delete(recursive: true);
  });

  test('album playback preserves the server disc and track order', () async {
    final tracks = await client.children('album');
    expect(tracks.map((item) => item.id), [
      'disc1track1',
      'disc1track2',
      'disc2track1',
    ]);
  });

  test('artist detail collection actions receive every artist song', () async {
    final controller = AppController(
      JellyfinSessionStore(supportDirectory: support),
    )..client = client;
    try {
      // _DetailScreen uses this exact audio subset for Play, Shuffle and
      // Download all songs; it currently receives only the ten-song preview.
      final children = await controller.children(
        const JellyfinItem(id: 'artist', name: 'Artist', type: 'MusicArtist'),
      );
      expect(children.where((item) => item.isAudio), hasLength(12));
    } finally {
      controller.dispose();
    }
  });
}
