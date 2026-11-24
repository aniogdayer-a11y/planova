import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'planova_brand.dart';
import 'account_avatar.dart';

const _labels = ['Home', 'Tasks', 'Suggestions', 'Profile', 'Settings'];
const _selectedIcons = [
  Icons.home_rounded,
  Icons.checklist_rounded,
  Icons.lightbulb,
  Icons.person,
  Icons.settings,
];
const _icons = [
  Icons.home_outlined,
  Icons.checklist_rounded,
  Icons.lightbulb_outline,
  Icons.person_outline,
  Icons.settings_outlined,
];

class PlanovaNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double maxWidth;
  const PlanovaNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.maxWidth = double.infinity,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            key: const ValueKey('planova-pill-navigation-v2'),
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(40),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: List.generate(_labels.length, (index) {
                  final selected = selectedIndex == index;
                  return Expanded(
                    flex: selected ? 3 : 1,
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: _labels[index],
                      child: Tooltip(
                        message: _labels[index],
                        excludeFromSemantics: true,
                        child: InkWell(
                          key: ValueKey('planova-tab-$index'),
                          onTap: () => onSelected(index),
                          borderRadius: BorderRadius.circular(30),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            constraints: const BoxConstraints(minHeight: 50),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    selected
                                        ? _selectedIcons[index]
                                        : _icons[index],
                                    size: 23,
                                    color: selected
                                        ? AppColors.ink
                                        : const Color(0xFFB5B1C2),
                                  ),
                                  if (selected) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _labels[index],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PlanovaWebHeader extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String name;
  final String photo;
  final VoidCallback? onLogout;
  const PlanovaWebHeader({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.name,
    this.photo = '',
    this.onLogout,
  });

  List<Widget> _actions() => [
    if (onLogout != null)
      IconButton(
        tooltip: 'Sign out',
        onPressed: onLogout,
        icon: const Icon(Icons.logout, color: AppColors.cream, size: 20),
      ),
  ];

  Widget _tab(int index, {bool compact = false}) {
    final selected = index == selectedIndex;
    return Expanded(
      child: TextButton(
        onPressed: () => onSelected(index),
        style: TextButton.styleFrom(
          backgroundColor: selected ? AppColors.charcoal : Colors.transparent,
          foregroundColor: selected ? AppColors.cream : AppColors.charcoal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        ),
        child: Text(
          _labels[index],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, letterSpacing: compact ? 0 : 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('planova-web-header'),
    color: AppColors.charcoal,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                if (!wide) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: PlanovaBrand(inverse: true),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AccountAvatar(name: name, photo: photo, size: 30),
                          ..._actions(),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _Ribbon(
                        child: Row(
                          children: List.generate(
                            5,
                            (i) => _tab(i, compact: true),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          const Spacer(),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.cream,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AccountAvatar(name: name, photo: photo, size: 30),
                          ..._actions(),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _Ribbon(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(children: [_tab(0), _tab(1)]),
                                ),
                                const SizedBox(width: 196),
                                Expanded(
                                  child: Row(
                                    children: [_tab(2), _tab(3), _tab(4)],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const _PlanovaBadge(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class _Ribbon extends StatelessWidget {
  final Widget child;
  const _Ribbon({required this.child});
  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: const _RibbonClipper(),
    child: Container(
      decoration: const BoxDecoration(color: AppColors.cream),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Container(
        decoration: const BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: AppColors.taupe),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    ),
  );
}

class _PlanovaBadge extends StatelessWidget {
  const _PlanovaBadge();
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('planova-web-badge-v2'),
    width: 174,
    height: 112,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: AppColors.charcoal,
      border: Border.all(color: AppColors.taupe, width: 3),
      borderRadius: BorderRadius.circular(36),
    ),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cream),
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.near_me_outlined, color: AppColors.cream, size: 20),
          SizedBox(height: 4),
          Text(
            'Planova',
            style: TextStyle(
              color: AppColors.cream,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RibbonClipper extends CustomClipper<Path> {
  const _RibbonClipper();
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width - 12, size.height / 2)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..lineTo(12, size.height / 2)
    ..close();
  @override
  bool shouldReclip(_RibbonClipper oldClipper) => false;
}
