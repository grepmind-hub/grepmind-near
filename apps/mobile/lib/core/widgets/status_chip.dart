import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Verification / open-status badge chip.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.type = StatusChipType.info,
    this.size = StatusChipSize.small,
  });

  final String label;
  final StatusChipType type;
  final StatusChipSize size;

  Color get _bg {
    switch (type) {
      case StatusChipType.success:
        return AppTheme.successContainer;
      case StatusChipType.warning:
        return AppTheme.warningContainer;
      case StatusChipType.error:
        return AppTheme.errorContainer;
      case StatusChipType.info:
        return AppTheme.surfaceVariant;
    }
  }

  Color get _fg {
    switch (type) {
      case StatusChipType.success:
        return AppTheme.success;
      case StatusChipType.warning:
        return AppTheme.warning;
      case StatusChipType.error:
        return AppTheme.error;
      case StatusChipType.info:
        return AppTheme.secondaryText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = size == StatusChipSize.small
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    return Container(
      padding: pad,
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _fg,
              fontWeight: FontWeight.w600,
              fontSize: size == StatusChipSize.small ? 10 : 11,
            ),
      ),
    );
  }
}

enum StatusChipType { info, success, warning, error }
enum StatusChipSize { small, medium }
