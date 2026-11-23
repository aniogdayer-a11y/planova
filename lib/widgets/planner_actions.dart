import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../services/api_client.dart';

Future<bool> plannerAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (context.mounted) {
      final message = error is ApiException
          ? error.message
          : error is GeminiException
          ? error.message
          : error is FormatException
          ? error.message
          : 'Could not save your changes. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    return false;
  }
}
