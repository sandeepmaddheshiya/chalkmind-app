// Home-screen listing reads small summary files instead of decoding every
// board's drawing; summaries can never be saved over or opened as boards.
import 'dart:convert';
import 'dart:io';

import 'package:boardflow/core/storage/project_storage_service.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/hand_drawn.dart';

ProjectModel bigBoard(String title, {int strokes = 300}) {
  final p = ProjectModel.createEmpty(title: title);
  return p.copyWith(pages: [
    p.pages.first.copyWith(strokes: [for (int i = 0; i < strokes; i++) handDrawn(sides: 0, radius: 40, seed: i)]),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bf_list'));
  tearDown(() => dir.deleteSync(recursive: true));

  String writeBoard(ProjectModel p) {
    final path = '${dir.path}/${p.id}.bf';
    File(path).writeAsStringSync(jsonEncode(p.toJson()));
    return path;
  }

  test('lists summaries (title, pages) without drawing data, and caches them', () {
    final path = writeBoard(bigBoard('Algebra lesson'));
    final first = listProjectSummaries([path]);
    expect(first.single.title, 'Algebra lesson');
    expect(first.single.isSummary, isTrue);
    expect(first.single.totalPages, 1);
    expect(first.single.pages.single.strokes, isEmpty, reason: 'no drawing in the listing');
    expect(File(metaPathFor(path)).existsSync(), isTrue, reason: 'summary cached for next time');

    // Second listing reads the small summary file.
    final second = listProjectSummaries([path]);
    expect(second.single.title, 'Algebra lesson');
  });

  test('a board changed after its summary is re-summarised', () async {
    final p = bigBoard('Old title', strokes: 5);
    final path = writeBoard(p);
    listProjectSummaries([path]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    File(path).writeAsStringSync(jsonEncode(p.copyWith(title: 'New title').toJson()));
    File(path).setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));
    expect(listProjectSummaries([path]).single.title, 'New title');
  });

  test('unreadable boards are skipped, not fatal', () {
    final good = writeBoard(bigBoard('Good', strokes: 2));
    final bad = '${dir.path}/broken.bf';
    File(bad).writeAsStringSync('{ not json');
    expect(listProjectSummaries([bad, good]).map((p) => p.title), ['Good']);
  });

  test('a summary can never be saved over a board', () async {
    final summary = bigBoard('x', strokes: 1).summary();
    await expectLater(ProjectStorageService().saveProject(summary), throwsStateError);
  });

  test('a summary can never be opened in the editor', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(
      () => c.read(whiteboardControllerProvider.notifier).loadProject(bigBoard('x', strokes: 1).summary()),
      throwsArgumentError,
    );
  });

  test('listing with summaries is much faster than decoding full boards', () {
    final paths = [for (int i = 0; i < 20; i++) writeBoard(bigBoard('Board $i'))];
    listProjectSummaries(paths); // first run writes summaries
    final full = Stopwatch()..start();
    for (final p in paths) {
      decodeProjectJson(File(p).readAsStringSync());
    }
    full.stop();
    final fast = Stopwatch()..start();
    final listed = listProjectSummaries(paths);
    fast.stop();
    expect(listed.length, 20);
    // ignore: avoid_print
    print('BENCH list 20 boards: full decode ${full.elapsedMilliseconds} ms -> summaries ${fast.elapsedMilliseconds} ms');
    expect(fast.elapsedMicroseconds, lessThan(full.elapsedMicroseconds / 5));
  });
}
