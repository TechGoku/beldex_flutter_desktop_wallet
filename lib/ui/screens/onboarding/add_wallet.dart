import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/validators.dart';
import '../../../services/models.dart';
import '../../../services/wallet_service.dart';
import '../../../state/app_controller.dart';
import '../../kit.dart';
import '../../theme.dart';
import '../../widgets/common.dart' show errorText;

/// "Add a wallet" menu: create or restore (extension onboarding style).
class AddWalletScreen extends StatelessWidget {
  const AddWalletScreen({super.key, this.firstRun = false});
  final bool firstRun;

  void _go(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final list = context.watch<WalletService>().walletList;
    return BScaffold(
      body: Column560(
        maxWidth: 440,
        padding: EdgeInsets.fromLTRB(20, firstRun ? 70 : 40, 20, 20),
        children: [
          if (!firstRun)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
            ),
          const Center(child: BrandMark(large: true)),
          const SizedBox(height: 20),
          Center(
            child: Text(
              firstRun ? 'PRIVACY, IN EVERY TRANSACTION' : 'ADD A WALLET',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 6),
          if (firstRun) const Muted('Keep your payments and identity private', center: true),
          const SizedBox(height: 28),
          PrimaryButton('Create new wallet', icon: Icons.add, onPressed: () => _go(context, const CreateWalletFlow())),
          const SizedBox(height: 10),
          GhostButton(
            'Restore from seed',
            icon: Icons.restore,
            onPressed: () => _go(context, const RestoreWalletFlow(mode: RestoreMode.seed)),
          ),
          const SectionLabel('More options'),
          BCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                MenuRow(
                  icon: Icons.key_outlined,
                  label: 'Restore from keys',
                  subtitle: 'Address + private view/spend keys',
                  onTap: () => _go(context, const RestoreWalletFlow(mode: RestoreMode.keys)),
                ),
                MenuRow(
                  icon: Icons.visibility_outlined,
                  label: 'Add view-only wallet',
                  subtitle: 'Watch incoming funds without spending',
                  onTap: () => _go(context, const RestoreWalletFlow(mode: RestoreMode.viewOnly)),
                ),
                MenuRow(
                  icon: Icons.file_open_outlined,
                  label: 'Import wallet file',
                  subtitle: 'A .keys file from another Beldex wallet',
                  onTap: () => _go(context, const RestoreWalletFlow(mode: RestoreMode.file)),
                ),
                for (final legacy in list.legacy)
                  MenuRow(
                    icon: Icons.history,
                    label: 'Import legacy GUI wallet',
                    subtitle: legacy.path,
                    onTap: () => _go(context, RestoreWalletFlow(mode: RestoreMode.file, initialPath: legacy.path)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Create: details -> seed -> quiz
// ===========================================================================

enum _CreateStep { details, seed, quiz }

class CreateWalletFlow extends StatefulWidget {
  const CreateWalletFlow({super.key});
  @override
  State<CreateWalletFlow> createState() => _CreateWalletFlowState();
}

class _CreateWalletFlowState extends State<CreateWalletFlow> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _language = 'English';
  _CreateStep _step = _CreateStep.details;
  WalletSecrets? _secrets;
  String? _error;
  bool _busy = false;

  // Quiz state: 5 random positions, their words shuffled, tapped back in order
  List<int> _quizIdx = [];
  List<String> _choices = [];
  List<int> _picked = [];

  @override
  void dispose() {
    for (final c in [_name, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final exists = context.read<WalletService>().walletList.wallets.any((w) => w.name == name);
    final error = name.isEmpty
        ? 'Enter a wallet name'
        : exists
        ? 'A wallet with this name already exists'
        : _password.text.length < 8
        ? 'Password must be at least 8 characters'
        : _password.text != _confirm.text
        ? 'Passwords do not match'
        : null;
    if (error != null) return setState(() => _error = error);
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final wallet = context.read<WalletService>();
      final app = context.read<AppController>();
      final secrets = await wallet.createWallet(name, _password.text, _language);
      await app.rememberWallet(name);
      setState(() {
        _secrets = secrets;
        _step = _CreateStep.seed;
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startQuiz() {
    final words = _secrets!.mnemonic.trim().split(RegExp(r'\s+'));
    final rnd = Random.secure();
    final positions = <int>{};
    while (positions.length < 5) {
      positions.add(rnd.nextInt(words.length));
    }
    _quizIdx = positions.toList()..sort();
    _choices = [for (final i in _quizIdx) words[i]]..shuffle(rnd);
    _picked = [];
    setState(() => _step = _CreateStep.quiz);
  }

  void _checkQuiz() {
    final words = _secrets!.mnemonic.trim().split(RegExp(r'\s+'));
    final wrong = [
      for (var i = 0; i < _quizIdx.length; i++)
        if (_choices[_picked[i]].toLowerCase() != words[_quizIdx[i]].toLowerCase()) _quizIdx[i] + 1,
    ];
    if (wrong.isNotEmpty) {
      setState(() {
        _error =
            'Word${wrong.length > 1 ? 's' : ''} #${wrong.join(', #')} ${wrong.length > 1 ? 'are' : 'is'} wrong — check your backup and try again';
        _picked = [];
      });
      return;
    }
    // Wallet is already open; drop the onboarding pages to reveal it
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Once the wallet exists, leaving must go through the seed steps
      canPop: _step == _CreateStep.details,
      child: BScaffold(
        body: Column560(
          maxWidth: 480,
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
          children: switch (_step) {
            _CreateStep.details => _details(),
            _CreateStep.seed => _seed(),
            _CreateStep.quiz => _quiz(),
          },
        ),
      ),
    );
  }

  List<Widget> _details() => [
    Row(
      children: [
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 4),
        const Expanded(child: H2('Create wallet')),
      ],
    ),
    Field(controller: _name, hint: 'Wallet name (e.g. Savings)', autofocus: true),
    Field(controller: _password, hint: 'Password (min 8 characters)', obscure: true, onChanged: (_) => setState(() {})),
    StrengthMeter(_password.text),
    Field(controller: _confirm, hint: 'Confirm password', obscure: true, onSubmitted: (_) => _create()),
    Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Muted('Seed language'),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _language,
            items: const [
              'English',
              'Deutsch',
              'Español',
              'Français',
              'Italiano',
              'Nederlands',
              'Português',
              'Русский',
              '日本語',
              '简体中文 (中国)',
              'Esperanto',
              'Lojban',
            ].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
            onChanged: (v) => _language = v ?? _language,
          ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    PrimaryButton('Create wallet', busy: _busy, onPressed: _create),
    ErrorText(_error),
  ];

  List<Widget> _seed() => [
    const H2('Your recovery seed'),
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BeldexColors.input,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: BeldexColors.green, style: BorderStyle.solid),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (i, w) in _secrets!.mnemonic.trim().split(RegExp(r'\s+')).indexed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: BeldexColors.card, borderRadius: BorderRadius.zero),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${i + 1} ',
                      style: const TextStyle(color: BeldexColors.faint, fontSize: 11.5),
                    ),
                    TextSpan(
                      text: w,
                      style: const TextStyle(color: BeldexColors.green, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    const Warn('Write these 25 words down and store them safely. They are the only way to recover your funds.'),
    const SizedBox(height: 12),
    CopyPill(_secrets!.mnemonic, display: 'Copy seed to clipboard (auto-clears in 60 s)', secret: true),
    const SizedBox(height: 20),
    PrimaryButton('I saved my seed — continue', onPressed: _startQuiz),
  ];

  List<Widget> _quiz() {
    final next = _picked.length;
    return [
      const H2('Confirm your seed'),
      Text.rich(
        TextSpan(
          style: const TextStyle(color: BeldexColors.muted, fontSize: 12),
          children: [
            const TextSpan(text: 'Tap the words below in this order: '),
            TextSpan(
              text: _quizIdx.map((i) => '#${i + 1}').join(' → '),
              style: const TextStyle(color: BeldexColors.green),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      for (var i = 0; i < _quizIdx.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: BeldexColors.input,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: i == next ? BeldexColors.green : BeldexColors.border),
          ),
          child: Row(
            children: [
              Muted('#${_quizIdx[i] + 1}'),
              const Spacer(),
              Text(
                i < _picked.length ? _choices[_picked[i]] : '—',
                style: const TextStyle(color: BeldexColors.green, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var ci = 0; ci < _choices.length; ci++)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                foregroundColor: _picked.contains(ci) ? BeldexColors.faint : BeldexColors.text,
              ),
              onPressed: () => setState(() {
                _error = null;
                _picked.contains(ci) ? _picked.remove(ci) : _picked.add(ci);
              }),
              child: Text(_choices[ci], style: const TextStyle(fontWeight: FontWeight.w400)),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(child: GhostButton('Back to seed', onPressed: () => setState(() => _step = _CreateStep.seed))),
          const SizedBox(width: 8),
          Expanded(child: PrimaryButton('Confirm', onPressed: _picked.length == _quizIdx.length ? _checkQuiz : null)),
        ],
      ),
      ErrorText(_error),
    ];
  }
}

// ===========================================================================
// Restore: seed / keys / view-only / file
// ===========================================================================

enum RestoreMode { seed, keys, viewOnly, file }

class RestoreWalletFlow extends StatefulWidget {
  const RestoreWalletFlow({super.key, required this.mode, this.initialPath});
  final RestoreMode mode;
  final String? initialPath;
  @override
  State<RestoreWalletFlow> createState() => _RestoreWalletFlowState();
}

class _RestoreWalletFlowState extends State<RestoreWalletFlow> {
  final _seed = TextEditingController();
  final _address = TextEditingController();
  final _viewKey = TextEditingController();
  final _spendKey = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _height = TextEditingController();
  DateTime? _date;
  bool _useHeight = false;
  String? _path;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
  }

  @override
  void dispose() {
    for (final c in [_seed, _address, _viewKey, _spendKey, _name, _password, _confirm, _height]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    RestoreMode.seed => 'Restore from seed',
    RestoreMode.keys => 'Restore from keys',
    RestoreMode.viewOnly => 'View-only wallet',
    RestoreMode.file => 'Import wallet file',
  };

  String? _validate() {
    final name = _name.text.trim();
    if (name.isEmpty) return 'Enter a wallet name';
    if (context.read<WalletService>().walletList.wallets.any((w) => w.name == name)) {
      return 'A wallet with this name already exists';
    }
    if (widget.mode != RestoreMode.file && _password.text.length < 8) return 'Password must be at least 8 characters';
    if (_password.text != _confirm.text) return 'Passwords do not match';
    switch (widget.mode) {
      case RestoreMode.seed:
        if (!isValidSeedLength(_seed.text)) return 'The seed must have 25 words (${seedWordCount(_seed.text)} entered)';
      case RestoreMode.keys:
      case RestoreMode.viewOnly:
        if (!looksLikeAddress(_address.text.trim())) return 'Invalid public address';
        if (!isHex64(_viewKey.text.trim())) return 'Invalid private view key';
        if (widget.mode == RestoreMode.keys && !isHex64(_spendKey.text.trim())) return 'Invalid private spend key';
      case RestoreMode.file:
        if (_path == null) return 'Choose a wallet file';
    }
    if (_useHeight && int.tryParse(_height.text) == null) return 'Enter a block height';
    return null;
  }

  Future<void> _restore() async {
    final error = _validate();
    if (error != null) return setState(() => _error = error);
    setState(() {
      _error = null;
      _busy = true;
    });
    final wallet = context.read<WalletService>();
    final app = context.read<AppController>();
    final name = _name.text.trim();
    try {
      int height = 0;
      if (widget.mode != RestoreMode.file) {
        height = _useHeight ? int.parse(_height.text) : (_date == null ? 0 : await wallet.heightForDate(_date!));
      }
      switch (widget.mode) {
        case RestoreMode.seed:
          await wallet.restoreFromSeed(name, _password.text, _seed.text, height);
        case RestoreMode.keys:
          await wallet.restoreFromKeys(
            name,
            _password.text,
            address: _address.text.trim(),
            viewKey: _viewKey.text.trim(),
            spendKey: _spendKey.text.trim(),
            restoreHeight: height,
          );
        case RestoreMode.viewOnly:
          await wallet.restoreViewOnly(
            name,
            _password.text,
            address: _address.text.trim(),
            viewKey: _viewKey.text.trim(),
            restoreHeight: height,
          );
        case RestoreMode.file:
          await wallet.importWallet(name, _password.text, _path!);
      }
      await app.rememberWallet(name);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _restorePoint() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionLabel('Scan from'),
      if (_useHeight)
        Field(controller: _height, hint: 'Block height', inputFormatters: [FilteringTextInputFormatter.digitsOnly])
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.zero,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date ?? DateTime.now().subtract(const Duration(days: 30)),
                firstDate: DateTime(2018, 5, 3),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.event, size: 18)),
              child: Text(
                _date == null ? 'Wallet creation date (faster restore)' : DateFormat.yMMMd().format(_date!),
                style: TextStyle(fontSize: 13, color: _date == null ? BeldexColors.faint : BeldexColors.text),
              ),
            ),
          ),
        ),
      Row(
        children: [
          Expanded(
            child: Muted(
              _useHeight
                  ? 'Scanning starts at this height.'
                  : _date == null
                  ? 'No date: the whole chain is scanned (slowest).'
                  : 'Scanning starts a day before this date.',
              size: 11,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _useHeight = !_useHeight),
            child: Text(_useHeight ? 'Use a date' : 'Use block height'),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    return BScaffold(
      body: Column560(
        maxWidth: 480,
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
        children: [
          Row(
            children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: 4),
              Expanded(child: H2(_title)),
            ],
          ),
          if (mode == RestoreMode.seed) ...[
            Field(
              controller: _seed,
              hint: 'Enter your 25-word seed',
              maxLines: 4,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Muted(
                '${seedWordCount(_seed.text)} / 25 words',
                size: 10.5,
                color: isValidSeedLength(_seed.text) ? BeldexColors.green : null,
              ),
            ),
          ],
          if (mode == RestoreMode.keys || mode == RestoreMode.viewOnly) ...[
            Field(controller: _address, hint: 'Public address', mono: true, autofocus: true),
            Field(controller: _viewKey, hint: 'Private view key (64 hex characters)', mono: true),
            if (mode == RestoreMode.keys)
              Field(controller: _spendKey, hint: 'Private spend key (64 hex characters)', mono: true),
          ],
          if (mode == RestoreMode.file) ...[
            GhostButton(
              _path ?? 'Choose a .keys file',
              icon: Icons.folder_open,
              onPressed: () async {
                final file = await openFile();
                if (file != null) setState(() => _path = file.path);
              },
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          Field(controller: _name, hint: 'Wallet name (e.g. Savings)'),
          Field(
            controller: _password,
            hint: mode == RestoreMode.file ? 'Wallet file password' : 'Choose a password (min 8 characters)',
            obscure: true,
            onChanged: (_) => setState(() {}),
          ),
          if (mode != RestoreMode.file) StrengthMeter(_password.text),
          Field(controller: _confirm, hint: 'Confirm password', obscure: true),
          if (mode != RestoreMode.file) _restorePoint(),
          const SizedBox(height: 16),
          PrimaryButton(mode == RestoreMode.file ? 'Import' : 'Restore', busy: _busy, onPressed: _restore),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Muted(
                'Restoring… the wallet opens as soon as it is created and keeps scanning in the background.',
                size: 11,
                center: true,
              ),
            ),
          ErrorText(_error),
        ],
      ),
    );
  }
}
