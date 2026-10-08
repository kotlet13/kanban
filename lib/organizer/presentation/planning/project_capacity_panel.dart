import 'dart:async';
import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';
import '../../domain/project_capacity.dart';
import 'task_timer_panel.dart';

class ProjectCapacityPanel extends StatefulWidget {
  const ProjectCapacityPanel({
    super.key,
    required this.project,
    required this.tasks,
    this.phaseId,
    this.clock = DateTime.now,
  });
  final LocalProject project;
  final List<LocalTask> tasks;
  final String? phaseId;
  final DateTime Function() clock;
  @override
  State<ProjectCapacityPanel> createState() => _ProjectCapacityPanelState();
}

class _ProjectCapacityPanelState extends State<ProjectCapacityPanel> {
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ProjectCapacityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    _ticker?.cancel();
    if (widget.tasks.any((task) => task.timer.running && !task.isCompleted)) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final estimate = estimateProjectCapacity(
      widget.project,
      widget.tasks,
      phaseId: widget.phaseId,
      now: widget.clock(),
    );
    final days = estimate.estimatedDays;
    final rounded = days == null ? null : (days * 10).ceil() / 10;
    final rawDayText = rounded?.toStringAsFixed(
      rounded == rounded.roundToDouble() ? 0 : 1,
    );
    final dayText = Localizations.localeOf(context).languageCode == 'sl'
        ? rawDayText?.replaceAll('.', ',')
        : rawDayText;
    return Padding(
      key: ValueKey('capacity-${widget.phaseId ?? widget.project.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.planningCapacityTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (estimate.taskCount == 0)
            Text(l.planningCapacityNoTasks)
          else if (estimate.openTaskCount == 0)
            Text(l.planningCapacityComplete)
          else ...[
            if (estimate.missingEstimates == 0)
              Text(
                '${l.planningRemaining}: ${planningDuration(estimate.remainingSeconds)}',
              ),
            if (dayText != null) Text(l.planningCapacityDuration(dayText)),
            if (estimate.missingEstimates > 0)
              Text(
                l.planningCapacityMissingEstimates(estimate.missingEstimates),
              ),
            if (estimate.missingAvailability > 0)
              Text(
                l.planningCapacityMissingAvailability(
                  estimate.missingAvailability,
                ),
              ),
          ],
          if (widget.phaseId == null) ...[
            const SizedBox(height: 4),
            Text(
              l.planningCapacityRule,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
