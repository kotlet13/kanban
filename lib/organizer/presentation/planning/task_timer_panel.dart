import 'dart:async';
import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../domain/organizer_models.dart';

String planningDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  return '$hours:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

class TaskTimerPanel extends StatefulWidget {
  const TaskTimerPanel({
    super.key,
    required this.timer,
    this.estimateMinutes,
    this.onToggle,
    this.showControls = true,
    this.clock = DateTime.now,
  });
  final TaskTimerState timer;
  final int? estimateMinutes;
  final Future<void> Function()? onToggle;
  final bool showControls;
  final DateTime Function() clock;
  @override
  State<TaskTimerPanel> createState() => _TaskTimerPanelState();
}

class _TaskTimerPanelState extends State<TaskTimerPanel> {
  Timer? _ticker;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _scheduleTicker();
  }

  @override
  void didUpdateWidget(TaskTimerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timer.running != widget.timer.running) _scheduleTicker();
  }

  void _scheduleTicker() {
    _ticker?.cancel();
    _ticker = widget.timer.running
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, now = widget.clock();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${l.planningElapsed}: ${planningDuration(widget.timer.elapsedAt(now))}',
          ),
          if (widget.estimateMinutes != null)
            Text(
              '${l.planningRemaining}: ${planningDuration(widget.timer.remainingAt(widget.estimateMinutes, now))}',
            ),
          if (widget.showControls)
            OutlinedButton.icon(
              key: const ValueKey('task-timer-toggle'),
              onPressed: _busy || widget.onToggle == null
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await widget.onToggle!();
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              icon: Icon(widget.timer.running ? Icons.pause : Icons.play_arrow),
              label: Text(
                widget.timer.running
                    ? l.planningTimerPause
                    : l.planningTimerStart,
              ),
            ),
        ],
      ),
    );
  }
}
