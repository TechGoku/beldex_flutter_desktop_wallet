import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format.dart';
import '../../../core/validators.dart';
import '../../../services/models.dart';
import '../../../services/price_service.dart';
import '../../../services/wallet_service.dart';
import '../../../state/app_controller.dart';
import '../../explorer.dart';
import '../../kit.dart';
import '../../theme.dart';
import '../../widgets/common.dart' show errorText;

enum _Recipient { empty, checking, valid, invalid }

class SendView extends StatefulWidget {
  const SendView({super.key, this.initialAddress, required this.onDone});
  final String? initialAddress;
  final VoidCallback onDone;
  @override
  State<SendView> createState() => _SendViewState();
}

class _SendViewState extends State<SendView> {
  late final _to = TextEditingController(text: widget.initialAddress ?? '');
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _contactName = TextEditingController();
  bool _flash = true;
  bool _saveContact = false;
  _Recipient _state = _Recipient.empty;
  String? _resolved; // address a BNS name resolves to
  String? _recipientError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (_to.text.isNotEmpty) _check(_to.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_to, _amount, _note, _contactName]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Validates as you type; wallet-rpc is only asked once typing pauses.
  void _check(String value) {
    _debounce?.cancel();
    final text = value.trim();
    setState(() {
      _resolved = null;
      _recipientError = null;
      _state = text.isEmpty ? _Recipient.empty : _Recipient.checking;
    });
    if (text.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final wallet = context.read<WalletService>();
      try {
        if (isBnsAddressName(text)) {
          final address = await wallet.resolveBns(text);
          if (!mounted || _to.text.trim() != text) return;
          setState(() {
            _resolved = address;
            _state = _Recipient.valid;
          });
        } else {
          final ok = await wallet.validateAddress(text);
          if (!mounted || _to.text.trim() != text) return;
          setState(() {
            _state = ok ? _Recipient.valid : _Recipient.invalid;
            _recipientError = ok ? null : 'Not a valid Beldex address for this network';
          });
        }
      } catch (e) {
        if (!mounted || _to.text.trim() != text) return;
        setState(() {
          _state = _Recipient.invalid;
          _recipientError = errorText(e);
        });
      }
    });
  }

  String get _target => _resolved ?? _to.text.trim();

  String? _amountError(int unlocked) {
    if (_amount.text.isEmpty) return null;
    final a = parseBdx(_amount.text);
    if (a == null) return 'Invalid amount';
    if (a <= 0) return 'Amount must be greater than 0';
    if (a > unlocked) return 'More than your unlocked balance';
    return null;
  }

  Future<void> _pickContact() async {
    final book = context.read<WalletService>().addressBook;
    final picked = await showBModal<AddressBookEntry>(
      context,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const H2('Contacts'),
            if (book.isEmpty) const Muted('No contacts yet. Save one when you send, or add them under Contacts.'),
            for (final e in book)
              MenuRow(
                icon: e.starred ? Icons.star : Icons.person_outline,
                label: e.name,
                subtitle: shorten(e.address, head: 10, tail: 10),
                onTap: () => Navigator.pop(ctx, e),
              ),
          ],
        );
      },
    );
    if (picked != null) {
      _to.text = picked.address;
      _check(picked.address);
    }
  }

  Future<void> _review() async {
    final wallet = context.read<WalletService>();
    final app = context.read<AppController>();
    final amount = parseBdx(_amount.text)!;
    final name = isBnsAddressName(_to.text.trim()) ? WalletService.fullBnsName(_to.text) : null;
    final askPassword = app.config.askPasswordOnSend;

    final result = await showBModal<_SendResult>(
      context,
      dismissible: false,
      width: 460,
      builder: (_) => _ReviewFlow(
        wallet: wallet,
        target: _target,
        name: name,
        amount: amount,
        flash: _flash,
        note: _note.text.trim(),
        askPassword: askPassword,
      ),
    );
    if (result == null || !mounted) return;
    if (_saveContact && !wallet.addressBook.any((e) => e.address == _target)) {
      final contactName = _contactName.text.trim().isEmpty ? (name ?? 'Contact') : _contactName.text.trim();
      unawaited(wallet.saveAddressBookEntry(address: _target, name: contactName).catchError((_) {}));
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = context.select<WalletService, int>((w) => w.unlockedBalance);
    final price = context.select<PriceService, double?>((p) => p.usd);
    final amountErr = _amountError(unlocked);
    final amount = parseBdx(_amount.text);
    final canReview = _state == _Recipient.valid && amount != null && amount > 0 && amountErr == null;

    Widget? recipientStatus = switch (_state) {
      _Recipient.checking => const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      _Recipient.valid => const Icon(Icons.check_circle, color: BeldexColors.green, size: 18),
      _Recipient.invalid => const Icon(Icons.error_outline, color: BeldexColors.red, size: 18),
      _Recipient.empty => null,
    };

    final form = Panel(
      title: 'Payment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
            controller: _to,
            hint: 'Recipient address or BNS name (name.bdx)',
            mono: true,
            autofocus: widget.initialAddress == null,
            onChanged: _check,
            errorText: _recipientError,
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?recipientStatus,
                IconButton(
                  tooltip: 'Paste',
                  iconSize: 18,
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _to.text = data!.text!.trim();
                      _check(_to.text);
                    }
                  },
                  icon: const Icon(Icons.content_paste),
                ),
                IconButton(
                  tooltip: 'Contacts',
                  iconSize: 18,
                  onPressed: _pickContact,
                  icon: const Icon(Icons.contacts_outlined),
                ),
              ],
            ),
          ),
          if (_resolved != null) ...[
            IconLabel(
              Icons.check,
              '${WalletService.fullBnsName(_to.text)} resolves to:',
              color: BeldexColors.green,
              size: 12,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: BeldexColors.input,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: BeldexColors.border),
              ),
              child: SelectableText(_resolved!, style: const TextStyle(fontSize: 12, color: BeldexColors.green)),
            ),
            const SizedBox(height: 4),
            const Muted('Verify this address with the recipient — BNS names can change owner.', size: 11.5),
            const SizedBox(height: 10),
          ],
          Field(
            controller: _amount,
            hint: 'Amount (BDX)',
            onChanged: (_) => setState(() {}),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,9}'))],
            errorText: amountErr,
            helper: amount != null && price != null && amountErr == null
                ? '≈ \$${(amount / atomicUnitsPerBdx * price).toStringAsFixed(2)}'
                : 'Available: ${formatBdx(unlocked)} BDX',
            suffix: TextButton(
              onPressed: () => setState(
                () => _amount.text = (unlocked / atomicUnitsPerBdx)
                    .toStringAsFixed(9)
                    .replaceFirst(RegExp(r'\.?0+$'), ''),
              ),
              child: const Text('MAX'),
            ),
          ),
          MenuRow(
            icon: Icons.bolt,
            label: 'Flash — instant confirmation',
            trailing: SquareSwitch(value: _flash, onChanged: (v) => setState(() => _flash = v)),
            onTap: () => setState(() => _flash = !_flash),
          ),
          const SizedBox(height: 6),
          Field(controller: _note, hint: 'Note (optional, only stored in this wallet)'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _saveContact,
            onChanged: (v) => setState(() => _saveContact = v ?? false),
            title: const Text('Save recipient to contacts', style: TextStyle(fontSize: 12.5)),
          ),
          if (_saveContact) Field(controller: _contactName, hint: 'Contact name'),
          const SizedBox(height: 8),
          Row(
            children: [
              GhostButton('Clear', expand: false, onPressed: _clear),
              const Spacer(),
              SizedBox(width: 200, child: PrimaryButton('Review', onPressed: canReview ? _review : null)),
            ],
          ),
        ],
      ),
    );

    return ResponsiveRow(
      flex: const [3, 2],
      breakpoint: 820,
      children: [
        form,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Available(),
            const SizedBox(height: 16),
            _QuickContacts(
              onPick: (e) {
                _to.text = e.address;
                _check(e.address);
              },
            ),
          ],
        ),
      ],
    );
  }

  void _clear() {
    for (final c in [_to, _amount, _note, _contactName]) {
      c.clear();
    }
    setState(() => _saveContact = false);
    _check('');
  }
}

/// Spendable balance beside the form.
class _Available extends StatelessWidget {
  const _Available();

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WalletService>();
    final hidden = context.select<AppController, bool>((a) => a.config.hideBalance);
    String mask(String s) => hidden ? '••••' : s;
    return Panel(
      title: 'Available',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${mask(formatBdx(w.unlockedBalance))} BDX',
            style: const TextStyle(fontFamily: BeldexFonts.display, fontSize: 20, color: BeldexColors.green),
          ),
          const SizedBox(height: 10),
          DetailLine.text('Total', '${mask(formatBdx(w.balance))} BDX'),
          DetailLine.text(
            'Locked',
            '${mask(formatBdx((w.balance - w.unlockedBalance).clamp(0, 1 << 62)))} BDX',
            last: true,
          ),
          const SizedBox(height: 6),
          const Muted('Received funds unlock after 10 blocks (about 20 minutes).', size: 12),
        ],
      ),
    );
  }
}

/// Starred contacts first; click to fill the recipient.
class _QuickContacts extends StatelessWidget {
  const _QuickContacts({required this.onPick});
  final ValueChanged<AddressBookEntry> onPick;

  @override
  Widget build(BuildContext context) {
    final book = context.select<WalletService, List<AddressBookEntry>>((w) => w.addressBook);
    final sorted = [...book.where((e) => e.starred), ...book.where((e) => !e.starred)].take(8).toList();
    return Panel(
      title: 'Contacts',
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: sorted.isEmpty
          ? const Padding(padding: EdgeInsets.only(bottom: 10), child: Muted('Saved recipients appear here.', size: 12))
          : Column(
              children: [
                for (final e in sorted)
                  MenuRow(
                    icon: e.starred ? Icons.star : Icons.person_outline,
                    label: e.name,
                    subtitle: shorten(e.address, head: 10, tail: 8),
                    trailing: const Icon(Icons.north_west, size: 16, color: BeldexColors.muted),
                    onTap: () => onPick(e),
                  ),
              ],
            ),
    );
  }
}

class _SendResult {
  _SendResult(this.hashes);
  final List<String> hashes;
}

enum _Phase { password, preparing, review, sending, success, error }

/// Review -> (password) -> fee -> confirm -> progress -> success/failure.
class _ReviewFlow extends StatefulWidget {
  const _ReviewFlow({
    required this.wallet,
    required this.target,
    required this.name,
    required this.amount,
    required this.flash,
    required this.note,
    required this.askPassword,
  });
  final WalletService wallet;
  final String target;
  final String? name;
  final int amount;
  final bool flash;
  final String note;
  final bool askPassword;

  @override
  State<_ReviewFlow> createState() => _ReviewFlowState();
}

class _ReviewFlowState extends State<_ReviewFlow> {
  late _Phase _phase = widget.askPassword ? _Phase.password : _Phase.preparing;
  final _password = TextEditingController();
  PendingTransfer? _pending;
  String _error = '';
  List<String> _hashes = const [];
  int _step = 0;

  static const _steps = ['Building transaction', 'Broadcasting to the network', 'Saving'];

  @override
  void initState() {
    super.initState();
    if (_phase == _Phase.preparing) _prepare(null);
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _prepare(String? password) async {
    setState(() {
      _phase = _Phase.preparing;
      _error = '';
    });
    try {
      final pending = await widget.wallet.prepareTransfer(
        password: password,
        amount: widget.amount,
        address: widget.target,
        priority: widget.flash ? 5 : 1,
      );
      if (mounted) {
        setState(() {
          _pending = pending;
          _phase = _Phase.review;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = errorText(e);
      setState(() {
        _error = msg;
        _phase = widget.askPassword && msg.toLowerCase().contains('password') ? _Phase.password : _Phase.error;
      });
    }
  }

  Future<void> _send() async {
    setState(() {
      _phase = _Phase.sending;
      _step = 1;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted) setState(() => _step = 2);
      final hashes = await widget.wallet.relay(_pending!, note: widget.note);
      if (mounted) setState(() => _step = 3);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        setState(() {
          _hashes = hashes;
          _phase = _Phase.success;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _phase = _Phase.error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.password => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const H2('Confirm with password'),
          Field(
            controller: _password,
            hint: 'Wallet password',
            obscure: true,
            autofocus: true,
            onSubmitted: (_) => _prepare(_password.text),
          ),
          ErrorText(_error),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: GhostButton('Cancel', onPressed: () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(child: PrimaryButton('Continue', onPressed: () => _prepare(_password.text))),
            ],
          ),
        ],
      ),
      _Phase.preparing => const Column(
        children: [
          SizedBox(height: 8),
          SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(height: 16),
          H2('Calculating fee'),
          Muted('Selecting outputs and building the transaction…', center: true),
        ],
      ),
      _Phase.review => _review(),
      _Phase.sending => Column(
        children: [
          const SizedBox(height: 6),
          const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          const H2('Sending'),
          Muted(_steps[(_step - 1).clamp(0, _steps.length - 1)]),
          const SizedBox(height: 10),
          GlowProgress(_step / _steps.length),
          const SizedBox(height: 6),
          Muted('step $_step of ${_steps.length}', size: 10),
        ],
      ),
      _Phase.success => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: SuccessTick()),
          const SizedBox(height: 10),
          const Center(child: H2('Sent!')),
          const Muted('Transaction hash'),
          const SizedBox(height: 4),
          for (final h in _hashes) ...[CopyPill(h), const SizedBox(height: 6)],
          const SizedBox(height: 8),
          Row(
            children: [
              if (_hashes.isNotEmpty)
                Expanded(
                  child: GhostButton(
                    'Explorer ↗',
                    onPressed: () => launchUrl(explorerUrl(widget.wallet.netType, 'tx', _hashes.first)),
                  ),
                ),
              if (_hashes.isNotEmpty) const SizedBox(width: 8),
              Expanded(child: PrimaryButton('Done', onPressed: () => Navigator.pop(context, _SendResult(_hashes)))),
            ],
          ),
        ],
      ),
      _Phase.error => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: FailMark()),
          const SizedBox(height: 10),
          const Center(child: H2('Send failed')),
          Text(_error, style: const TextStyle(color: BeldexColors.red, fontSize: 12)),
          const SizedBox(height: 14),
          GhostButton('Close', onPressed: () => Navigator.pop(context)),
        ],
      ),
    };
  }

  Widget _review() {
    final p = _pending!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const H2('Review transaction'),
        if (widget.name != null)
          DetailLine('BNS name', Text(widget.name!, style: const TextStyle(fontSize: 12, color: BeldexColors.green))),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Muted(widget.name != null ? 'Resolves to' : 'Recipient', size: 11),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: BeldexColors.input,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: BeldexColors.green),
          ),
          child: SelectableText(widget.target, style: const TextStyle(fontSize: 12.5, color: BeldexColors.green)),
        ),
        const SizedBox(height: 8),
        DetailLine.text('Amount', '${formatBdx(p.totalAmount)} BDX'),
        DetailLine.text('Network fee', '${formatBdx(p.totalFee)} BDX'),
        DetailLine(
          'Total',
          Text(
            '${formatBdx(p.totalAmount + p.totalFee)} BDX',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        DetailLine(
          'Priority',
          widget.flash
              ? const IconLabel(Icons.bolt, 'Flash (instant)', color: BeldexColors.green, size: 12)
              : const Text('Normal', style: TextStyle(fontSize: 12)),
          last: true,
        ),
        const SizedBox(height: 10),
        const Warn('Transactions are irreversible. Verify the full recipient address before confirming.'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: GhostButton('Cancel', onPressed: () => Navigator.pop(context))),
            const SizedBox(width: 8),
            Expanded(child: PrimaryButton('Confirm send', onPressed: _send)),
          ],
        ),
      ],
    );
  }
}
