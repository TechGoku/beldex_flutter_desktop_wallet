import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/format.dart';
import '../../../services/models.dart';
import '../../../services/wallet_service.dart';
import '../../kit.dart';
import '../../theme.dart';
import '../../widgets/common.dart' show errorText, showSnack;

class ReceiveView extends StatefulWidget {
  const ReceiveView({super.key});
  @override
  State<ReceiveView> createState() => _ReceiveViewState();
}

class _ReceiveViewState extends State<ReceiveView> {
  SubAddress? _shown; // null = primary address
  final _label = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _newSubaddress() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sub = await context.read<WalletService>().createSubaddress(label: _label.text.trim());
      setState(() => _shown = sub);
      _label.clear();
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveQr(String data) async {
    final location = await getSaveLocation(suggestedName: 'beldex-address.png');
    if (location == null) return;
    try {
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
      );
      final image = await painter.toImage(600);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, 680, 680), Paint()..color = Colors.white);
      canvas.drawImage(image, const Offset(40, 40), Paint());
      final png = await (await recorder.endRecording().toImage(680, 680)).toByteData(format: ui.ImageByteFormat.png);
      await File(location.path).writeAsBytes(png!.buffer.asUint8List());
      if (mounted) showSnack(context, 'QR code saved to ${location.path}');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save QR code', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WalletService>();
    final address = _shown?.address ?? w.address;
    final subs = [...w.usedAddresses, ...w.unusedAddresses.where((a) => a.label.isNotEmpty)];
    return ResponsiveRow(
      flex: const [2, 3],
      breakpoint: 820,
      children: [
        Panel(
          title: _shown == null ? 'Primary address' : 'Subaddress #${_shown!.index}',
          trailing: _shown == null
              ? null
              : TextButton(onPressed: () => setState(() => _shown = null), child: const Text('Show primary')),
          child: Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                // Fixed box: with an embedded logo the QR paints only once the
                // image has loaded, which would otherwise make the panel jump.
                width: 244,
                height: 244,
                child: QrImageView(
                  data: address.isEmpty ? ' ' : address,
                  size: 220,
                  padding: EdgeInsets.zero,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  embeddedImage: const AssetImage('assets/images/logo128.png'),
                  embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(44, 44)),
                ),
              ),
              if (_shown != null && _shown!.label.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_shown!.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 14),
              SelectableText(
                address,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: BeldexColors.muted, height: 1.5),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  CopyButton(address, label: 'Copy address'),
                  GhostButton('Save QR', icon: Icons.save_alt, expand: false, onPressed: () => _saveQr(address)),
                ],
              ),
            ],
          ),
        ),
        Panel(
          title: 'Subaddresses',
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Muted(
                'Give each payer their own subaddress: payments still arrive in this wallet, but nobody can link them together.',
                size: 12.5,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Field(
                      controller: _label,
                      hint: 'Label (optional, e.g. invoice-42)',
                      onSubmitted: (_) => _newSubaddress(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PrimaryButton('+ New subaddress', expand: false, busy: _busy, onPressed: _newSubaddress),
                ],
              ),
              ErrorText(_error),
              const SizedBox(height: 6),
              if (subs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Muted('No subaddresses yet.', center: true),
                )
              else
                for (final s in subs)
                  MenuRow(
                    icon: s.used ? Icons.inbox_outlined : Icons.label_outline,
                    label: s.label.isNotEmpty ? s.label : 'Subaddress #${s.index}',
                    subtitle:
                        '${shorten(s.address, head: 14, tail: 12)}${(s.balance ?? 0) > 0 ? ' · ${formatBdx(s.balance!)} BDX' : ''}',
                    trailing: _shown?.address == s.address
                        ? const Icon(Icons.qr_code_2, size: 18, color: BeldexColors.green)
                        : const Icon(Icons.chevron_right, size: 18, color: BeldexColors.muted),
                    onTap: () => setState(() => _shown = s),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
