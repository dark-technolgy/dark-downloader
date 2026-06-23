import 'package:flutter/material.dart';

/// A horizontally scrollable row of filter chips.
///
/// Designed for the quality picker but reusable for any `single-select +
/// (All)` filter surface. When [value] is empty the "All" chip is selected.
///
/// - [options]: ordered list of option values the user can pick. Use raw
///   values (e.g. `"1080p"`, `"MP4"`) — the label builder is separate so
///   callers can localise.
/// - [value]: currently selected option, or an empty string to mean "All".
/// - [onChanged]: called with the new selection. Empty string means "All".
/// - [labelFor]: maps an option value to its display label. Defaults to
///   returning the option itself.
/// - [allLabel]: label for the "All" chip.
/// - [title]: optional leading caption shown above the chips.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.allLabel,
    this.title,
    this.labelFor,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String allLabel;
  final String? title;
  final String Function(String option)? labelFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = labelFor ?? (s) => s;
    final disabled = options.isEmpty;

    final chips = <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: FilterChip(
          label: Text(allLabel),
          selected: value.isEmpty,
          onSelected: disabled ? null : (_) => onChanged(''),
        ),
      ),
      for (final opt in options)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FilterChip(
            label: Text(label(opt)),
            selected: value == opt,
            onSelected: disabled ? null : (sel) => onChanged(sel ? opt : ''),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title!.isNotEmpty) ...[
          Text(
            title!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            children: chips,
          ),
        ),
      ],
    );
  }
}
