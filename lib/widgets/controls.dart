import 'package:button_display_latency/core/logging.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'button_factory.dart';
import 'button_types.dart';

class ButtonTypeDropdown extends StatelessWidget {
  const ButtonTypeDropdown({super.key});

  static const List<String> buttonTypes = [
    'GestureDetectorTapButton',
    'GestureDetectorTapDownButton',
    'RawGestureDetectorTapButton',
    'GestureDetectorPanDownButton',
    'ListenerPointerDownButton',
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
              PerformanceLogger.buttonType = newType;
            }
          },
        );
      },
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
