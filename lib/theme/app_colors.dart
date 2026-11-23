import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class AppColors {
  static const charcoal = Color(0xFF383A38);
  static const cream = Color(0xFFEDEBD5);
  static const taupe = Color(0xFFA79E8E);
  static const ink = Color(0xFF171523);
  static const lavender = Color(0xFFEEE5F7);
  static const background = kIsWeb ? Color(0xFFF0EEDF) : Color(0xFFF8F7FA);
  static const surface = kIsWeb ? Color(0xFFFFFDF3) : Colors.white;
  static const surfaceWarm = kIsWeb ? cream : lavender;
  static const surfaceSubtle = kIsWeb ? Color(0xFFE7E4D5) : Color(0xFFF1EFF5);
  static const primary = kIsWeb ? charcoal : ink;
  static const primaryDark = Color(0xFF252724);
  static const primaryLight = Color(0xFF64675F);
  static const primaryContainer = kIsWeb ? Color(0xFFE1DDC7) : lavender;
  static const textPrimary = Color(0xFF2D302D);
  static const textSecondary = Color(0xFF62645C);
  static const textTertiary = Color(0xFF74766C);
  static const textInverse = cream;
  static const border = kIsWeb ? Color(0xFFD7D3C1) : Color(0xFFE5E2EB);
  static const borderMedium = taupe;
  static const divider = border;
  static const breakBadgeBg = kIsWeb ? Color(0xFFE5E2D1) : lavender;
  static const breakBadgeText = Color(0xFF5D5E52);
  static const successBg = Color(0xFFEBF1E9);
  static const successText = Color(0xFF456241);
  static const accentPeach = primaryContainer;
  static const accentAmber = primary;
}
