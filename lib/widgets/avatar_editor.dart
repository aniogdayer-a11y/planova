import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class AvatarEditor extends StatefulWidget {
  final String name;
  const AvatarEditor({super.key, required this.name});

  @override
  State<AvatarEditor> createState() => _AvatarEditorState();
}

class _AvatarEditorState extends State<AvatarEditor> {
  static const _colors = <(String, Color)>[
    ('Charcoal', Color(0xFF343735)),
    ('Lavender', Color(0xFF685184)),
    ('Forest', Color(0xFF3F6457)),
    ('Blue', Color(0xFF3F627A)),
    ('Rose', Color(0xFF995A63)),
    ('Terracotta', Color(0xFF98563B)),
  ];
  static const _styles = <(String, IconData?)>[
    ('Initials', null),
    ('Smile', Icons.sentiment_satisfied_alt),
    ('Paw', Icons.pets),
    ('Flower', Icons.local_florist_outlined),
    ('Star', Icons.star_outline),
    ('Person', Icons.person_outline),
  ];
  final _preview = GlobalKey();
  late final TextEditingController _initials;
  int _color = 0, _style = 0;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final parts = widget.name.trim().split(RegExp(r'\s+'));
    _initials = TextEditingController(
      text: parts
          .where((p) => p.isNotEmpty)
          .take(2)
          .map((p) => p.characters.first)
          .join()
          .toUpperCase(),
    );
  }

  @override
  void dispose() {
    _initials.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_style == 0 && _initials.text.trim().isEmpty) {
      setState(() => _error = 'Enter your initials.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _preview.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Could not export avatar.');
        if (mounted) {
          Navigator.pop<Uint8List>(context, data.buffer.asUint8List());
        }
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save avatar. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Customize avatar'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: AbsorbPointer(
          absorbing: _saving,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: RepaintBoundary(
                  key: _preview,
                  child: Container(
                    key: const ValueKey('avatar-preview'),
                    width: 128,
                    height: 128,
                    color: _colors[_color].$2,
                    alignment: Alignment.center,
                    child: _style == 0
                        ? Text(
                            _initials.text.trim().toUpperCase(),
                            style: const TextStyle(
                              fontSize: 46,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            textScaler: TextScaler.noScaling,
                          )
                        : Icon(
                            _styles[_style].$2,
                            size: 72,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: List.generate(
                  _styles.length,
                  (index) => ChoiceChip(
                    label: Text(_styles[index].$1),
                    selected: _style == index,
                    onSelected: (_) => setState(() {
                      _style = index;
                      _error = null;
                    }),
                  ),
                ),
              ),
              if (_style == 0) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('avatar-initials'),
                  controller: _initials,
                  maxLength: 2,
                  inputFormatters: [LengthLimitingTextInputFormatter(2)],
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Initials',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: List.generate(
                  _colors.length,
                  (index) => Semantics(
                    selected: _color == index,
                    child: IconButton(
                      tooltip: _colors[index].$1,
                      style: IconButton.styleFrom(
                        backgroundColor: _colors[index].$2,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(
                        _color == index ? Icons.check : Icons.circle_outlined,
                      ),
                      onPressed: () => setState(() => _color = index),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving...' : 'Save avatar'),
      ),
    ],
  );
}
