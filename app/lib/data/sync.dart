import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A Fretline PC on the LAN.
class PcHost {
  final String name, address;
  final int port;
  PcHost(this.name, this.address, this.port);
  Uri get base => Uri.parse('http://$address:$port');
  String get label => '$name ($address:$port)';
}

class RemotePackage {
  final String id, title, artist, url;
  final double duration;
  final int size;
  RemotePackage.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String? ?? 'Untitled',
        artist = j['artist'] as String? ?? '',
        url = j['url'] as String,
        duration = (j['duration'] as num?)?.toDouble() ?? 0,
        size = j['size'] as int? ?? 0;
}

/// Parse what the user scanned or typed:
///   "http://192.168.1.20:8765/app/"  (the desktop QR code)
///   "192.168.1.20:8765" or "192.168.1.20"
PcHost? parseHost(String text) {
  var t = text.trim();
  if (t.isEmpty) return null;
  if (!t.contains('://')) t = 'http://$t';
  final u = Uri.tryParse(t);
  if (u == null || u.host.isEmpty || u.scheme != 'http') return null;
  return PcHost('PC', u.host, u.hasPort ? u.port : 8765);
}

/// Check that a Fretline backend answers at [host].
Future<bool> ping(PcHost host) async {
  try {
    final r = await http.get(host.base.resolve('/health')).timeout(const Duration(seconds: 3));
    return r.statusCode == 200 && (jsonDecode(r.body) as Map)['name'] == 'fretline';
  } catch (_) {
    return false;
  }
}

Future<List<RemotePackage>> listPackages(PcHost host) async {
  final r = await http.get(host.base.resolve('/packages')).timeout(const Duration(seconds: 5));
  if (r.statusCode != 200) throw Exception('PC answered ${r.statusCode}');
  return (jsonDecode(r.body) as List).map((j) => RemotePackage.fromJson(j as Map<String, dynamic>)).toList();
}

/// Download with progress (0..1).
Future<Uint8List> download(PcHost host, RemotePackage p, void Function(double) onProgress) async {
  final req = http.Request('GET', host.base.resolve(p.url));
  final res = await http.Client().send(req);
  if (res.statusCode != 200) throw Exception('download failed (${res.statusCode})');
  final total = res.contentLength ?? p.size;
  final b = BytesBuilder(copy: false);
  await for (final chunk in res.stream) {
    b.add(chunk);
    if (total > 0) onProgress(b.length / total);
  }
  return b.takeBytes();
}
