import 'background_style.dart';
import 'shape_model.dart';
import 'stroke_model.dart';
import 'text_model.dart';

class PageModel {
  final String id;
  final int pageNumber;
  final CanvasBackground background;
  final List<Stroke> strokes;
  final List<ShapeObject> shapes;
  final List<TextObject> texts;

  const PageModel({
    required this.id,
    required this.pageNumber,
    this.background = const CanvasBackground(),
    this.strokes = const [],
    this.shapes = const [],
    this.texts = const [],
  });

  bool get isEmpty => strokes.isEmpty && shapes.isEmpty && texts.isEmpty;
  int get totalElements => strokes.length + shapes.length + texts.length;

  PageModel copyWith({
    String? id,
    int? pageNumber,
    CanvasBackground? background,
    List<Stroke>? strokes,
    List<ShapeObject>? shapes,
    List<TextObject>? texts,
  }) {
    return PageModel(
      id: id ?? this.id,
      pageNumber: pageNumber ?? this.pageNumber,
      background: background ?? this.background,
      strokes: strokes ?? this.strokes,
      shapes: shapes ?? this.shapes,
      texts: texts ?? this.texts,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pageNumber': pageNumber,
    'background': background.toJson(),
    'strokes': strokes.map((s) => s.toJson()).toList(),
    'shapes': shapes.map((s) => s.toJson()).toList(),
    'texts': texts.map((t) => t.toJson()).toList(),
  };

  factory PageModel.fromJson(Map<String, dynamic> json) {
    return PageModel(
      id: json['id'] as String,
      pageNumber: json['pageNumber'] as int? ?? 1,
      background: json['background'] != null
          ? CanvasBackground.fromJson(json['background'] as Map<String, dynamic>)
          : const CanvasBackground(),
      strokes: (json['strokes'] as List<dynamic>?)
              ?.map((s) => Stroke.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      shapes: (json['shapes'] as List<dynamic>?)
              ?.map((s) => ShapeObject.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      texts: (json['texts'] as List<dynamic>?)
              ?.map((t) => TextObject.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
