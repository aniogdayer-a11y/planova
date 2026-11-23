import 'package:flutter/material.dart';

// Kept for callers that still wrap the app. Screen layout is now responsive.
class PhoneFrameWrapper extends StatelessWidget {
  final Widget child;
  const PhoneFrameWrapper({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}
