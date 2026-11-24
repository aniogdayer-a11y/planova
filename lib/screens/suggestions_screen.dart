import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/feedback_model.dart';
import '../providers/planner_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/account_avatar.dart';
import '../widgets/page_layout.dart';
import '../widgets/planner_actions.dart';

const _categories = ['General Feedback', 'Feature Suggestion', 'Bug Report'];

class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _category = _categories.first;
  String _recommendation = 'yes';
  bool _sharePublicly = false;
  bool _submitting = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(PlannerProvider planner) async {
    final text = _controller.text.trim();
    if (_submitting) return;
    if (text.isEmpty) {
      setState(() {
        _status = 'Please share a few thoughts before submitting.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _status = null;
    });
    final sharePublicly = _sharePublicly;
    try {
      await planner.addFeedback(
        text,
        category: _category,
        recommendation: _recommendation,
        visibility: sharePublicly ? 'public' : 'private',
      );
      if (!mounted) return;
      _controller.clear();
      _focusNode.unfocus();
      setState(() {
        _sharePublicly = false;
        _status = sharePublicly
            ? 'Your feedback was shared with the community.'
            : 'Your feedback was submitted privately.';
        _statusIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not submit feedback: $error';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    PlannerProvider planner,
    FeedbackModel item,
  ) async {
    final editController = TextEditingController(text: item.content);
    var category = item.category;
    var recommendation = item.recommendation;
    var sharePublicly = item.visibility == 'public';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit feedback'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: editController,
                  maxLines: 5,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Share your thoughts about Planova...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                _CategoryDropdown(
                  value: category,
                  onChanged: (value) => setDialogState(() => category = value),
                ),
                const SizedBox(height: 16),
                const Text('Would you recommend Planova to others?'),
                const SizedBox(height: 4),
                _RecommendationOptions(
                  value: recommendation,
                  onChanged: (value) =>
                      setDialogState(() => recommendation = value),
                ),
                Row(
                  children: [
                    Semantics(
                      label:
                          "I'm willing to share my feedback with other Planova users.",
                      child: Checkbox(
                        value: sharePublicly,
                        onChanged: (value) => setDialogState(
                          () => sharePublicly = value ?? false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "I'm willing to share my feedback with other Planova users.",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = editController.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(dialogContext);
                await plannerAction(
                  context,
                  () => planner.updateFeedback(
                    item.id,
                    text,
                    category: category,
                    recommendation: recommendation,
                    visibility: sharePublicly ? 'public' : 'private',
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    editController.dispose();
  }

  void _confirmDelete(
    BuildContext context,
    PlannerProvider planner,
    FeedbackModel item,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete feedback?'),
        content: const Text(
          'Are you sure you want to delete this feedback? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await plannerAction(
                context,
                () => planner.deleteFeedback(item.id),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final items = planner.feedbackList.where((item) => !item.isSeed).toList();
    final publicItems = items
        .where((item) => item.visibility == 'public')
        .toList();
    final privateItems = items
        .where((item) => item.visibility == 'private' && item.isMine)
        .toList();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = viewportWidth >= 900 ? 64.0 : 40.0;
    final contentWidth = (viewportWidth - horizontalPadding)
        .clamp(0.0, 760.0)
        .toDouble();

    return PageLayout(
      title: 'Feedback',
      subtitle: 'Help us improve Planova.',
      maxWidth: 760,
      children: [
        SizedBox(
          width: contentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.borderMedium),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Share your feedback',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        hintText: 'Share your thoughts about Planova...',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _CategoryDropdown(
                      value: _category,
                      onChanged: (value) => setState(() => _category = value),
                    ),
                    const SizedBox(height: 16),
                    const Text('Would you recommend Planova to others?'),
                    const SizedBox(height: 4),
                    _RecommendationOptions(
                      value: _recommendation,
                      onChanged: (value) =>
                          setState(() => _recommendation = value),
                    ),
                    Row(
                      children: [
                        Semantics(
                          label:
                              "I'm willing to share my feedback with other Planova users.",
                          child: Checkbox(
                            value: _sharePublicly,
                            onChanged: (value) => setState(
                              () => _sharePublicly = value ?? false,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "I'm willing to share my feedback with other Planova users.",
                          ),
                        ),
                      ],
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _status!,
                        style: TextStyle(
                          color: _statusIsError
                              ? const Color(0xFF9B3932)
                              : AppColors.successText,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        key: const ValueKey('submit-suggestion-button'),
                        onPressed: _submitting ? null : () => _submit(planner),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Submit Feedback'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Community Feedback',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (planner.loadingFeedback && items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (planner.feedbackError != null && items.isEmpty)
                _FeedbackMessage(
                  message: 'Community feedback could not be loaded.',
                  action: TextButton(
                    onPressed: planner.loadFeedback,
                    child: const Text('Try again'),
                  ),
                )
              else if (publicItems.isEmpty)
                const _FeedbackMessage(
                  message: 'No community feedback yet. Be the first to share.',
                )
              else
                for (var index = 0; index < publicItems.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _CommentItem(
                    key: ValueKey('comment-${publicItems[index].id}'),
                    item: publicItems[index],
                    onLike: () => plannerAction(
                      context,
                      () => planner.toggleFeedbackLike(publicItems[index].id),
                    ),
                    onEdit: () =>
                        _showEditDialog(context, planner, publicItems[index]),
                    onDelete: () =>
                        _confirmDelete(context, planner, publicItems[index]),
                  ),
                ],
              if (privateItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Your Private Feedback',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (var index = 0; index < privateItems.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _CommentItem(
                    key: ValueKey('private-feedback-${privateItems[index].id}'),
                    item: privateItems[index],
                    allowLike: false,
                    onLike: () {},
                    onEdit: () =>
                        _showEditDialog(context, planner, privateItems[index]),
                    onDelete: () =>
                        _confirmDelete(context, planner, privateItems[index]),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CategoryDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value,
    decoration: const InputDecoration(labelText: 'Feedback category'),
    isExpanded: true,
    items: _categories
        .map(
          (category) =>
              DropdownMenuItem(value: category, child: Text(category)),
        )
        .toList(),
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}

class _RecommendationOptions extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _RecommendationOptions({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    children: [
      for (final option in const {
        'yes': 'Yes',
        'maybe': 'Maybe',
        'no': 'No',
      }.entries)
        InkWell(
          onTap: () => onChanged(option.key),
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Radio<String>(
                value: option.key,
                groupValue: value,
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
                visualDensity: VisualDensity.compact,
              ),
              Text(option.value),
            ],
          ),
        ),
    ],
  );
}

class _FeedbackMessage extends StatelessWidget {
  final String message;
  final Widget? action;

  const _FeedbackMessage({required this.message, this.action});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textTertiary),
          ),
          if (action != null) action!,
        ],
      ),
    ),
  );
}

class _CommentItem extends StatelessWidget {
  final FeedbackModel item;
  final VoidCallback onLike;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool allowLike;

  const _CommentItem({
    super.key,
    required this.item,
    required this.onLike,
    required this.onEdit,
    required this.onDelete,
    this.allowLike = true,
  });

  @override
  Widget build(BuildContext context) {
    final isPrivate = item.visibility == 'private';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountAvatar(
            name: item.authorName,
            photo: item.authorAvatar,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 7,
                  runSpacing: 4,
                  children: [
                    Text(
                      item.authorName,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '· ${item.category}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      DateFormat('MMM d, yyyy').format(item.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    if (isPrivate)
                      const Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                    if (item.isMine) ...[
                      IconButton(
                        tooltip: 'Edit feedback',
                        visualDensity: VisualDensity.compact,
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                      ),
                      IconButton(
                        tooltip: 'Delete feedback',
                        visualDensity: VisualDensity.compact,
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline, size: 16),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (allowLike)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  toggled: item.isLikedByMe,
                  child: IconButton(
                    key: ValueKey('like-${item.id}'),
                    tooltip: item.isLikedByMe ? 'Unlike' : 'Like',
                    onPressed: onLike,
                    icon: Icon(
                      item.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                      size: 20,
                      color: item.isLikedByMe
                          ? const Color(0xFFE05353)
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                Text(
                  '${item.likesCount}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: item.isLikedByMe
                        ? const Color(0xFFE05353)
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
