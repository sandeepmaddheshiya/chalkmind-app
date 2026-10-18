import 'package:flutter/material.dart';

class TextObject {
  final String id;
  final String text;
  final Offset position;
  final double fontSize;
  final int colorValue;
  final bool isBold;
  final bool isItalic;

  const TextObject({
    required this.id,
    required this.text,
    required this.position,
    this.fontSize = 20.0,
    required this.colorValue,
    this.isBold = false,
    this.isItalic = false,
  });

  Color get color => Color(colorValue);

  TextStyle get style => TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        fontFamily: 'Roboto',
      );

  Rect get bounds {
    final textSpan = TextSpan(text: text.isEmpty ? ' ' : text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = 8.0;
    return Rect.fromLTWH(
      position.dx - padding,
      position.dy - padding,
      textPainter.width + (padding * 2),
      textPainter.height + (padding * 2),
    );
  }

  bool hitTest(Offset point) {
    return bounds.contains(point);
  }

  TextObject translate(Offset delta) {
    return TextObject(
      id: id,
      text: text,
      position: position + delta,
      fontSize: fontSize,
      colorValue: colorValue,
      isBold: isBold,
      isItalic: isItalic,
    );
  }

  TextObject copyWith({
    String? id,
    String? text,
    Offset? position,
    double? fontSize,
    int? colorValue,
    bool? isBold,
    bool? isItalic,
  }) {
    return TextObject(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      fontSize: fontSize ?? this.fontSize,
      colorValue: colorValue ?? this.colorValue,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'position': {'dx': position.dx, 'dy': position.dy},
    'fontSize': fontSize,
    'colorValue': colorValue,
    'isBold': isBold,
    'isItalic': isItalic,
  };

  factory TextObject.fromJson(Map<String, dynamic> json) {
    final pos = json['position'] as Map<String, dynamic>;
    return TextObject(
      id: json['id'] as String,
      text: json['text'] as String,
      position: Offset(
        (pos['dx'] as num).toDouble(),
        (pos['dy'] as num).toDouble(),
      ),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 20.0,
      colorValue: json['colorValue'] as int,
      isBold: json['isBold'] as bool? ?? false,
      isItalic: json['isItalic'] as bool? ?? false,
    );
  }
}
