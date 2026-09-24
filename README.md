# Beldex Wallet (Flutter desktop)

Desktop wallet for Beldex with feature parity with the Electron wallet: wallets
(create / restore from seed or keys / view-only / import file / legacy & old-GUI
import), send & receive, history with notes and CSV export, address book,
subaddresses, master nodes (stake, register, unlock, deregistration check), BNS
(buy, update, renew, decrypt), proofs & sign/verify, key images, and swaps via
Changelly / QuickEx. Uses the same translations as the Electron wallet.

## Design
- **Theme** from the Beldex browser extension (`Agatha-luna/beldex-wallet-extension`,
  `privacy-token-integration` branch, `public/panel.html`): `#0a0a0a` background with the
  beldex.io dot grid, `#101010` panels with `#222` hairlines, square corners, white primary
  buttons that turn green on hover, `#3ec745` green / `#1574ad` blue, Michroma headings and
  Space Mono text (OFL, bundled).
- **Layout** is desktop-first: a sidebar (wallet switcher, Wallet / Services navigation,
  Settings, Lock, sync status) and full-width pages capped at 1180 px: Overview (balance,
  address + QR, recent activity, network), a Transactions table with filters
  and search, two-column Send / Receive, a Contacts table, and a two-column Settings grid.
  Columns stack below ~820 px. Shortcuts: Ctrl+1…9 pages, Ctrl+, settings, Ctrl+L lock,
  F5 refresh, Ctrl+F search transactions, Esc closes sub-pages. Window: 1280×840, min 960×620.
- Tokens are not shown: `beldex-wallet-rpc` 7.0.4 has no token RPCs.
- Rendering uses Skia on Linux for crisper text on 1x displays; set `BELDEX_IMPELLER=1` to use
  Impeller instead.
- Screenshots of every main screen: `flutter test test/screens_test.dart --update-goldens`
  writes them to `test/screens/`.

## How it works
The app spawns `beldex-wallet-rpc` (and `beldexd` for a local node) and talks to
them directly over JSON-RPC (HTTP Basic auth, random per-launch credentials,
bound to 127.0.0.1). Sync design: scanning starts immediately on open (explicit
`refresh`), auto-refresh every 10 s, cheap heartbeat, incremental `get_transfers`,
heavy work deferred while scanning, automatic failover when the remote node is down.

Wallet files default to `~/Beldex/wallets` and swap history to `~/Beldex/beldex_wallet.db`,
the same as the Electron wallet, so both apps share them. Config is separate.
wallet-rpc uses port 29296 by default, so both apps can run at once.

## Build (Linux)
    sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
    flutter build linux --release

Without sudo, a private toolchain unpacked from the Ubuntu packages works too
(this is how the current build was made): `~/sdk/sysroot` holds clang 18, ninja
and the GTK headers, and `source ~/sdk/flutter-linux-env.sh` puts them on the
PATH / pkg-config path before `flutter build linux`.
    # put beldexd and beldex-wallet-rpc next to the executable:
    mkdir -p build/linux/x64/release/bundle/bin && cp /path/to/beldex/bin/* build/linux/x64/release/bundle/bin/

Binaries are searched in `$BELDEX_BIN_DIR`, `<exe dir>/bin`, `./bin`, then `PATH`.

Swap API keys are compiled in, as in the Electron build:

    --dart-define=CHANGELLY_SWAP_API_KEY=... --dart-define=CHANGELLY_SWAP_PRIVATE_KEY=<pkcs8 der hex>
    --dart-define=CHANGELLY_PRIVACY_SWAP_API_KEY=... --dart-define=CHANGELLY_PRIVACY_SWAP_PRIVATE_KEY=...
    --dart-define=QUICKEX_SWAP_PUPLIC_KEY=... --dart-define=QUICKEX_SWAP_SECRET_KEY=... --dart-define=QUICKEX_REFERRER_ID=...

## Tests
    flutter test test/core_test.dart
    BELDEX_BIN_DIR=/path/to/bin flutter test test/live_wallet_test.dart   # real wallet-rpc + public node
