import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../services/models.dart';
import '../../../services/wallet_service.dart';
import '../../kit.dart';
import '../../theme.dart';
import '../../widgets/common.dart' show errorText;
import 'home_screen.dart';

class ContactsView extends StatefulWidget {
  const ContactsView({super.key});
  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final book = context.select<WalletService, List<AddressBookEntry>>((w) => w.addressBook);
    final q = _query.toLowerCase();
    final list = book
        .where(
          (e) =>
              q.isEmpty ||
              e.name.toLowerCase().contains(q) ||
              e.address.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q),
        )
        .toList();
    final viewOnly = context.select<WalletService, bool>((w) => w.viewOnly);
    final sorted = [...list.where((e) => e.starred), ...list.where((e) => !e.starred)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search name, address or note',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Muted('${book.length} saved', size: 12),
            const Spacer(),
            PrimaryButton('+ Add contact', expand: false, onPressed: () => editContact(context, null)),
          ],
        ),
        const SizedBox(height: 14),
        Material(
          color: BeldexColors.panel,
          shape: const RoundedRectangleBorder(side: BorderSide(color: BeldexColors.border)),
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 860;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: BeldexColors.border)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(flex: 3, child: TableHead('Name')),
                        const Expanded(flex: 5, child: TableHead('Address')),
                        if (wide) const Expanded(flex: 3, child: TableHead('Note')),
                        const SizedBox(width: 150),
                      ],
                    ),
                  ),
                  if (sorted.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Muted(book.isEmpty ? 'No contacts yet' : 'No matches', center: true),
                    )
                  else
                    for (final e in sorted)
                      InkWell(
                        onTap: () => _open(context, e),
                        hoverColor: BeldexColors.hover,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: BeldexColors.rowBorder)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Icon(
                                      e.starred ? Icons.star : Icons.person_outline,
                                      size: 17,
                                      color: e.starred ? BeldexColors.amber : BeldexColors.muted,
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        e.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 5,
                                child: Text(
                                  shorten(e.address, head: 18, tail: 14),
                                  style: const TextStyle(fontSize: 12.5, color: BeldexColors.muted),
                                ),
                              ),
                              if (wide)
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    e.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5, color: BeldexColors.muted),
                                  ),
                                ),
                              SizedBox(
                                width: 150,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: 'Copy address',
                                      iconSize: 17,
                                      color: BeldexColors.muted,
                                      onPressed: () => copyText(e.address),
                                      icon: const Icon(Icons.copy_rounded),
                                    ),
                                    if (!viewOnly) ...[
                                      const SizedBox(width: 4),
                                      IconChip(
                                        icon: Icons.north_east,
                                        label: 'Send',
                                        onTap: () => HomeScreen.of(context)?.sendTo(e.address),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, AddressBookEntry e) async {
    final wallet = context.read<WalletService>();
    await showBModal<void>(
      context,
      builder: (ctx) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (e.starred)
                  const Padding(
                    padding: EdgeInsets.only(right: 8, bottom: 14),
                    child: Icon(Icons.star, color: BeldexColors.amber, size: 18),
                  ),
                Expanded(child: H2(e.name)),
              ],
            ),
            CopyPill(e.address),
            if (e.description.isNotEmpty) ...[const SizedBox(height: 10), Muted(e.description)],
            const SizedBox(height: 16),
            if (!wallet.viewOnly)
              PrimaryButton(
                'Send to ${e.name}',
                icon: Icons.north_east,
                onPressed: () {
                  Navigator.pop(ctx);
                  HomeScreen.of(context)?.sendTo(e.address);
                },
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    'Edit',
                    onPressed: () {
                      Navigator.pop(ctx);
                      editContact(context, e);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    'Delete',
                    danger: true,
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await wallet.deleteAddressBookEntry(e.index);
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Add or edit a contact.
Future<void> editContact(BuildContext context, AddressBookEntry? entry) async {
  final wallet = context.read<WalletService>();
  final address = TextEditingController(text: entry?.address);
  final name = TextEditingController(text: entry?.name);
  final note = TextEditingController(text: entry?.description);
  var starred = entry?.starred ?? false;
  String? error;
  var busy = false;
  await showBModal<void>(
    context,
    width: 460,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> save() async {
            final addr = address.text.trim();
            if (name.text.trim().isEmpty) return setState(() => error = 'Enter a name');
            if (name.text.contains('::')) return setState(() => error = 'Name cannot contain "::"');
            setState(() {
              busy = true;
              error = null;
            });
            if (!await wallet.validateAddress(addr)) {
              return setState(() {
                busy = false;
                error = 'Not a valid Beldex address';
              });
            }
            if (entry == null && wallet.addressBook.any((e) => e.address == addr)) {
              return setState(() {
                busy = false;
                error = 'This address is already a contact';
              });
            }
            try {
              await wallet.saveAddressBookEntry(
                address: addr,
                name: name.text.trim(),
                description: note.text.trim(),
                starred: starred,
                replaceIndex: entry?.index,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              setState(() {
                busy = false;
                error = errorText(e);
              });
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              H2(entry == null ? 'Add contact' : 'Edit contact'),
              Field(controller: name, hint: 'Name', autofocus: true),
              Field(controller: address, hint: 'Beldex address', mono: true),
              Field(controller: note, hint: 'Note (optional)'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: starred,
                onChanged: (v) => setState(() => starred = v ?? false),
                secondary: const Icon(Icons.star, color: BeldexColors.amber, size: 18),
                title: const Text('Favourite (shown first)', style: TextStyle(fontSize: 12.5)),
              ),
              ErrorText(error),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: GhostButton('Cancel', onPressed: () => Navigator.pop(ctx))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton('Save', busy: busy, onPressed: save),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
  for (final c in [address, name, note]) {
    c.dispose();
  }
}
