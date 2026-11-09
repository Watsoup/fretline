import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/lesson.dart';

const supportedSchema = 1;

class FretpackError implements Exception {
  final String message;
  FretpackError(this.message);
  @override
  String toString() => 'Invalid .fretpack: $message';
}

/// A parsed package fully in memory.
class FretPack {
  final Manifest manifest;
  final Lesson lesson;
  final Map<String, Uint8List> files; // every file in the zip, by path
  FretPack(this.manifest, this.lesson, this.files);
}

/// What the player needs: data + a way to address each stem for the audio engine.
class LoadedSong {
  final Manifest manifest;
  final Lesson lesson;
  final Uri Function(String path) stemUri;
  LoadedSong(this.manifest, this.lesson, this.stemUri);
}

Uint8List _bytes(ArchiveFile f) => f.content;

FretPack parseFretpack(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw FretpackError('not a zip file');
  }
  final files = <String, Uint8List>{};
  for (final f in zip.files) {
    if (f.isFile) files[f.name] = _bytes(f);
  }
  Map<String, dynamic> json(String name) {
    final b = files[name];
    if (b == null) throw FretpackError('missing $name');
    return jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
  }

  final manifest = Manifest.fromJson(json('manifest.json'));
  if (manifest.schemaVersion > supportedSchema) {
    throw FretpackError('made by a newer Fretline (schema ${manifest.schemaVersion}); update the app');
  }
  final lesson = Lesson.fromJson(json('lesson.json'));
  if (lesson.parts.isEmpty) throw FretpackError('no parts');
  for (final stem in [manifest.backingStem, ...lesson.parts.map((p) => p.stem)]) {
    if (!files.containsKey(stem)) throw FretpackError('missing $stem');
  }
  return FretPack(manifest, lesson, files);
}
