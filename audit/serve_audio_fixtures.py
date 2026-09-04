"""Serve generated quiet audio for integration_test/codec_test.dart (requires ffmpeg)."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse
import subprocess
import tempfile

root = Path(tempfile.mkdtemp(prefix='shrimphony-codecs-'))
formats = {'mp3': ('mp3', 'libmp3lame'), 'aac': ('aac', 'aac'), 'm4a': ('m4a', 'aac'),
           'alac': ('m4a', 'alac'), 'flac': ('flac', 'flac'), 'flac24': ('flac', 'flac'),
           'flac32': ('flac', 'flac'), 'ogg': ('ogg', 'vorbis'), 'opus': ('opus', 'libopus'), 'wav': ('wav', 'pcm_s16le')}
ffmpeg = ['/opt/homebrew/bin/ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
          'sine=frequency=440:sample_rate=48000:duration=2', '-af', 'volume=0.01', '-ac', '2', '-strict', 'experimental']
for name, (extension, codec) in formats.items():
    depth = ['-sample_fmt', 's16'] if name == 'flac' else ['-sample_fmt', 's32', '-bits_per_raw_sample', name[4:]] if name.startswith('flac') else []
    subprocess.run([*ffmpeg, '-c:a', codec, *depth, str(root / f'{name}.{extension}')], check=True)
subprocess.run([*ffmpeg, '-c:a', 'aac', '-f', 'hls', '-hls_time', '1', '-hls_list_size', '0',
                '-hls_segment_filename', str(root / 'segment%d.ts'), str(root / 'master.m3u8')], check=True)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        parts = urlparse(self.path).path.split('/')
        name = next((part for part in parts if part in formats), None)
        leaf = parts[-1]
        if leaf == 'master.m3u8' or leaf in ['segment0.ts', 'segment1.ts', 'segment2.ts']:
            file = root / leaf
        elif name is not None:
            extension = formats[name][0]
            file = root / ('m4a.m4a' if leaf == 'stream.m4a' and extension not in ['m4a'] else f'{name}.{extension}')
        else:
            self.send_error(404)
            return
        data = file.read_bytes()
        start, end = 0, len(data) - 1
        if 'Range' in self.headers:
            left, right = self.headers['Range'].split('=')[1].split('-')
            start = int(left or 0)
            end = min(int(right or end), end)
        if start > end:
            self.send_error(416)
            return
        self.send_response(206 if 'Range' in self.headers else 200)
        mime = {'mp3': 'audio/mpeg', 'aac': 'audio/aac', 'm4a': 'audio/mp4', 'flac': 'audio/flac',
                'ogg': 'audio/ogg', 'opus': 'audio/ogg', 'wav': 'audio/wav', 'm3u8': 'application/vnd.apple.mpegurl', 'ts': 'video/mp2t'}
        self.send_header('Content-Type', mime[file.suffix[1:]])
        self.send_header('Accept-Ranges', 'bytes')
        if 'Range' in self.headers:
            self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
        self.send_header('Content-Length', str(end - start + 1))
        self.end_headers()
        try:
            self.wfile.write(data[start:end + 1])
        except (BrokenPipeError, ConnectionResetError):
            pass

print('Audio fixtures ready on http://127.0.0.1:8765', flush=True)
ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
