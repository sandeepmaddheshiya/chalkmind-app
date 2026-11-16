import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/backend.dart';

/// Chalkmind brand colours (logo, website) used by the account screens on
/// top of the app's Material theme.
class AccountColors {
  AccountColors._();
  static const board = Color(0xFF0B3B35);
  static const board2 = Color(0xFF0F766E);
  static const chalk = Color(0xFFF8FAFC);
  static const chalkDim = Color(0xFFC9DDD6);
  static const yellow = Color(0xFFFACC15);
  static const onYellow = Color(0xFF14201D);

  static Color border(bool dark) =>
      dark ? const Color(0xFF262A34) : const Color(0xFFE2E0D9);
  static Color panel(bool dark) =>
      dark ? const Color(0xFF181B22) : Colors.white;

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [board, Color(0xFF105E50)],
  );
}

/// The multi-colour Google "G", drawn so no image asset is needed.
class GoogleGMark extends StatelessWidget {
  final double size;
  const GoogleGMark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GPainter());
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final w = s * 0.2;
    final rect = Rect.fromLTWH(w / 2, w / 2, s - w, s - w);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    double rad(double d) => d * math.pi / 180;
    // Clockwise from the bar: blue, green, yellow, red; gap at upper right.
    canvas.drawArc(rect, rad(0), rad(45), false, p(const Color(0xFF4285F4)));
    canvas.drawArc(rect, rad(45), rad(105), false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, rad(150), rad(65), false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, rad(215), rad(100), false, p(const Color(0xFFEA4335)));
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - w / 2, s / 2 - w * 0.05, w),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Remembers that the user accepted the Terms and Privacy Policy.
class LegalConsent {
  LegalConsent._();
  static const _key = 'legal.accepted.v1';

  static Future<bool> accepted() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAccepted(bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, v);
    } catch (_) {}
  }
}

/// "I agree to the Terms of use and Privacy policy" with tappable links.
class AgreementCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final void Function(String url) onOpen;
  final Color? textColor;
  final Color? linkColor;

  const AgreementCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onOpen,
    this.textColor,
    this.linkColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = textColor ?? theme.colorScheme.onSurfaceVariant;
    final link = linkColor ?? theme.colorScheme.primary;
    TextSpan linkSpan(String label, String url) => TextSpan(
      text: label,
      style: TextStyle(
        color: link,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
        decorationColor: link,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => onOpen(url),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: link,
              side: BorderSide(color: text, width: 1.5),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: text, fontSize: 13.5, height: 1.4),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    linkSpan('Terms of use', BackendConfig.termsUrl),
                    const TextSpan(text: ' and '),
                    linkSpan('Privacy policy', BackendConfig.privacyUrl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White "Continue with Google" button (Google's sign-in button style).
class GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;
  const GoogleButton({super.key, required this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.55),
          disabledForegroundColor: const Color(
            0xFF1F1F1F,
          ).withValues(alpha: 0.45),
          elevation: enabled ? 1 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFDADCE0)),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              Opacity(
                opacity: enabled ? 1 : 0.5,
                child: const GoogleGMark(size: 20),
              ),
            const SizedBox(width: 12),
            Text(
              busy ? 'Signing in…' : 'Continue with Google',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
