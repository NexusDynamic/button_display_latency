import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/timing_config.dart';
import '../core/timing_session.dart';
import 'button_factory.dart';
import 'button_types.dart';

class ButtonTypeDropdown extends StatelessWidget {
  const ButtonTypeDropdown({super.key});

  /// Ordered fastest-first: the raw packet hook, then the framework listener,
  /// then the gesture recognisers.
  static const List<String> buttonTypes = [
    'RawPointerDownButton',
    'ListenerPointerDownButton',
    'GestureDetectorPanDownButton',
    'GestureDetectorTapDownButton',
    'RawGestureDetectorTapButton',
    'GestureDetectorTapButton',
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<BaseButton>(
      builder: (context, currentButton, _) {
        final buttonService = context.read<ButtonService>();
        String currentType = currentButton.runtimeType.toString();

        return DropdownButton<String>(
          value: buttonTypes.contains(currentType)
              ? currentType
              : buttonTypes.first,
          items: buttonTypes.map((String type) {
            return DropdownMenuItem<String>(
              value: type,
              child: Text('buttonTypes.$type'.tr()),
            );
          }).toList(),
          onChanged: (String? newType) {
            if (newType != null) {
              final newButton = StaticButtonFactory.createButton(type: newType);
              buttonService.updateButton(newButton);
            }
          },
        );
      },
    );
  }
}

/// Bela protocol controls: the photodiode patch, the frame-rate pin and the
/// optional LSL outlet.
class BelaControls extends StatefulWidget {
  const BelaControls({super.key});

  @override
  State<BelaControls> createState() => _BelaControlsState();
}

class _BelaControlsState extends State<BelaControls> {
  final TimingSession _session = TimingSession.instance;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // Polled rather than driven by the session, so that opening a trial never
    // dirties a widget in the frame the flash has to land in.
    _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hz = _session.refreshHz;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 4,
          children: [
            _Toggle(
              label: 'bela.mode'.tr(),
              value: _session.belaMode,
              onChanged: (value) async {
                await _session.setBelaMode(value);
                if (mounted) setState(() {});
              },
            ),
            _Toggle(
              label: 'bela.lsl'.tr(),
              value: _session.lslRequested,
              onChanged: (value) async {
                await _session.setLslEnabled(value);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            'trial ${_session.trial}',
            if (_session.rejectedTouches > 0)
              'rejected ${_session.rejectedTouches}',
            hz == null ? 'refresh ?' : '${hz.toStringAsFixed(0)} Hz',
            if (_session.lastDispatchSeconds != null)
              'os→dart ${(_session.lastDispatchSeconds! * 1000).toStringAsFixed(2)} ms',
            if (_session.lslRunning)
              _session.lsl.hasConsumers
                  ? 'lsl: consumer attached'
                  : 'lsl: waiting for Bela'
            else
              'lsl: off',
            if (_session.lsl.pushErrors > 0)
              'push errors ${_session.lsl.pushErrors}',
          ].join('  ·  '),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        Text(
          '${TimingConfig.streamName} / ${TimingConfig.sourceId}',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class LoggingControls extends StatelessWidget {
  const LoggingControls({super.key});

  Future<void> _shareFiles(
    String logs,
    String description,
    BuildContext context,
  ) async {
    final Size windowSize = MediaQueryData.fromView(View.of(context)).size;
    final params = ShareParams(
      subject: 'Exported $description',
      text: logs,
      sharePositionOrigin: Rect.fromLTWH(
        windowSize.width / 2 - 100,
        windowSize.height - 200,
        200,
        100,
      ),
    );
    // await until dialog is closed
    await SharePlus.instance.share(params);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton(
          onPressed: () => StaticButtonFactory.clearLogs(),
          child: Text('buttons.clearLogs'.tr()),
        ),
        ElevatedButton(
          onPressed: () => StaticButtonFactory.generateSyncPulse(),
          child: Text('buttons.syncPulse'.tr()),
        ),
        ElevatedButton(
          onPressed: () => StaticButtonFactory.startSyncPulse(),
          child: Text('buttons.startSync'.tr()),
        ),
        ElevatedButton(
          onPressed: () => StaticButtonFactory.stopSyncPulse(),
          child: Text('buttons.stopSync'.tr()),
        ),
        ElevatedButton(
          onPressed: () {
            final logs = StaticButtonFactory.exportLogs();
            if (kDebugMode) {
              print('console.exportedLogsHeader'.tr());
              print(logs);
              print('console.exportedLogsFooter'.tr());
            }
            _shareFiles(logs, 'logs', context);
          },
          child: Text('buttons.exportLogs'.tr()),
        ),
      ],
    );
  }
}
