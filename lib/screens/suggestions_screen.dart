import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/feedback_model.dart';
import '../providers/planner_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/page_layout.dart';
import '../widgets/planner_actions.dart';

class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _visibility = 'public';
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(PlannerProvider planner) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await planner.addFeedback(text, visibility: _visibility);
      _controller.clear();
      _focusNode.unfocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post suggestion: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showEditDialog(
    BuildContext context,
    PlannerProvider planner,
    FeedbackModel item,
  ) {
    final editController = TextEditingController(text: item.content);
    String editVisibility = item.visibility;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit suggestion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: editController,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Edit your suggestion...',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Visibility: '),
                  ChoiceChip(
                    label: const Text('Public'),
                    selected: editVisibility == 'public',
                    onSelected: (val) {
                      if (val) setDialogState(() => editVisibility = 'public');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Private'),
                    selected: editVisibility == 'private',
                    onSelected: (val) {
                      if (val) setDialogState(() => editVisibility = 'private');
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newText = editController.text.trim();
                if (newText.isEmpty) return;
                Navigator.pop(ctx);
                await plannerAction(
                  context,
                  () => planner.updateFeedback(
                    item.id,
                    newText,
                    visibility: editVisibility,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    PlannerProvider planner,
    FeedbackModel item,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete suggestion?'),
        content: const Text(
          'Are you sure you want to delete this suggestion? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
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
    final items = planner.feedbackList;

    return PageLayout(
      title: 'Suggestions',
      maxWidth: 760,
      children: [
        // Comment input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: 'Share a suggestion or tip...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _submit(planner),
                ),
              ),
              IconButton(
                icon: Icon(
                  _visibility == 'public'
                      ? Icons.public
                      : Icons.lock_outline,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
                tooltip: _visibility == 'public'
                    ? 'Public (tap for private)'
                    : 'Private (tap for public)',
                onPressed: () {
                  setState(() {
                    _visibility =
                        _visibility == 'public' ? 'private' : 'public';
                  });
                },
              ),
              IconButton(
                key: const ValueKey('submit-suggestion-button'),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                tooltip: 'Post suggestion',
                onPressed: _submitting ? null : () => _submit(planner),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Comments feed
        if (planner.loadingFeedback && items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: Text(
                'No suggestions yet. Share the first tip above!',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          )
        else
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _CommentItem(
              key: ValueKey('comment-${items[index].id}'),
              item: items[index],
              onLike: () => plannerAction(
                context,
                () => planner.toggleFeedbackLike(items[index].id),
              ),
              onEdit: () => _showEditDialog(context, planner, items[index]),
              onDelete: () => _confirmDelete(context, planner, items[index]),
            ),
          ],
      ],
    );
  }
}

class _CommentItem extends StatelessWidget {
  final FeedbackModel item;
  final VoidCallback onLike;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CommentItem({
    super.key,
    required this.item,
    required this.onLike,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              item.authorName.isNotEmpty
                  ? item.authorName[0].toUpperCase()
                  : 'P',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.authorName,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.visibility == 'private') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Private',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                    if (item.isMine) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: onDelete,
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.delete_outline,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
                    item.isLikedByMe
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 20,
                    color: item.isLikedByMe
                        ? const Color(0xFFE05353)
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              if (item.likesCount > 0)
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
