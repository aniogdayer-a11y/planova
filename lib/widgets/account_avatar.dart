import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AccountAvatar extends StatelessWidget {
  final String name, photo;
  final double size;
  const AccountAvatar({
    super.key,
    required this.name,
    this.photo = '',
    this.size = 52,
  });
  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: Text(
        name.trim().isEmpty ? 'P' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: size * .38,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
    Widget content = placeholder;
    if (RegExp(r'^data:image/(jpeg|png|webp);base64,').hasMatch(photo)) {
      try {
        final bytes = base64Decode(photo.split(',')[1]);
        content = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => placeholder,
        );
      } catch (_) {
        /* Keep the initials if a photo cannot be decoded. */
      }
    }
    return Semantics(
      label: '$name profile photo',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: AppColors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: ClipOval(child: content),
      ),
    );
  }
}
