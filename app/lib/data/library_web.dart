import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/lesson.dart';
import 'fretpack.dart';
import 'library.dart';

LibraryStore createStore() => _WebLibrary();

@JS('window.location.assign')
external void _assign(String url);

/// PWA (iOS): when the app is served by the PC backend (`http://<pc>:8765/app/`),
/// the PC library is listed and stems are streamed from it. Files opened
/// locally are kept in memory for this session.
class _WebLibrary extends LibraryStore {
  final Map<String, FretPack> _local = {};
  final Uri _base = Uri.base;

  bool get _servedByPc => _base.scheme.startsWith('http') && _base.path.startsWith('/app');

  @override
  bool get supportsLanSync => false;

  bool get _onThisPc => const {'127.0.0.1', 'localhost', '::1', '[::1]'}.contains(_base.host);

  @override
  Uri? get desktopUiUrl => _servedByPc && _onThisPc ? _base.resolve('/ui/') : null;

  @override
  void openDesktopUi() {
    final u = desktopUiUrl;
    if (u != null) _assign(u.toString());
  }

  @override
  String? get initialSongId => _base.queryParameters['song'];

  @override
  Future<List<Manifest>> list() async {
    final out = _local.values.map((p) => p.manifest).toList();
    if (_servedByPc) {
      try {
        final r = await http.get(_base.resolve('/packages'));
        if (r.statusCode == 200) {
          for (final j in jsonDecode(r.body) as List) {
            final m = Manifest.fromJson(j as Map<String, dynamic>);
            if (!_local.containsKey(m.id)) out.add(m);
          }
        }
      } catch (_) {
        // PC offline: only local imports
      }
    }
    return out;
  }

  @override
  Future<Manifest> importBytes(Uint8List bytes) async {
    final p = parseFretpack(bytes);
    _local[p.manifest.id] = p;
    return p.manifest;
  }

  @override
  Future<void> delete(String id) async => _local.remove(id);

  @override
  Future<LoadedSong> load(String id) async {
    final p = _local[id];
    if (p != null) {
      return LoadedSong(p.manifest, p.lesson,
          (path) => Uri.dataFromBytes(p.files[path]!, mimeType: 'audio/ogg'));
    }
    final r = await http.get(_base.resolve('/packages/$id/lesson'));
    if (r.statusCode != 200) throw FretpackError('could not load song from PC (${r.statusCode})');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return LoadedSong(
      Manifest.fromJson(j['manifest'] as Map<String, dynamic>),
      Lesson.fromJson(j['lesson'] as Map<String, dynamic>),
      (path) => _base.resolve('/packages/$id/files/$path'),
    );
  }
}
