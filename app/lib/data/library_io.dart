import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/lesson.dart';
import 'fretpack.dart';
import 'library.dart';

LibraryStore createStore() => _FileLibrary();

/// Each song is extracted to `<app documents>/library/<id>/` so stems can be
/// played straight from disk.
class _FileLibrary extends LibraryStore {
  Directory? _root;

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory('${docs.path}/fretline/library');
    await _root!.create(recursive: true);
    return _root!;
  }

  bool _safeId(String id) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  @override
  bool get supportsLanSync => true;

  @override
  Future<List<Manifest>> list() async {
    final root = await _dir();
    final out = <Manifest>[];
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final f = File('${e.path}/manifest.json');
      if (!await f.exists()) continue;
      try {
        out.add(Manifest.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // skip broken entries
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  @override
  Future<Manifest> importBytes(Uint8List bytes) async {
    final pack = parseFretpack(bytes);
    final id = pack.manifest.id;
    if (!_safeId(id)) throw FretpackError('bad id "$id"');
    final root = await _dir();
    final tmp = Directory('${root.path}/.$id.tmp');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    for (final entry in pack.files.entries) {
      final name = entry.key;
      if (name.contains('..') || name.startsWith('/')) continue;
      final f = File('${tmp.path}/$name');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(entry.value, flush: true);
    }
    final dst = Directory('${root.path}/$id');
    if (await dst.exists()) await dst.delete(recursive: true);
    await tmp.rename(dst.path);
    return pack.manifest;
  }

  @override
  Future<void> delete(String id) async {
    if (!_safeId(id)) return;
    final d = Directory('${(await _dir()).path}/$id');
    if (await d.exists()) await d.delete(recursive: true);
  }

  @override
  Future<LoadedSong> load(String id) async {
    final d = Directory('${(await _dir()).path}/$id');
    Future<Map<String, dynamic>> read(String n) async =>
        jsonDecode(await File('${d.path}/$n').readAsString()) as Map<String, dynamic>;
    final manifest = Manifest.fromJson(await read('manifest.json'));
    final lesson = Lesson.fromJson(await read('lesson.json'));
    return LoadedSong(manifest, lesson, (path) => Uri.file('${d.path}/$path'));
  }
}
