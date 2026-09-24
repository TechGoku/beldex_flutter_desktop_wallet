import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../core/config.dart';
import 'swap_models.dart';

/// Swap order history in SQLite. Uses the same file and schema as the
/// Electron wallet (`~/Beldex/beldex_wallet.db`), so both apps share history.
class SwapStore {
  SwapStore({String? directory}) : _dir = directory ?? AppConfig.defaultWalletDir();
  final String _dir;
  Database? _db;

  Database get db {
    if (_db != null) return _db!;
    Directory(_dir).createSync(recursive: true);
    final database = sqlite3.open(p.join(_dir, 'beldex_wallet.db'));
    database.execute('PRAGMA journal_mode = WAL');
    database.execute('PRAGMA synchronous = NORMAL');
    database.execute('''
      CREATE TABLE IF NOT EXISTS swap_transactions_history (
        uuid TEXT PRIMARY KEY NOT NULL,
        wallet_address TEXT NOT NULL,
        exchange TEXT NOT NULL,
        txn_id TEXT NOT NULL,
        txn_status TEXT NOT NULL,
        txn_type TEXT NOT NULL,
        swap_type TEXT NOT NULL,
        currency_from TEXT NOT NULL,
        network_from TEXT,
        currency_to TEXT NOT NULL,
        network_to TEXT,
        payin_address TEXT,
        payin_address_memo TEXT,
        payout_address TEXT,
        payout_address_memo TEXT,
        refund_address TEXT,
        refund_status TEXT DEFAULT 'not_returned',
        refund_address_memo TEXT,
        amount_from REAL,
        amount_to REAL,
        network_fee REAL DEFAULT 0,
        platform_fee REAL DEFAULT 0,
        raw_response TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        UNIQUE(exchange, txn_id)
      )''');
    database.execute(
      'CREATE INDEX IF NOT EXISTS idx_swap_txn_wallet_created '
      'ON swap_transactions_history (wallet_address, created_at DESC)',
    );
    database.execute('CREATE INDEX IF NOT EXISTS idx_swap_txn_id ON swap_transactions_history (txn_id)');
    return _db = database;
  }

  static String _uuid() {
    final r = Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  void upsert(SwapOrder order, String walletAddress, {String? networkFrom, String? networkTo}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      '''
      INSERT INTO swap_transactions_history (
        uuid, wallet_address, exchange, txn_id, txn_status, txn_type, swap_type,
        currency_from, network_from, currency_to, network_to,
        payin_address, payin_address_memo, payout_address, payout_address_memo,
        refund_address, refund_address_memo, amount_from, amount_to, network_fee,
        raw_response, created_at, updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(exchange, txn_id) DO UPDATE SET
        txn_status = excluded.txn_status,
        payin_address = COALESCE(NULLIF(excluded.payin_address, ''), swap_transactions_history.payin_address),
        payout_address = COALESCE(NULLIF(excluded.payout_address, ''), swap_transactions_history.payout_address),
        amount_from = COALESCE(excluded.amount_from, swap_transactions_history.amount_from),
        amount_to = COALESCE(excluded.amount_to, swap_transactions_history.amount_to),
        raw_response = COALESCE(excluded.raw_response, swap_transactions_history.raw_response),
        updated_at = excluded.updated_at
    ''',
      [
        _uuid(),
        walletAddress,
        order.exchange.name,
        order.id,
        order.status,
        order.type,
        order.privacySwap ? 'privacy' : 'normal',
        order.currencyFrom,
        networkFrom,
        order.currencyTo,
        networkTo,
        order.payinAddress,
        order.payinExtraId,
        order.payoutAddress,
        order.raw['payoutExtraId'],
        order.refundAddress,
        order.raw['refundExtraId'],
        order.amountFrom,
        order.amountTo,
        order.networkFee,
        jsonEncode(order.raw),
        order.createdAtMs,
        now,
      ],
    );
  }

  int count(String walletAddress) =>
      (db.select('SELECT COUNT(*) AS c FROM swap_transactions_history WHERE wallet_address = ?', [
            walletAddress,
          ]).first['c']
          as int);

  List<SwapOrder> page(String walletAddress, {int page = 1, int pageSize = 7}) => _rows(
    db.select(
      'SELECT * FROM swap_transactions_history WHERE wallet_address = ? ORDER BY created_at DESC LIMIT ? OFFSET ?',
      [walletAddress, pageSize, (page - 1) * pageSize],
    ),
  );

  List<SwapOrder> all(String walletAddress) => _rows(
    db.select('SELECT * FROM swap_transactions_history WHERE wallet_address = ? ORDER BY created_at DESC', [
      walletAddress,
    ]),
  );

  List<SwapOrder> _rows(ResultSet rows) => [
    for (final row in rows)
      SwapOrder({
        ...(() {
          try {
            return (jsonDecode(row['raw_response'] as String? ?? '{}') as Map).cast<String, dynamic>();
          } catch (_) {
            return <String, dynamic>{};
          }
        })(),
        'id': row['txn_id'],
        'status': row['txn_status'],
        'type': row['txn_type'],
        'currencyFrom': row['currency_from'],
        'currencyTo': row['currency_to'],
        'payinAddress': row['payin_address'],
        'payoutAddress': row['payout_address'],
        'refundAddress': row['refund_address'],
        'amountExpectedFrom': row['amount_from'],
        'amountExpectedTo': row['amount_to'],
        'networkFee': row['network_fee'],
        'createdAt': row['created_at'],
        'privacySwap': row['swap_type'] == 'privacy',
      }, row['exchange'] == 'quickex' ? Exchange.quickex : Exchange.changelly),
  ];

  void close() {
    _db?.close();
    _db = null;
  }
}
