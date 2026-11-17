// Tests for the AI layer against a mock HTTP server (no network, no key).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:boardflow/core/ai/ai_config.dart';
import 'package:boardflow/core/ai/openrouter_client.dart';
import 'package:boardflow/features/whiteboard/assistant/board_assistant.dart';
import 'package:boardflow/features/whiteboard/assistant/board_context.dart';
import 'package:boardflow/features/whiteboard/assistant/diagram_builder.dart';
import 'package:boardflow/features/whiteboard/models/page_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/text_model.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/recognition/ai_math_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _cfg = AiConfig(userApiKey: 'test-key', model: 'primary/model');

/// UTF-8 JSON response, as the real API sends it.
http.Response _ok(String content) => http.Response.bytes(
      utf8.encode(_completion(content)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _completion(String content) => jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.BaseRequest> requests;
  tearDown(() => OpenRouterClient.clientFactory = http.Client.new);

  void mock(Future<http.Response> Function(http.Request r, int call) handler) {
    requests = [];
    int call = 0;
    OpenRouterClient.clientFactory = () => MockClient((r) {
          requests.add(r);
          return handler(r, call++);
        });
  }

  group('AiConfig', () {
    test('no key ships with the app', () {
      const c = AiConfig();
      expect(c.isConfigured, isFalse);
      expect(c.apiKey, isEmpty);
    });

    test('model candidates: primary then fallback, deduplicated', () {
      expect(_cfg.modelCandidates, ['primary/model', AiConfig.defaultFallbackModel]);
      expect(const AiConfig(userApiKey: 'k', model: AiConfig.defaultFallbackModel).modelCandidates,
          [AiConfig.defaultFallbackModel]);
    });
  });

  group('OpenRouterClient.complete', () {
    test('throws notConfigured without a key and sends nothing', () async {
      mock((r, _) async => http.Response('', 200));
      await expectLater(
        const OpenRouterClient(AiConfig()).complete(messages: const []),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.notConfigured)),
      );
      expect(requests, isEmpty);
    });

    test('sends the key as a bearer token and returns content', () async {
      mock((r, _) async => _ok('hello'));
      final out = await const OpenRouterClient(_cfg).complete(messages: [aiUserMessage('hi')]);
      expect(out, 'hello');
      expect(requests.single.headers['Authorization'], 'Bearer test-key');
      final body = jsonDecode((requests.single as http.Request).body) as Map<String, dynamic>;
      expect(body['model'], 'primary/model');
    });

    test('falls back to the next model on 404 / 5xx', () async {
      mock((r, call) async => call == 0 ? http.Response('no such model', 404) : _ok('ok'));
      final out = await const OpenRouterClient(_cfg).complete(messages: const []);
      expect(out, 'ok');
      expect(requests.length, 2);
      final second = jsonDecode((requests[1] as http.Request).body) as Map<String, dynamic>;
      expect(second['model'], AiConfig.defaultFallbackModel);
    });

    test('does NOT retry other models on 401 (bad key)', () async {
      mock((r, _) async => http.Response('unauthorized', 401));
      await expectLater(
        const OpenRouterClient(_cfg).complete(messages: const []),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.unauthorized)),
      );
      expect(requests.length, 1);
    });

    test('reports rate limiting after exhausting models', () async {
      mock((r, _) async => http.Response('slow down', 429));
      await expectLater(
        const OpenRouterClient(_cfg).complete(messages: const []),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.rateLimited)),
      );
    });

    test('times out instead of hanging', () async {
      mock((r, _) => Completer<http.Response>().future); // never completes
      await expectLater(
        const OpenRouterClient(_cfg).complete(messages: const [], timeout: const Duration(milliseconds: 50)),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.timeout)),
      );
    });

    test('a cancelled token stops before sending', () async {
      mock((r, _) async => _ok('x'));
      final token = AiCancelToken()..cancel();
      await expectLater(
        const OpenRouterClient(_cfg).complete(messages: const [], cancelToken: token),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.cancelled)),
      );
      expect(requests, isEmpty);
    });
  });

  group('SSE streaming', () {
    test('parses deltas, ignores keep-alives, stops at [DONE]', () async {
      final sse = [
        ': OPENROUTER PROCESSING',
        'data: {"choices":[{"delta":{"content":"Hel"}}]}',
        '',
        'data: {"choices":[{"delta":{"content":"lo ²"}}]}',
        'data: {"choices":[{"delta":{}}]}',
        'data: [DONE]',
        'data: {"choices":[{"delta":{"content":"IGNORED"}}]}',
      ].join('\n');
      final out = await OpenRouterClient.parseSseDeltas(Stream.value(utf8.encode(sse))).join();
      expect(out, 'Hello ²');
    });

    test('stream() yields content through the mock transport', () async {
      OpenRouterClient.clientFactory = () => MockClient.streaming((req, body) async {
            final payload = 'data: {"choices":[{"delta":{"content":"A"}}]}\n'
                'data: {"choices":[{"delta":{"content":"B"}}]}\n'
                'data: [DONE]\n';
            return http.StreamedResponse(Stream.value(utf8.encode(payload)), 200);
          });
      final out = await const OpenRouterClient(_cfg).stream(messages: const []).join();
      expect(out, 'AB');
    });
  });

  group('AiMathService', () {
    Stroke s(String id, Offset a, Offset b) => Stroke(
          id: id,
          points: [StrokePoint.fromOffset(a, timestamp: 0), StrokePoint.fromOffset(b, timestamp: 1)],
          colorValue: 0xFF000000,
          width: 3,
          toolType: ToolType.pen,
        );

    test('requires configuration', () async {
      await expectLater(
        AiMathService.solveWithVisionAI(strokes: [s('a', Offset.zero, const Offset(40, 40))], config: const AiConfig()),
        throwsA(isA<AiException>()),
      );
    });

    test('sends an image and parses the JSON answer', () async {
      mock((r, _) async => _ok('{"expression":"9 × 12 =","answer":"108","steps":["9 × 12 = 108"],"explanation":"times"}'));
      final res = await AiMathService.solveWithVisionAI(
        strokes: [s('a', Offset.zero, const Offset(60, 40)), s('b', const Offset(0, 50), const Offset(60, 90))],
        config: _cfg,
      );
      expect(res, isNotNull);
      expect(res!.answer, '108');
      expect(res.steps, isNotEmpty);
      final body = jsonDecode((requests.single as http.Request).body) as Map<String, dynamic>;
      final content = (body['messages'] as List).first['content'] as List;
      expect(content.any((p) => p['type'] == 'image_url'), isTrue);
    });
  });

  group('AI solver beyond maths', () {
    Stroke s(String id, Offset a, Offset b) => Stroke(
          id: id,
          points: [StrokePoint.fromOffset(a, timestamp: 0), StrokePoint.fromOffset(b, timestamp: 1)],
          colorValue: 0xFF000000,
          width: 3,
          toolType: ToolType.pen,
        );
    final strokes = [s('a', Offset.zero, const Offset(60, 40)), s('b', const Offset(0, 50), const Offset(60, 90))];

    test('chemistry answers keep their arrow and are accepted', () async {
      mock((r, _) async => _ok('{"subject":"chemistry","expression":"H₂ + O₂ →","answer":"2H₂ + O₂ → 2H₂O",'
          '"steps":["Count atoms","Balance O","Balance H"],"explanation":"Conserve atoms."}'));
      final res = await AiMathService.solveWithVisionAI(strokes: strokes, config: _cfg);
      expect(res!.answer, '2H₂ + O₂ → 2H₂O');
      expect(res.expression, 'H₂ + O₂ →', reason: 'no stray " =" after the arrow');
      final body = jsonDecode((requests.single as http.Request).body) as Map<String, dynamic>;
      final prompt = ((body['messages'] as List).first['content'] as List).first['text'] as String;
      expect(prompt, contains('chemistry'));
      expect(prompt, contains('physics'));
    });

    test('physics answers with units are accepted', () async {
      mock((r, _) async => _ok('{"subject":"physics","expression":"a = v / t =","answer":"4 m/s²","steps":["20/5"]}'));
      final res = await AiMathService.solveWithVisionAI(strokes: strokes, config: _cfg);
      expect(res!.answer, '4 m/s²');
      expect(res.expression, 'a = v / t =');
    });
  });

  group('BoardAssistant', () {
    test('board context lists typed text in reading order and requests an image for ink', () async {
      final page = PageModel(
        id: 'p',
        pageNumber: 1,
        texts: const [
          TextObject(id: 'b', text: 'second', position: Offset(10, 200), colorValue: 0),
          TextObject(id: 'a', text: 'first', position: Offset(10, 10), colorValue: 0),
        ],
        strokes: [
          Stroke(
            id: 'ink',
            points: [StrokePoint.fromOffset(Offset.zero, timestamp: 0), StrokePoint.fromOffset(const Offset(80, 80), timestamp: 1)],
            colorValue: 0xFF000000,
            width: 3,
            toolType: ToolType.pen,
          ),
        ],
      );
      final ctx = await BoardContext.build(page: page, pageNumber: 1, totalPages: 2);
      expect(ctx.description.indexOf('first'), lessThan(ctx.description.indexOf('second')));
      expect(ctx.description, contains('page 1 of 2'));
      expect(ctx.imageBase64, isNotNull);
      expect(ctx.isSelection, isFalse);

      final selOnly = await BoardContext.build(page: page, pageNumber: 1, totalPages: 2, selectedIds: {'a'});
      expect(selOnly.isSelection, isTrue);
      expect(selOnly.description, isNot(contains('second')));
      expect(selOnly.imageBase64, isNull, reason: 'text-only selection needs no image');
    });

    test('messages include system prompt, bounded history, context and image', () {
      const assistant = BoardAssistant(_cfg);
      const ctx = BoardContext(description: 'Context: x = 2', imageBase64: 'AAAA', isSelection: true, elementCount: 1);
      final msgs = assistant.buildMessages(
        action: AssistantAction.check,
        input: '',
        board: ctx,
        history: [for (int i = 0; i < 10; i++) AssistantTurn(i.isEven, 'turn $i')],
      );
      expect(msgs.first['role'], 'system');
      expect(msgs.length, 1 + 4 + 1, reason: 'only last 4 turns kept');
      final last = msgs.last['content'] as List;
      expect(last.first['text'], contains('FIRST incorrect step'));
      expect(last.first['text'], contains('x = 2'));
      expect(last.any((p) => p['type'] == 'image_url'), isTrue);
    });

    test('lesson plan does not send board content', () {
      const assistant = BoardAssistant(_cfg);
      const ctx = BoardContext(description: 'SECRET BOARD', imageBase64: 'AAAA', isSelection: false, elementCount: 1);
      final msgs = assistant.buildMessages(action: AssistantAction.lessonPlan, input: 'Fractions grade 4', board: ctx);
      final last = msgs.last['content'] as List;
      expect(last.first['text'], isNot(contains('SECRET BOARD')));
      expect(last.any((p) => p['type'] == 'image_url'), isFalse);
    });

    test('toBoardText strips markdown', () {
      expect(BoardAssistant.toBoardText('## Title\n**bold** and - item\n- list'), 'Title\nbold and - item\n• list');
    });

    test('diagram generation end to end (mocked) produces editable elements', () async {
      mock((r, _) async => _ok(
            '```json\n{"title":"Water cycle","nodes":[{"id":"e","label":"Evaporation"},'
                '{"id":"c","label":"Condensation"},{"id":"p","label":"Precipitation"},{"id":"q","label":"Raining?","shape":"diamond"}],'
                '"edges":[{"from":"e","to":"c"},{"from":"c","to":"q"},{"from":"q","to":"p","label":"yes"},{"from":"p","to":"e"},{"from":"x","to":"e"}]}\n```',
          ));
      final spec = await const BoardAssistant(_cfg).generateDiagram(action: AssistantAction.flowchart, topic: 'water cycle');
      expect(spec.nodes.length, 4);
      expect(spec.edges.length, 4, reason: 'edge to unknown node dropped');
      final els = DiagramBuilder.build(spec, origin: const Offset(100, 100));
      final nodeShapes = els.shapes.where((s) => s.shapeType != ShapeType.arrow).toList();
      final arrows = els.shapes.where((s) => s.shapeType == ShapeType.arrow).toList();
      expect(nodeShapes.length, 4);
      expect(nodeShapes.where((s) => s.shapeType == ShapeType.diamond).length, 1);
      expect(arrows.length, 4);
      // No two node boxes overlap.
      for (int i = 0; i < nodeShapes.length; i++) {
        for (int j = i + 1; j < nodeShapes.length; j++) {
          final a = Rect.fromPoints(nodeShapes[i].start, nodeShapes[i].end);
          final b = Rect.fromPoints(nodeShapes[j].start, nodeShapes[j].end);
          expect(a.overlaps(b), isFalse, reason: 'nodes $i and $j overlap');
        }
      }
      // Title + labels + edge label are text objects.
      expect(els.texts.map((t) => t.text), contains('Water cycle'));
      expect(els.texts.map((t) => t.text), contains('yes'));
      // Diagram starts at the requested origin.
      final minY = els.texts.map((t) => t.position.dy).reduce((a, b) => a < b ? a : b);
      expect(minY, closeTo(100, 1));
    });

    test('mind map radial layout keeps nodes apart', () {
      final spec = DiagramSpec.parse(
        jsonEncode({
          'title': 'Fractions',
          'nodes': [
            {'id': 'root', 'label': 'Fractions'},
            for (int i = 0; i < 6; i++) {'id': 'n$i', 'label': 'Branch $i'},
            for (int i = 0; i < 4; i++) {'id': 'm$i', 'label': 'Leaf $i'},
          ],
          'edges': [
            for (int i = 0; i < 6; i++) {'from': 'root', 'to': 'n$i'},
            for (int i = 0; i < 4; i++) {'from': 'n$i', 'to': 'm$i'},
          ],
        }),
        DiagramKind.mindmap,
      );
      final els = DiagramBuilder.build(spec, origin: Offset.zero);
      final boxes = [
        for (final s in els.shapes.where((s) => s.shapeType != ShapeType.arrow)) Rect.fromPoints(s.start, s.end),
      ];
      expect(boxes.length, 11);
      for (int i = 0; i < boxes.length; i++) {
        for (int j = i + 1; j < boxes.length; j++) {
          expect(boxes[i].overlaps(boxes[j]), isFalse, reason: 'boxes $i/$j overlap');
        }
      }
    });

    test('on a page, a large mind map is fitted onto the sheet and stays readable', () {
      final spec = DiagramSpec.parse(
        jsonEncode({
          'title': 'Photosynthesis',
          'nodes': [
            {'id': 'root', 'label': 'Photosynthesis'},
            for (int i = 0; i < 8; i++) {'id': 'n$i', 'label': 'Branch with a long label $i'},
            for (int i = 0; i < 8; i++) {'id': 'm$i', 'label': 'Leaf detail $i'},
          ],
          'edges': [
            for (int i = 0; i < 8; i++) {'from': 'root', 'to': 'n$i'},
            for (int i = 0; i < 8; i++) {'from': 'n$i', 'to': 'm$i'},
          ],
        }),
        DiagramKind.mindmap,
      );
      // Inserted near the right edge, as when the user looks at that area.
      final raw = DiagramBuilder.build(spec, origin: const Offset(700, 300));
      const sheet = Rect.fromLTWH(70, 70, 1040, 1490);
      expect(raw.bounds.right, greaterThan(sheet.right), reason: 'precondition: overflows the page');
      final fitted = raw.fitInto(sheet);
      final b = fitted.bounds;
      expect(b.left, greaterThanOrEqualTo(sheet.left - 0.5));
      expect(b.right, lessThanOrEqualTo(sheet.right + 0.5));
      expect(b.top, greaterThanOrEqualTo(sheet.top - 0.5));
      expect(b.bottom, lessThanOrEqualTo(sheet.bottom + 0.5));
      expect(fitted.texts.map((t) => t.fontSize).reduce((a, c) => a < c ? a : c), greaterThanOrEqualTo(14 * 0.5));
      // Already fitting: unchanged.
      final small = DiagramBuilder.build(spec, origin: const Offset(100, 100));
      if (small.bounds.width <= sheet.width && small.bounds.height <= sheet.height) {
        expect(identical(small.fitInto(sheet), small), isTrue);
      }
    });

    test('invalid diagram output raises a bad-response error', () async {
      mock((r, _) async => _ok('Sorry, I cannot draw that.'));
      await expectLater(
        const BoardAssistant(_cfg).generateDiagram(action: AssistantAction.mindMap, topic: 'x'),
        throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.badResponse)),
      );
    });
  });

  group('UploadedImage', () {
    test('rejects non-images by signature, not extension', () async {
      await expectLater(
        UploadedImage.prepare(Uint8List.fromList(utf8.encode('#!/bin/sh\nrm -rf /'))),
        throwsA(isA<FormatException>()),
      );
      await expectLater(UploadedImage.prepare(Uint8List(0)), throwsA(isA<FormatException>()));
    });

    test('rejects oversized files', () async {
      final big = Uint8List(UploadedImage.maxBytes + 1)..setAll(0, [0x89, 0x50, 0x4E, 0x47]);
      await expectLater(UploadedImage.prepare(big), throwsA(isA<FormatException>()));
    });

    test('rejects a truncated PNG that cannot be decoded', () async {
      final fake = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
      await expectLater(UploadedImage.prepare(fake), throwsA(isA<FormatException>()));
    });
  });
}
