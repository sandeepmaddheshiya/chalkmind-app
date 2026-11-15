import 'background_style.dart';
import 'pdf_page_attachment.dart';
import 'plot_model.dart';
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
  final List<PlotObject> plots;

  /// Imported PDF page shown under the ink (null for ordinary pages).
  final PdfPageAttachment? pdf;

  const PageModel({
    required this.id,
    required this.pageNumber,
    this.background = const CanvasBackground(),
    this.strokes = const [],
    this.shapes = const [],
    this.texts = const [],
    this.plots = const [],
    this.pdf,
  });

  bool get isEmpty =>
      strokes.isEmpty && shapes.isEmpty && texts.isEmpty && plots.isEmpty;
  int get totalElements =>
      strokes.length + shapes.length + texts.length + plots.length;

  PageModel copyWith({
    String? id,
    int? pageNumber,
    CanvasBackground? background,
    List<Stroke>? strokes,
    List<ShapeObject>? shapes,
    List<TextObject>? texts,
    List<PlotObject>? plots,
    PdfPageAttachment? pdf,
  }) {
    return PageModel(
      id: id ?? this.id,
      pageNumber: pageNumber ?? this.pageNumber,
      background: background ?? this.background,
      strokes: strokes ?? this.strokes,
      shapes: shapes ?? this.shapes,
      texts: texts ?? this.texts,
      plots: plots ?? this.plots,
      pdf: pdf ?? this.pdf,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pageNumber': pageNumber,
    'background': background.toJson(),
    'strokes': strokes.map((s) => s.toJson()).toList(),
    'shapes': shapes.map((s) => s.toJson()).toList(),
    'texts': texts.map((t) => t.toJson()).toList(),
    'plots': plots.map((p) => p.toJson()).toList(),
    if (pdf != null) 'pdf': pdf!.toJson(),
  };

  factory PageModel.fromJson(Map<String, dynamic> json) {
    return PageModel(
      id: json['id'] as String,
      pageNumber: json['pageNumber'] as int? ?? 1,
      background: json['background'] != null
          ? CanvasBackground.fromJson(
              json['background'] as Map<String, dynamic>,
            )
          : const CanvasBackground(),
      strokes:
          (json['strokes'] as List<dynamic>?)
              ?.map((s) => Stroke.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      shapes:
          (json['shapes'] as List<dynamic>?)
              ?.map((s) => ShapeObject.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      texts:
          (json['texts'] as List<dynamic>?)
              ?.map((t) => TextObject.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      pdf: json['pdf'] is Map<String, dynamic>
          ? PdfPageAttachment.fromJson(json['pdf'] as Map<String, dynamic>)
          : null,
      plots:
          (json['plots'] as List<dynamic>?)
              ?.map((p) => PlotObject.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
