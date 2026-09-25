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
bound to 127.0.0.1).

**Sync.** wallet-rpc can't be interrupted once it starts scanning: every call waits
until the wallet has caught up, so closing mid-scan used to lose everything scanned
since the last save. The app therefore puts a small local proxy
(`lib/services/daemon_proxy.dart`) between wallet-rpc and the node and drives
refreshes itself (wallet-rpc's auto refresh is off):
- scans run in 30 s chunks; the proxy ends each chunk by failing the block-sync
  requests, the app reads height and balance, saves every 60 s, and starts the next
  chunk from the same block;
- closing, switching wallets or quitting ends a scan in well under a second and
  saves it, so reopening carries on where it stopped;
- a user action during a scan ends the current chunk so it is answered at once;
- live progress, speed and time left come from the block responses the proxy sees;
- block-hash batches far below the tip are cached on disk, which makes restores and
  rescans skip ~10 s of hash downloads;
- rescans can start from a block height or date (blocks before it are skipped; an
  unfinished one carries on after a restart). wallet2 never scans below a wallet's own
  restore height, so older transactions need a fresh restore with an earlier date;
- quitting sends `stop_wallet` on a non-keep-alive connection and closes the pool, as
  wallet-rpc's server only exits once idle client connections are gone.

wallet-rpc scans as fast as `beldex-wallet-cli` (measured interleaved on the same node
and block range); speed mostly depends on the node. Transfers are fetched
incrementally, heavy work is deferred while scanning, and the app fails over to a
public node when the configured remote node is down.

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

## Packaging
- **Linux .deb**: `flutter build linux --release`, then
  `BELDEX_BIN_DIR=/path/to/beldex/bin linux/packaging/build_deb.sh [out_dir]`. Installs to
  `/opt/beldex-flutter-wallet` with a `beldex-flutter-wallet` command, desktop entry and icons.
- **Windows .exe**: built by `.github/workflows/windows.yml` on a Windows runner (Flutter can't
  cross-compile for Windows). Pushing a `v*` tag publishes an Inno Setup installer
  (`windows/installer.iss`) and a portable zip as a pre-release; manual runs keep them as
  artifacts. It bundles beldexd / beldex-wallet-rpc from the Beldex-Coin/beldex release and the
  Visual C++ runtime. Swap keys come from optional repository secrets.

## Tests
    flutter test test/core_test.dart
    BELDEX_BIN_DIR=/path/to/bin flutter test test/live_wallet_test.dart   # real wallet-rpc + public node
