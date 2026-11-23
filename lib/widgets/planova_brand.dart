import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PlanovaBrand extends StatelessWidget {
  final bool inverse;
  final bool large;
  const PlanovaBrand({super.key, this.inverse = false, this.large = false});
  @override
  Widget build(BuildContext context) {
    final color = inverse ? AppColors.cream : AppColors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(large ? 14 : 7),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: .65)),
            borderRadius: BorderRadius.circular(
              large
                  ? 12
                  : kIsWeb
                  ? 4
                  : 12,
            ),
          ),
          child: Icon(
            Icons.near_me_outlined,
            color: color,
            size: large ? 40 : 21,
          ),
        ),
        SizedBox(width: large ? 20 : 10),
        Text(
          'Planova',
          style: TextStyle(
            fontSize: large ? 52 : 24,
            fontWeight: FontWeight.w600,
            letterSpacing: kIsWeb ? 1.2 : -.5,
            color: color,
          ),
        ),
      ],
    );
  }
}
