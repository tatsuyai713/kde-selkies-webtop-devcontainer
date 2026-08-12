# kde-selkies-webtop-devcontainer

**[English Version (README.md)](README.md)**

ブラウザからアクセスできるコンテナ化された Kubuntu (KDE Plasma) デスクトップ環境。Selkies WebRTC ストリーミングにより、VNC や RDP なしでフル機能の Linux デスクトップを提供します。

**Ubuntu/Linux**、**macOS (Docker Desktop)**、**WSL2** に対応。すべてのプラットフォームで `build-user-image.sh`、`start-container.sh`、`create-devcontainer-config.sh` を共通の入口として利用できます。

## なぜこのプロジェクト？

[linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) をベースに、開発者の使いやすさとマルチプラットフォーム対応を重視したフォークです。

| | オリジナル | このプロジェクト |
|---|---|---|
| **イメージ提供** | Pull 可能なイメージ | 2段階ローカルビルド（ユーザーイメージは1-2分） |
| **コンテナユーザー** | Root | あなたの UID/GID（非root） |
| **UID/GID 設定** | 手動 | 自動マッチング |
| **パスワード** | コマンドに平文 | 環境変数で安全に |
| **シェル** | 汎用 bash | Ubuntu Desktop bash（カラープロンプト、Git ブランチ、エイリアス） |
| **GPU 選択** | 自動検出 | 明示的な `--encoder` / `--gpu` フラグ |
| **依存バージョン** | 変動 | 固定（VirtualGL 3.1.4、プラットフォーム互換の Pixelflux wheel、Selkies は最新 main / `SELKIES_COMMIT` で固定可能） |
| **Docker-in-Docker** | — | `--docker-mode dind\|dood` |
| **配信チューニング** | — | `-S` ストリームスケール、`-f` フレームレート制御 |
| **Dev Container** | — | `create-devcontainer-config.sh`（CLI と同じ設定項目） |
| **言語サポート** | 英語のみ | 多言語（EN/JA） |

## 主な特徴

- **2段階ビルド** — 重いベースイメージ（5-10 GB、一度だけ）＋軽量ユーザーイメージ（~100 MB、1-2分）。30-60分の待ち時間なし。
- **デフォルト非root** — コンテナはあなたのユーザー権限で実行。適切な権限分離、必要時は sudo 利用可能。
- **自動 UID/GID マッチング** — マウントしたホストディレクトリがそのまま動作。共有フォルダでの「permission denied」なし。
- **統一された設定** — `start-container.sh`（日常利用）と `create-devcontainer-config.sh`（VS Code Dev Container）が同じ対話設定を共有。
- **エンコーダー/GPU の明示的制御** — `--encoder nvidia|intel|amd|software|nvidia-wsl` でエンコーダーを選択。`--all`/`--num` で Docker GPU 割り当てを独立制御。
- **ストリームスケーリング** — `-S 0.5` でエンコード解像度を半分に。帯域とエンコーダー負荷の両方を削減。
- **Docker モード切替** — `--docker-mode dood`（ホスト socket）または `dind`（コンテナ内 dockerd）。
- **ブラウザのみでアクセス** — 起動後 `https://localhost:<30000+UID>` にアクセス。SSH/RDP の配布不要。
- **安全なパスワード** — 環境変数で設定。コマンドやログに表示されない。
- **多言語対応** — ビルド時に `-l jp` でLinux側の日本語入力（Fcitx/Anthy）、タイムゾーン、ロケールを設定。
- **バージョン固定** — VirtualGL 3.1.4、プラットフォーム互換の Pixelflux wheel、Selkies（デフォルトで最新 `main`、`SELKIES_COMMIT` ビルド引数で固定可能）により再現可能なビルドを保証。

## 対応環境

| 環境 | GPU レンダリング | WebGL / Vulkan | ハードウェアエンコード | 備考 |
|---|---|---|---|---|
| **Ubuntu + NVIDIA GPU** | ✅ | ✅ | ✅ NVENC | 最高パフォーマンス |
| **Ubuntu + Intel GPU** | ✅ | ✅ | ✅ VA-API (QSV) | 統合GPU可 |
| **Ubuntu + AMD GPU** | ✅ | ✅ | ✅ VA-API | RDNA / GCN |
| **WSL2 + NVIDIA GPU** | ❌ ソフトウェア | ❌ ソフトウェア | ✅ NVENC | エンコードは動作、レンダリングはソフトウェア |
| **macOS (Docker Desktop)** | ❌ | ❌ ソフトウェア | ❌ | VM 制限あり。ワークフローは同一 |

---

## クイックスタート

```bash
# 1. ユーザーイメージをビルド（1-2分、ベースイメージは GHCR から自動取得）
./build-user-image.sh                    # 英語（デフォルト）
./build-user-image.sh -l jp              # 日本語環境
./build-user-image.sh -u 22.04           # Ubuntu 22.04

# 2. コンテナを起動
./start-container.sh                     # 対話設定
./start-container.sh --encoder software  # ソフトウェアエンコード
./start-container.sh --encoder nvidia --all          # NVIDIA NVENC（全GPU）
./start-container.sh --encoder nvidia --num 0        # NVIDIA NVENC（GPU 0のみ）
./start-container.sh --encoder intel                 # Intel VA-API
./start-container.sh --encoder amd -r 1920x1080 -S 0.5  # AMD + 配信解像度半分
./start-container.sh --encoder nvidia-wsl --all      # WSL2 + NVIDIA NVENC

# 3. ブラウザでアクセス
#    https://localhost:<30000+UID>（例: UID 1000 → https://localhost:31000）
#    http://localhost:<40000+UID> （例: UID 1000 → http://localhost:41000）

# 4. 変更を保存（重要！コンテナ削除前に必ず実行）
./commit-container.sh
# ロールバック用に直前のイメージを残す場合のみ:
./commit-container.sh --keep-history

# 5. 停止
./stop-container.sh            # 停止（コンテナ保持、再起動可能）
./stop-container.sh --rm       # 停止して削除（commit 後のみ推奨）
```

### プラットフォーム別の例

**Ubuntu / Linux**
```bash
./build-user-image.sh -u 22.04
./start-container.sh --encoder intel
```

**macOS (Docker Desktop)**
```bash
./build-user-image.sh -u 22.04 -a amd64
./start-container.sh --encoder software -a amd64 --docker-mode dood
```

**WSL2 + NVIDIA**
```bash
./build-user-image.sh -u 22.04
./start-container.sh --encoder nvidia-wsl --all
```

### VS Code Dev Container

```bash
# 1. Dev Container 設定を生成（start-container.sh と同じ対話設定）
./create-devcontainer-config.sh

# 2. VS Code で F1 → 「Dev Containers: Reopen in Container」を選択

# 3. ブラウザから https://localhost:<表示されたポート> でデスクトップにアクセス
```

---

## 目次

- [なぜこのプロジェクト？](#なぜこのプロジェクト)
- [主な特徴](#主な特徴)
- [対応環境](#対応環境)
- [クイックスタート](#クイックスタート)
- [システム要件](#システム要件)
- [2段階ビルドシステム](#2段階ビルドシステム)
- [Intel/AMD GPU ホストセットアップ](#intelamd-gpu-ホストセットアップ)
- [セットアップ（ユーザーイメージのビルド）](#セットアップユーザーイメージのビルド)
- [使い方](#使い方)
- [付録: ベースイメージのビルド](#付録-ベースイメージのビルド)
- [付録: スクリプトリファレンス](#付録-スクリプトリファレンス)
- [付録: 設定](#付録-設定)
- [付録: HTTPS/SSL](#付録-httpsssl)
- [トラブルシューティング](#トラブルシューティング)
- [既知の制限](#既知の制限)
- [付録: 高度なトピック](#付録-高度なトピック)

---

## システム要件

### 必須

- **Docker** 20.10 以降（Docker Desktop 4.0+）
- **8 GB 以上の RAM**（16 GB 推奨）
- **20 GB 以上のディスク空き容量**

### GPU（オプション — ハードウェアアクセラレーション用）

- **NVIDIA GPU** ✅ テスト済み
  - ドライバー 470 以降、Maxwell 世代以降
  - NVIDIA Container Toolkit インストール済み
- **Intel GPU** ✅ テスト済み
  - 統合グラフィックス（HD Graphics、Iris、Arc）、Quick Sync Video 対応
  - VA-API ドライバーはコンテナに含まれる
  - **ホストセットアップ必要**（下記参照）
- **AMD GPU** ⚠️ 部分的にテスト済み
  - VCE/VCN エンコーダー搭載 Radeon
  - VA-API ドライバーはコンテナに含まれる
  - **ホストセットアップ必要**（下記参照）

---

## 2段階ビルドシステム

```
┌─────────────────────────────┐
│   ベースイメージ (5-10 GB)    │  ← 一度だけビルド（30-60分）または GHCR から取得
│  • システムパッケージ         │
│  • デスクトップ環境           │
│  • プリインストールアプリ     │
└────────────┬────────────────┘
             │
             ↓  この上にビルド
┌────────────┴────────────────┐
│ ユーザーイメージ (~100 MB)    │  ← あなたがビルド（1-2分）
│  • あなたのユーザー名         │
│  • あなたの UID/GID          │
│  • あなたのパスワード         │
└─────────────────────────────┘
```

**メリット:**
- ✅ **高速セットアップ** — 30-60分のビルド待ち不要
- ✅ **適切な権限** — ファイルがホストの UID/GID に一致
- ✅ **簡単な更新** — 新しいベースイメージを取得してユーザーイメージを再ビルド

**なぜ UID/GID マッチングが重要か:**
ホストディレクトリ（例: `$HOME`）をマウントするにはファイルの所有権が一致する必要があります。不一致だと権限エラーが発生します。ユーザーイメージがこれを自動的に処理します。

---

## Intel/AMD GPU ホストセットアップ

Intel/AMD ハードウェアエンコード（VA-API）を使用する場合のみ必要。NVIDIA GPU では不要。

### 1. ユーザーを video/render グループに追加

```bash
sudo usermod -aG video,render $USER
# ログアウト・再ログイン後に確認:
groups  # "video" と "render" が含まれていること
```

### 2. VA-API ドライバーのインストール

**Intel:**
```bash
sudo apt update && sudo apt install vainfo intel-media-va-driver-non-free
vainfo  # VAProfileH264Main : VAEntrypointEncSlice が表示されること
```

**AMD:**
```bash
sudo apt update && sudo apt install vainfo mesa-va-drivers
vainfo  # VAProfileH264Main : VAEntrypointEncSlice が表示されること
```

> ホストで VA-API が正しく動作すれば、コンテナ内でも自動的に動作します。

---

## セットアップ（ユーザーイメージのビルド）

ベースイメージは GHCR から自動取得されるため、通常利用では手動ビルド不要です。

```bash
# 英語（デフォルト）
./build-user-image.sh

# 日本語
./build-user-image.sh -l jp

# パスワードプロンプトをスキップ
USER_PASSWORD=yourpass ./build-user-image.sh
```

**オプション:**
```bash
./build-user-image.sh -u 22.04           # Ubuntu 22.04
./build-user-image.sh -v 2.0.0           # カスタムバージョン
./build-user-image.sh -b my-base:1.1.0   # カスタムベースイメージタグ
./build-user-image.sh -i ghcr.io/you/img  # カスタムベースイメージ名
./build-user-image.sh -a amd64           # アーキテクチャヒント
./build-user-image.sh -p linux/amd64     # 明示的なプラットフォーム指定
./build-user-image.sh -n                 # Docker キャッシュなしでビルド
```

---

## 使い方

### コンテナの起動

初回起動時は対話ウィザードが設定を `configs/<name>.yml` に保存し、次回以降はその設定を自動で読み込みます。
保存済みの設定を再編集するには `--reconfigure` を使用します。

```bash
# 初回起動 — すべての設定を入力して保存
./start-container.sh

# 再設定 — 保存済みの値をデフォルトとして対話式で編集してから起動
./start-container.sh --reconfigure

# CLI の例
./start-container.sh --encoder software
./start-container.sh --encoder nvidia --all
./start-container.sh --encoder nvidia --num 0
./start-container.sh --encoder intel --dri-node /dev/dri/renderD129
./start-container.sh --encoder amd -r 2560x1440 -d 144 -S 0.5
./start-container.sh --encoder nvidia-wsl --all --docker-mode dood
./start-container.sh --encoder software -a amd64   # --platform linux/amd64 を自動付与
```

**対話設定の項目**（`configure-container.sh` で管理）:

コンテナ名、Ubuntu バージョン、アーキテクチャ、Docker モード（`dind`/`dood`）、エンコーダー、Docker GPU 選択（`--all`/`--num`）、DRI ノード、解像度、DPI、ストリームスケール、フレームレート、タイムゾーン、言語、SSL ディレクトリ、Mac/Docker Desktop 設定

**既存コンテナの挙動:**
- 同名の停止中コンテナ → 以前の設定で再開（プロンプトなし）
- 同名の起動中コンテナ → スクリプト終了

**UID ベースのポート割り当て**（マルチユーザー対応）:
- HTTPS: `30000 + UID`（例: UID 1000 → ポート 31000）
- HTTP: `40000 + UID`（例: UID 1000 → ポート 41000）

**リモートアクセス:** WebRTC ベース。LAN IP を自動検出、`https://<ホストIP>:<HTTPSポート>` でアクセス。

**コンテナの特徴:**
- 停止してもコンテナは削除されない（再起動や commit がいつでも可能）
- ホスト名: `Docker-$(hostname)`
- ホストホーム: `~/host_home` でマウント
- ホスト `/mnt`: `~/host_mnt` でマウント（Linux/WSL2 のみ、macOS ではスキップ）
  - WSL2 では Windows ドライブにアクセス可能（例: `~/host_mnt/c/Users/...`）
- コンテナ名: `linuxserver-kde-{username}`
- `dind` はコンテナ内 `dockerd`、`dood` はホスト Docker socket を利用
- `STREAM_SCALE` は表示だけでなくエンコード前の実解像度を縮小

### 変更の保存（重要！）

```bash
./commit-container.sh
```

- ⚠️ **`./stop-container.sh --rm` の前に必ず commit** — さもなければ変更が失われます
- イメージ名形式: `webtop-kde-{username}-{arch}-u{ubuntu_version}:{version}`
- commit したイメージはコンテナ削除後も残る
- 次回起動時は自動的に commit したイメージを使用
- 以前のイメージタグは、他から参照されていなければデフォルトで削除される。
  `--keep-history` を指定した場合は日時付きの `history` タグで保持する。commitの
  レイヤー自体は圧縮されないため、容量削減には `flatten-container.sh` を使用する
- コンテナ内の **Commit Container** アイコンから実行した場合は、commit前に直前の
  イメージ履歴を保持するかGUIで選択できる

### イメージのフラット化

```bash
./flatten-container.sh
```

- 現在のコンテナファイルシステムを単一レイヤーのイメージに変換する。環境変数、
  ENTRYPOINT、CMD、ラベル、ポート、宣言済みボリュームなどのメタデータは維持される
- コンテナのファイルシステムと同程度の一時容量が必要で、数分かかる場合がある
- 通常の `docker commit` と同様、マウントされたボリュームとbind mountの内容は含まれない
- デフォルトではCLIとデスクトップ操作のどちらも、フラット化成功後に元コンテナとタグの
  ない旧イメージを自動削除する。次回起動時はフラット化済みイメージが使われる。CLIで
  `--keep-container` を指定した場合、元コンテナを削除するまで旧レイヤーは解放されない
- コンテナ内の **Flatten Container** デスクトップアイコンからも同じ処理を実行でき、
  Breezeの `archive-insert` アクションアイコンで表示される

**典型的なワークフロー:**
```bash
./shell-container.sh          # コンテナ内で作業
# ... パッケージインストール、環境設定 ...
exit
./commit-container.sh         # イメージに保存
./stop-container.sh --rm      # 安全に削除可能
./start-container.sh --encoder intel   # すべての変更が反映された状態で再開
```

### コンテナの停止

```bash
./stop-container.sh            # 停止（コンテナ保持）
./stop-container.sh --rm       # 停止して削除
```

---

## 付録: ベースイメージのビルド

GHCR から取得する代わりに自分でビルドする場合のみ必要（30-60分）:

```bash
./files/build-base-image.sh                         # Ubuntu 24.04、アーキテクチャ自動検出
./files/build-base-image.sh -u 22.04                # Ubuntu 22.04
./files/build-base-image.sh -a amd64                # Intel/AMD 64-bit
./files/build-base-image.sh -a arm64                # Apple Silicon / ARM
./files/build-base-image.sh -a amd64 -u 22.04       # オプション組み合わせ
./files/build-base-image.sh --no-cache               # クリーンリビルド

# GHCR へ Push
./files/push-base-image.sh

# カスタムリポジトリ
IMAGE_NAME=ghcr.io/you/your-base ./files/build-base-image.sh
IMAGE_NAME=ghcr.io/you/your-base ./files/push-base-image.sh
```

---

## 付録: スクリプトリファレンス

### コアスクリプト

| スクリプト | 説明 | 使い方 |
|---|---|---|
| `build-user-image.sh` | ユーザー固有イメージをビルド | `./build-user-image.sh [-l jp] [-u 22.04]` |
| `start-container.sh` | コンテナを起動/再開 | `./start-container.sh [--encoder <type>]` |
| `configure-container.sh` | 保存済みの起動設定を作成・編集 | `./configure-container.sh [--config <file>]` |
| `create-devcontainer-config.sh` | Dev Container 設定を生成 | `./create-devcontainer-config.sh` |
| `stop-container.sh` | コンテナを停止 | `./stop-container.sh [--rm]` |

### 管理スクリプト

| スクリプト | 説明 | 使い方 |
|---|---|---|
| `shell-container.sh` | コンテナ内シェルを開く | `./shell-container.sh` |
| `commit-container.sh` | コンテナ状態をイメージに保存 | `./commit-container.sh` |
| `flatten-container.sh` | コンテナを単一レイヤーのイメージに圧縮 | `./flatten-container.sh` |
| `logs-container.sh` | コンテナログを表示 | `./logs-container.sh` |
| `restart-container.sh` | コンテナを再起動 | `./restart-container.sh` |
| `delete-image.sh` | ユーザーイメージを削除 | `./delete-image.sh` |
| `files/build-base-image.sh` | ベースイメージをビルド | `./files/build-base-image.sh [-a arch]` |
| `files/push-base-image.sh` | ベースイメージを GHCR へ Push | `./files/push-base-image.sh` |

### 起動オプション

```
./start-container.sh [オプション]

エンコーダー / GPU:
  -e, --encoder <type>       software | nvidia | nvidia-wsl | intel | amd
  -g, --gpu <value>          Docker --gpus 値: all または device=0,1
  --all                      --gpu all のショートカット
  --num <list>               --gpu device=<list> のショートカット
  --dri-node <path>          VA-API 用 DRI レンダーノード

表示:
  -r <WxH>                   解像度（例: 1920x1080）
  -d <dpi>                   DPI（例: 96, 144, 192）
  -S, --stream-scale <f>     エンコード解像度の倍率（0.25-1.0）
  -f <fps|min-max>           フレームレート（例: 30, 30-60）

その他:
  --docker-mode <mode>       dind または dood
  --timezone <tz>            タイムゾーン（例: Asia/Tokyo）
  -a <arch>                  amd64 / arm64
  -p <platform>              docker run の --platform を明示指定
  -s <ssl_dir>               SSL 証明書ディレクトリ
  -n <name>                  コンテナ名
  --config <file>            YAML 設定ファイル（デフォルト: configs/<name>.yml）
  --reconfigure              保存済みの設定を起動前に対話式で再編集
```

---

## 付録: 設定

### 表示設定

```bash
./start-container.sh -r 1920x1080 -d 96              # 標準
./start-container.sh -r 2560x1440 -d 144             # WQHD HiDPI
./start-container.sh -r 3840x2160 -d 192             # 4K HiDPI

# ストリームスケール — エンコード解像度を縮小
./start-container.sh --encoder software -r 1920x1080 -S 0.5
# 960x540 でエンコードし、1920x1080 のビューポートで表示
```

### ビデオエンコード

| GPU | エンコーダー | 品質 | CPU 負荷 |
|---|---|---|---|
| NVIDIA | NVENC | 高 | 低 |
| Intel | VA-API (Quick Sync) | 高 | 低 |
| AMD | VA-API | 高 | 低 |
| なし | Software (libx264) | 中 | 高 |

`-S/--stream-scale` はエンコード前に解像度を縮小し、帯域とエンコーダー負荷の両方を削減します。

### オーディオ

| 機能 | 状態 | 技術 |
|---|---|---|
| スピーカー出力 | ✅ 内蔵 | WebRTC（ブラウザネイティブ） |
| マイク入力 | ✅ 内蔵 | WebRTC（ブラウザネイティブ） |

Selkies はブラウザへ WebRTC 経由で双方向オーディオをストリーミングします。

---

## 付録: HTTPS/SSL

Selkies はデスクトップ配信にセキュアWebSocket（`wss://`）を使用します。
HTTPSの警告画面を一度許可するだけでは不十分で、ブラウザによってはWSSだけを
拒否し、要求がnginxまで届きません。ブラウザを実行するすべての端末へローカルCAを
登録してください。

### 1. ローカルCAとサーバー証明書の生成

```bash
# https://localhost:PORT でアクセスする場合
./generate-ssl-cert.sh -c localhost

# リモートDockerホストへDNS名でアクセスする場合
./generate-ssl-cert.sh -f -c webtop.example.lan

# ssl/ は自動検出される
./start-container.sh
```

`ssl/` の作成前からコンテナが存在していた場合、Dockerは既存コンテナへ後から
証明書のバインドマウントを追加できません。コンテナ内だけにある作業を保存してから
再作成してください。

```bash
docker stop linuxserver-kde-$(whoami)
docker rm linuxserver-kde-$(whoami)
./start-container.sh
```

すでにマウント済みの `ssl/` 内の証明書だけを交換した場合は、nginxが新しい証明書を
読み込むようコンテナを再起動します。

ブラウザでは `-c` に指定したものと同じDNS名を使用してください。生成スクリプトは
`localhost`、`127.0.0.1`、`::1` を自動的にSANへ追加しますが、任意のリモートIPは
IP SANとして追加しません。リモートIPでアクセスする場合は、そのIPを
`subjectAltName` に含む独自証明書を使用するか、ホストへローカルDNS名を割り当てます。

生成されるファイル：

| ファイル | 用途 | 配布可否 |
|---|---|---|
| `ssl/ca.crt` | ローカルCAの公開証明書 | ブラウザ端末へ配布可 |
| `ssl/ca.key` | ローカルCAの秘密鍵 | **配布禁止・要厳重保管** |
| `ssl/cert.pem` | サーバー証明書 | コンテナへマウント |
| `ssl/cert.key` | サーバー秘密鍵 | **配布禁止・要厳重保管** |

### 2. ブラウザ端末へ `ssl/ca.crt` を信頼登録

登録先はDockerホストではなく、実際にブラウザを実行する端末です。両者が別の
コンピューターの場合は、ブラウザ側へ `ca.crt` だけを安全に転送してください。

#### macOS

現在のユーザーだけで信頼する場合（開発端末で推奨）：

```bash
security add-trusted-cert -r trustRoot \
  -k "$HOME/Library/Keychains/login.keychain-db" ./ssl/ca.crt
```

全ユーザーで信頼する場合（管理者権限が必要）：

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ./ssl/ca.crt
```

GUIでは `ca.crt` をキーチェーンアクセスへ読み込み、証明書を開いて「信頼」から
「常に信頼」を選択します。詳細はAppleの
[証明書の信頼設定](https://support.apple.com/ja-jp/guide/keychain-access/kyca11871/mac)を参照してください。
変更後はタブを閉じるだけでなく、ブラウザを `Cmd+Q` で完全終了して再起動します。

#### Windows 10/11

`ca.crt` をWindowsへコピーしてPowerShellを実行します。現在のユーザーだけへの
登録には管理者権限は不要です。

```powershell
Import-Certificate -FilePath .\ca.crt `
  -CertStoreLocation Cert:\CurrentUser\Root
```

全ユーザーで信頼する場合は、PowerShellを「管理者として実行」します。

```powershell
Import-Certificate -FilePath .\ca.crt `
  -CertStoreLocation Cert:\LocalMachine\Root
```

詳細はMicrosoftの
[`Import-Certificate` ドキュメント](https://learn.microsoft.com/powershell/module/pki/import-certificate)を
参照してください。登録後はChrome、Edge、Firefoxを完全終了して再起動します。

#### WSL2

通常、ブラウザはWindows側で動作するため、上記のWindows証明書ストアへ登録します。
WSLからWindowsへコピーする例：

```bash
cp ./ssl/ca.crt /mnt/c/Users/<WindowsUser>/Downloads/kde-webtop-ca.crt
```

WSL内の `curl`、`git`、SDKなどにも信頼させる場合は、Windowsとは別にWSL
ディストリビューション内でも次のUbuntu/Debian手順を実行します。

#### Ubuntu / Debian

```bash
sudo apt-get install -y ca-certificates
sudo cp ./ssl/ca.crt /usr/local/share/ca-certificates/kde-webtop-ca.crt
sudo update-ca-certificates
```

ファイルの拡張子は `.crt` が必須です。詳細はUbuntuの
[ルートCA登録ガイド](https://ubuntu.com/server/docs/how-to/security/install-a-root-ca-certificate-in-the-trust-store/)を
参照してください。

#### Fedora / RHEL / Rocky Linux / AlmaLinux

```bash
sudo cp ./ssl/ca.crt /etc/pki/ca-trust/source/anchors/kde-webtop-ca.crt
sudo update-ca-trust
```

詳細はRed Hatの
[共有システム証明書のドキュメント](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/security_guide/sec-shared-system-certificates)を
参照してください。

#### iOS / iPadOS / visionOS

`ca.crt` だけを端末へ転送し、ダウンロードした証明書プロファイルをインストールします。
続いて「設定 > 一般 > 情報 > 証明書信頼設定」を開き、「Local Development CA」の
完全な信頼を有効にします。手動インストールしたルート証明書は、この操作を行うまで
TLSでは信頼されません。詳細は
[Appleの手順](https://support.apple.com/ja-jp/102390)を参照してください。

#### Android

`ca.crt` だけを端末へ転送し、「設定 > セキュリティとプライバシー > その他の
セキュリティ設定 > 暗号化と認証情報 > 証明書のインストール > CA証明書」から
登録します。メニュー名は端末メーカーとAndroidバージョンによって異なります。
プライベートCAは自分が管理する端末だけへ登録してください。詳細はGoogleの
[証明書登録手順](https://support.google.com/pixelphone/answer/2844832?hl=ja)を参照してください。

#### ChromeOS

`chrome://settings/certificates` を開き、「認証局 > インポート」から `ca.crt` を
読み込み、確認画面でWebサイトの信頼を有効にします。管理対象Chromebookでは、管理者が
「Google管理コンソール > デバイス > ネットワーク > 証明書」からCAを配布する必要が
あります。詳細はGoogleの
[ChromeOS証明書登録手順](https://support.google.com/chromebook/answer/1282338?hl=ja)と
[管理対象端末へのCA設定](https://support.google.com/chrome/a/answer/6342302?hl=ja)を参照してください。

### ブラウザ別の注意

- Chrome、Chromium、Edge、SafariはOSのローカル信頼設定を使用します。CAを登録・
  交換した後はブラウザを完全終了して再起動してください。
- FirefoxはWindows、macOS、AndroidではデフォルトでOSへ追加されたサードパーティCAを
  使用します。無効になっている場合は「設定 > プライバシーとセキュリティ > 証明書」の
  「インストールしたサードパーティのルート証明書をFirefoxが自動的に信頼する」を
  有効にします。LinuxでシステムCAが検出されない場合は「証明書を表示 > 認証局」から
  `ca.crt` を読み込みます。詳細はMozillaの
  [CA設定ガイド](https://support.mozilla.org/ja/kb/setting-certificate-authorities-firefox)を参照してください。
- 通常のブラウザ利用では `--no-ca` を使用しないでください。単独の自己署名サーバー
  証明書を作るだけで、ブラウザの信頼警告は解消されません。

### 3. HTTPSとWSSの確認

`start-container.sh` が表示したHTTPS URLで確認します。

```bash
# -k は付けない。通常の証明書検証に成功する必要がある
curl -I https://localhost:<HTTPS-port>/
```

`200` または `/auth/login` へのリダイレクトになればTLS検証は成功です。ブラウザの
開発者ツールでは「Network > WS」の `/websockets` がステータス `101` になることを
確認します。ページが数秒ごとに再読込され、nginxに `/websockets` が記録されない場合は、
ブラウザを完全再起動し、ブラウザ端末側へCAが登録されているか確認してください。

`./generate-ssl-cert.sh -f` で証明書を再生成すると新しいCA鍵になります。すべての
ブラウザ端末で、新しい `ssl/ca.crt` を再登録してください。

### 独自証明書の使用

```bash
mkdir -p ssl
cp /path/to/cert.pem ssl/
cp /path/to/key.pem ssl/cert.key
./start-container.sh   # ssl/ を自動検出
```

### `generate-ssl-cert.sh` のオプション

| オプション | 説明 | デフォルト |
|---|---|---|
| `-c <hostname>` | Common Name / DNSホスト名 | `localhost` |
| `-d <dir>` | 出力ディレクトリ | `./ssl` |
| `-n <days>` | 有効期間 | `365` |
| `--no-ca` | CAなしの自己署名証明書 | CAモード |
| `-f` | 既存証明書を上書き | — |

### 証明書の優先順位

1. 明示した `-s <dir>`、保存済みの `ssl_dir`、または `SSL_DIR`
2. SSLディレクトリが未指定の場合、プロジェクト内の `ssl/cert.pem` + `ssl/cert.key`
3. イメージのデフォルト証明書（フォールバック）

---

## トラブルシューティング

### コンテナが起動しない

```bash
docker logs linuxserver-kde-$(whoami)
docker images | grep webtop-kde
./build-user-image.sh                           # ユーザーイメージを再ビルド
sudo netstat -tulpn | grep -E "31000|41000"     # ポート競合を確認
```

### GPU が検出されない

```bash
# NVIDIA
./shell-container.sh
nvidia-smi

# Intel / AMD
./shell-container.sh
ls -la /dev/dri/ && vainfo

# Docker GPU アクセスの確認
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

### 権限の問題

```bash
id                    # ホスト上
./shell-container.sh
id                    # コンテナ内 — UID が一致していること
# 不一致の場合: ./build-user-image.sh で再ビルド
```

### 黒画面 / デスクトップが表示されない

```bash
docker logs linuxserver-kde-$(whoami)
docker exec linuxserver-kde-$(whoami) pgrep -af plasmashell
docker exec linuxserver-kde-$(whoami) ls -la /run/user/$(id -u)
```

原因: `/run/user/<uid>` が存在しないまたは権限不正、plasmashell のクラッシュ → コンテナを再起動。

### WebGL/Vulkan が動かない

```bash
docker exec linuxserver-kde-$(whoami) glxinfo | head -30
docker exec linuxserver-kde-$(whoami) vulkaninfo | head -50
```

macOS: Docker VM の制限により GPU アクセラレーションは不可。ソフトウェアレンダリングで動作。

### 音声が出ない

```bash
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl info'
docker exec linuxserver-kde-$(whoami) bash -lc 's6-setuidgid "${USER_NAME}" pactl list sinks short'
```

ブラウザのオーディオ権限を確認し、HTTPS を使用してください（一部ブラウザは HTTP でオーディオをブロック）。

---

## 既知の制限

### Vulkan
- Xvfb は DRI3 をサポートしていないため、Vulkan アプリケーションはフレームをプレゼントできない
- VirtualGL ベースの OpenGL は正常に動作
- 環境によっては Xvfb 上で vkcube が NVIDIA GPU を検出するが、プレゼンテーションの挙動は構成依存

### macOS
- Docker Desktop はコンテナを Linux VM 内で実行 — Apple GPU（Metal）へのアクセス不可
- WebGL/Vulkan はソフトウェアレンダリング（llvmpipe）
- ハードウェアアクセラレーションが必要な場合は Linux 実機または WSL2 を使用

### WSL2
- NVIDIA GPU のみ対応
- レンダリングはソフトウェア（llvmpipe）、WebGL/Vulkan もソフトウェアのみ
- ハードウェアエンコード（NVENC）は `--encoder nvidia-wsl` で動作

---

## 付録: 高度なトピック

### 環境変数

<details>
<summary>クリックで展開</summary>

#### コンテナ

| 変数 | 説明 | デフォルト |
|---|---|---|
| `CONTAINER_NAME` | コンテナ名 | `linuxserver-kde-$(whoami)` |
| `IMAGE_BASE` | イメージベース名 | `webtop-kde` |
| `IMAGE_VERSION` | イメージバージョン | `1.1.0` |

#### 表示

| 変数 | 説明 | デフォルト |
|---|---|---|
| `RESOLUTION` | 解像度 | `1920x1080` |
| `DPI` | DPI | `96` |
| `STREAM_SCALE` | エンコード解像度の倍率 | `1.0` |
| `FRAMERATE` | Selkies フレームレート | `30` |
| `TIMEZONE` | タイムゾーン | `UTC` |

#### GPU

| 変数 | 説明 | デフォルト |
|---|---|---|
| `ENCODER` | エンコーダー種別 | （未設定） |
| `GPU_VENDOR` | GPU ベンダー | `software` |
| `DOCKER_MODE` | Docker モード | `dind` |

#### ネットワーク

| 変数 | 説明 | デフォルト |
|---|---|---|
| `PORT_SSL_OVERRIDE` | HTTPS ポート上書き | `UID + 30000` |
| `PORT_HTTP_OVERRIDE` | HTTP ポート上書き | `UID + 40000` |

</details>

### プロジェクト構造

```
kde-selkies-webtop-devcontainer/
├── build-user-image.sh           # ユーザーイメージビルド
├── start-container.sh            # コンテナ起動
├── create-devcontainer-config.sh # Dev Container 設定生成
├── compose-env.sh                # compose/devcontainer 用 env 生成
├── interactive-common.sh         # 対話設定の共通処理
├── stop-container.sh             # コンテナ停止
├── restart-container.sh          # コンテナ再起動
├── shell-container.sh            # シェルアクセス
├── commit-container.sh           # 変更保存
├── flatten-container.sh          # イメージレイヤーを圧縮
├── logs-container.sh             # ログ表示
├── delete-image.sh               # ユーザーイメージ削除
├── generate-ssl-cert.sh          # SSL 証明書生成
├── ssl/                          # SSL 証明書（自動検出）
│   ├── cert.pem
│   └── cert.key
└── files/                        # システムファイル
    ├── build-base-image.sh       # ベースイメージビルド
    ├── push-base-image.sh        # ベースイメージを GHCR へ Push
    ├── linuxserver-kde.base.dockerfile
    ├── linuxserver-kde.user.dockerfile
    ├── alpine-root/              # s6-overlay 設定
    ├── kde-root/                 # KDE デフォルト
    └── ubuntu-root/              # Ubuntu デフォルト
```

### バージョン固定

再現可能なビルドのため、外部依存関係を固定:

- **VirtualGL:** 3.1.4（Dockerfile のビルド引数）
- **Pixelflux:** amd64 は 1.6.0。Ubuntu 22.04 arm64 は、Jammy の libva に新しい arm64 wheel が必要とする `vaMapBuffer2` シンボルがないため 1.4.7。arm64 wheel はベースイメージのビルド時に PyPI から取得し、SHA-256 を検証
- **Selkies:** デフォルトで最新 `main` ブランチを追跡。`--build-arg SELKIES_COMMIT=<hash>` で特定コミットに固定可能

ハードウェアエンコード:
- **NVIDIA:** Pixelflux 経由の NVENC
- **Intel:** Pixelflux 経由の VA-API (Quick Sync Video)
- **AMD:** Pixelflux 経由の VA-API

バージョンは [files/linuxserver-kde.base.dockerfile](files/linuxserver-kde.base.dockerfile) で定義。

---

## ライセンス

このプロジェクトは複数のオープンソースプロジェクトを基にしています:
- [linuxserver/webtop](https://github.com/linuxserver/docker-webtop) — GPL-3.0
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — MPL-2.0
- [VirtualGL](https://github.com/VirtualGL/virtualgl) — LGPL

詳細は各プロジェクトのライセンスを参照してください。

## 関連プロジェクト

- [tatsuyai713/devcontainer-egl-desktop](https://github.com/tatsuyai713/devcontainer-egl-desktop) — EGL ベース版（3つの表示モード対応）
- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) — 元プロジェクト
- [selkies-project/selkies](https://github.com/selkies-project/selkies) — WebRTC ストリーミング

## クレジット

**元プロジェクト:**
- **Selkies Project:** [github.com/selkies-project](https://github.com/selkies-project)
- **LinuxServer.io:** [github.com/linuxserver](https://github.com/linuxserver)

**このプロジェクト:**
- **改善点:** 2段階ビルド、非root実行、UID/GID マッチング、安全なパスワード管理、管理スクリプト、バージョン固定、マルチGPU/エンコーダー対応、Dev Container 統合
- **メンテナー:** [@tatsuyai713](https://github.com/tatsuyai713)
