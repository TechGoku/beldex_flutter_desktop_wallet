import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/daemon_service.dart';
import '../../state/app_controller.dart';
import '../kit.dart';
import '../theme.dart';
import 'settings/settings_screen.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  static const _stages = [
    StartupStage.loadingConfig,
    StartupStage.startingDaemon,
    StartupStage.startingWallet,
    StartupStage.readingWallets,
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final daemonHeight = context.select<DaemonService, int>((d) => d.info.height);
    final target = context.select<DaemonService, int>((d) => d.info.targetHeight);

    final message = switch (app.stage) {
      StartupStage.loadingConfig => 'Loading settings',
      StartupStage.startingDaemon =>
        app.config.daemon.runsLocally ? 'Starting your node' : 'Connecting to ${app.config.daemon.remoteHost}',
      StartupStage.startingWallet => 'Starting wallet service',
      StartupStage.readingWallets => 'Reading wallets',
      StartupStage.quitting => 'Closing securely',
      _ => 'Connecting',
    };
    final step = _stages.indexOf(app.stage);

    return BScaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(large: true),
              const SizedBox(height: 36),
              if (app.stage == StartupStage.failed) ...[
                const FailMark(),
                const SizedBox(height: 14),
                Text(
                  app.failure ?? 'Something went wrong',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        'Settings',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen(startupMode: true)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: PrimaryButton('Retry', onPressed: () => app.saveConfigAndStart(app.config))),
                  ],
                ),
              ] else ...[
                Text(
                  message.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: BeldexFonts.display,
                    fontSize: 12,
                    letterSpacing: 2,
                    color: BeldexColors.muted,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(width: 260, child: GlowProgress(step < 0 ? 0.1 : (step + 1) / (_stages.length + 1))),
                if (app.stage == StartupStage.startingDaemon &&
                    app.config.daemon.runsLocally &&
                    target > daemonHeight) ...[
                  const SizedBox(height: 12),
                  Muted('Node syncing $daemonHeight / $target', size: 11),
                ],
                if (app.daemonVersion != null) ...[const SizedBox(height: 12), Muted(app.daemonVersion!, size: 10)],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
