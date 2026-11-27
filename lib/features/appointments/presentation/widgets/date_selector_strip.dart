import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/date_formatters.dart';

/// Expressive horizontal date strip modeled after Pixel Calendar.
class DateSelectorStrip extends StatelessWidget {
  const DateSelectorStrip({
    super.key,
    required this.selectedDate,
    required this.markedDates,
    required this.onDateSelected,
  });

  final DateTime selectedDate;
  final Set<DateTime> markedDates;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final today = DateFormatters.startOfDay(DateTime.now());
    final selectedStart = DateFormatters.startOfDay(selectedDate);
    final isTodaySelected = DateFormatters.isSameDay(selectedStart, today);

    // 7-day window anchored 2 days before selectedDate for smooth browsing.
    final windowStart = DateTime(
      selectedStart.year,
      selectedStart.month,
      selectedStart.day - 2,
    );
    final days = List<DateTime>.generate(
      7,
      (int i) =>
          DateTime(windowStart.year, windowStart.month, windowStart.day + i),
      growable: false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormatters.formatMonthYear(selectedStart),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isTodaySelected)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ActionChip(
                    label: const Text('Hoy'),
                    avatar: const Icon(Icons.today_rounded, size: 16),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onDateSelected(today);
                    },
                  ),
                ),
              IconButton(
                tooltip: 'Elegir fecha',
                onPressed: () => _pickDate(context, selectedStart),
                icon: const Icon(Icons.calendar_month_rounded),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final day = days[index];
              final isSelected = DateFormatters.isSameDay(day, selectedStart);
              final isToday = DateFormatters.isSameDay(day, today);
              final hasEvents = markedDates.contains(day);

              final backgroundColor = isSelected
                  ? colorScheme.primaryContainer
                  : (isToday
                        ? colorScheme.surfaceContainerHigh
                        : colorScheme.surfaceContainerLow);
              final foregroundColor = isSelected
                  ? colorScheme.onPrimaryContainer
                  : (isToday ? colorScheme.primary : colorScheme.onSurface);

              return Material(
                color: backgroundColor,
                borderRadius: PixelShapes.cardBorderRadius,
                child: InkWell(
                  borderRadius: PixelShapes.cardBorderRadius,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onDateSelected(day);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 56,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: PixelShapes.cardBorderRadius,
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary.withValues(alpha: 0.45)
                            : colorScheme.outlineVariant.withValues(alpha: 0.4),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormatters.formatWeekdayShort(day),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foregroundColor.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormatters.formatDayNumber(day),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foregroundColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasEvents
                                ? (isSelected
                                      ? colorScheme.primary
                                      : colorScheme.tertiary)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, DateTime current) async {
    HapticFeedback.lightImpact();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime(current.year + 3),
    );
    if (picked != null) {
      HapticFeedback.lightImpact();
      onDateSelected(DateFormatters.startOfDay(picked));
    }
  }
}
