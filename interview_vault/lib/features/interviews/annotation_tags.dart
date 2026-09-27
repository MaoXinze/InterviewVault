import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';
import '../../core/theme.dart';

/// PRD 2.5 标签体系：5 个系统标签 + 用户自定义。
/// annotations.tag 存英文键（PRD 3.3 DDL：question/answer/highlight/mistake/
/// improvement/custom），自定义标签再带 customTagName 存展示名。
const systemTagOrder = [
  'question',
  'answer',
  'highlight',
  'mistake',
  'improvement',
];

const systemTagLabels = <String, String>{
  'question': '问题',
  'answer': '回答',
  'highlight': '亮点',
  'mistake': '失误',
  'improvement': '待改进',
};

String systemTagLabel(String tag) => systemTagLabels[tag] ?? tag;

/// 标注行的展示名：系统标签查表，自定义标签用 customTagName
String annotationLabel(Annotation a) =>
    a.tag == 'custom' ? (a.customTagName ?? '自定义') : systemTagLabel(a.tag);

/// 筛选键：系统标签直接用 tag 键；自定义标签加 'custom:' 前缀
String annotationFilterKey(Annotation a) =>
    a.tag == 'custom' ? 'custom:${a.customTagName ?? ''}' : a.tag;

/// 一组标注的筛选键排序：系统标签按固定顺序在前，自定义按名称
List<String> sortedFilterKeys(Iterable<Annotation> annotations) {
  final keys = annotations.map(annotationFilterKey).toSet().toList();
  keys.sort((a, b) {
    final ai = systemTagOrder.indexOf(a);
    final bi = systemTagOrder.indexOf(b);
    if (ai != bi) {
      return (ai == -1 ? systemTagOrder.length : ai) -
          (bi == -1 ? systemTagOrder.length : bi);
    }
    return a.compareTo(b);
  });
  return keys;
}

/// 系统标签配色（暗色优先）；自定义标签走 scheme.tertiary
Color annotationTagColor(BuildContext context, String filterKey) {
  final scheme = Theme.of(context).colorScheme;
  return switch (filterKey) {
    'question' => const Color(0xFF64B5F6),
    'answer' => const Color(0xFF66BB6A),
    'highlight' => AppTheme.gold,
    'mistake' => scheme.error,
    'improvement' => const Color(0xFFE8933A),
    _ => scheme.tertiary,
  };
}

String filterKeyLabel(String filterKey) => filterKey.startsWith('custom:')
    ? filterKey.substring('custom:'.length)
    : systemTagLabel(filterKey);

/// 标签 chip：弹层选择、逐字稿标注行、筛选条共用
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    required this.filterKey,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final String filterKey;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = annotationTagColor(context, filterKey);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? color.withValues(alpha: 0.18) : null,
          border: Border.all(
            color: color.withValues(alpha: selected ? 0.9 : 0.45),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
      ),
    );
  }
}
