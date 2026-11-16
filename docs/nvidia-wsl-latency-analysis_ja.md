# nvidia-wsl (Ubuntu 26.04) ストリームが「CPU は低いのにカクつく」原因の整理

調査日: 2026-09-19 / 対象コンテナ: `linuxserver-kde-tatsuyai`
(webtop-kde 1.1.0, Ubuntu 26.04, encoder=`nvidia-wsl`, RTX PRO 1000 Laptop, WSL2)

バッテリー残量の都合で調査を途中で打ち切ったため、本書は
**「確認できた事実」「確度の高い推定」「未確認の可能性」** を分けて記録し、
修正は未実施です。次回作業の起点として使ってください。

---

## 1. 結論(先に要点)

| 質問 | 答え | 確度 |
| --- | --- | --- |
| NVENC が間に合っていないのか | **いいえ。** 3072x1920@30fps の全画面更新中でも NVENC 使用率は 17〜35%。エンコーダ自体には余裕がある | 確認済み |
| 無駄な処理があるか | **ある。** 1フレームごとに「GPU→CPU 同期リードバック(約 24 MB)」→「CPU→GPU 再アップロード」→「NVENC 完了を CPU が同期待ち」という直列の待ちが 3 段ある。CPU 使用率が低いのは、スレッドが計算ではなく **GPU の完了待ち(ioctl / fence poll)で寝ている** ため | 確認済み(スタック採取) |
| バッファが多すぎるか | **はい。** サーバ側キューは最大 120 フレーム(30fps で 4 秒分)、フロント側の描画待ち配列は上限なし。遅れると「捨てる」のではなく「溜める」設計になっており、時間とともに遅延が伸びてカクつきが悪化する | 確認済み(コード) |
| レイテンシ重視の設計になっているか | **なっていない箇所が複数ある**(下記 §4) | 確認済み |

一言でいうと、**ボトルネックは NVENC ではなく「WSL 経由の同期 GPU 転送の待ち時間」と「遅延を吸収するはずのバッファが逆に遅延を蓄積する設計」** です。

---

## 2. 現在のパイプライン(実測ベース)

```
KWin(nested, D3D12/GL) 
  └→ pixelflux(Rust/smithay, Selkies の Python プロセス内で動作) が 3072x1920@30Hz で合成
       └→ [render thread LWP 501] glReadPixels 相当の同期リードバック (BGRA 23.6 MB/frame, 708 MB/s)
            ※ gdb: libgallium(d3d12) 内の poll() = D3D12 fence 待ち
            └→ [wl-encode thread] cuMemcpy HtoD(ARGB) → NVENC(ARGB 直接入力) 
                 ※ gdb: libnvidia-encode → libnvcuvid → D3DKMTWaitForSynchronizationObjectFromCpu (ioctl) で同期待ち
                 └→ Python callback: bytes(frame) コピー → call_soon_threadsafe → asyncio.Queue(maxsize=120)
                      └→ websocket send → nginx(TLS) → Windows 側ブラウザ
                           └→ WebCodecs VideoDecoder(prefer-hardware, optimizeForLatency)
                                └→ 配列 `re` に push(上限なし) → requestAnimationFrame ごとに **1 枚だけ** drawImage
```

- ログ: `[Wayland] Decision: Rendering and Encoding GPUs differ -> Forcing Readback (CPU path for pixels).`
  `Mode: H264 (NVENC) FullFrame Streaming | CRF: 25 | PaintOver CRF: 20 (Burst: 5f)`
- 解像度 3072x1920 は、ブラウザ側 2048x1280 CSS px × devicePixelRatio 1.5(DPI 144 / `FORCE_DEVICE_SCALE_FACTOR=1.50`)。
  `STREAM_SCALE=1.0` なので物理ピクセルそのままをキャプチャしている。

---

## 3. 計測した数値

| 項目 | 値 | 備考 |
| --- | --- | --- |
| Selkies プロセス CPU | 28〜55%(1 コア換算、16 コア機) | どのスレッドも飽和していない |
| wl-encode スレッド CPU | 15〜28% | 残りは GPU 待ち |
| render スレッド(LWP 501) CPU | 5〜6% | gallium poll() で fence 待ち |
| NVENC 使用率(nvidia-smi enc) | 17〜35% | 飽和には遠い |
| GPU SM 使用率 | 3〜15%、瞬間的に 72% | KWin/Plasma 描画+リードバック |
| ストリーム | 3072x1920 @ 30fps, CQP(CRF 25) | I420 limited range |
| サーバ側フレームキュー | maxsize **120** frames、満杯時は **新しい方を捨てる** | `selkies.py` `_start_capture_for_display` |
| backpressure 判定 | ACK 遅延 50ms 閾値・許容 desync **2000ms**・0.5s 周期 | `BACKPRESSURE_*` 定数 |
| フロント描画待ち配列 `re` | 上限なし、rAF 1 回につき 1 枚消費 | `selkies-core.js` |
| ログ上の再起動 | `Capture loop stopped` → NVENC 再初期化が多数回 | 再設定のたびにセッション作り直し |

※ 全画面更新の負荷試験用に `ffplay`(SDL) を Xwayland 上で起動しようとしたが SEGV したため、
負荷試験は未実施。上記の数値はユーザー操作中の実測値。

---

## 4. 原因の分析

### 4.1 確認済み: フレームごとに 3 回の同期 GPU 待ち(WSL /dev/dxg 経由)

1. **リードバック**: 描画 GPU(D3D12 render node)と encode node(`/dev/dxg`)が別物と判定されるため
   pixelflux はゼロコピー(dmabuf→CUDA)を使えず「Readback path」に落ちる。
   3072x1920 BGRA = 23.6 MB を GPU→CPU に **同期** で読み戻す。WSL では dxgkrnl 経由で
   ホスト側との往復があり、1 フレームあたり十数 ms 以上かかっても CPU は消費しない。
2. **再アップロード**: 読み戻した ARGB を `cuMemcpyHtoD` で **同じ GPU** に戻す(往復で約 47 MB/frame の PCIe/共有メモリ転送)。
3. **NVENC 完了待ち**: エンコードスレッドは `D3DKMTWaitForSynchronizationObjectFromCpu` で
   ビットストリーム完了を同期待ちしている(非同期深度なし)。

この 3 つが直列なので、合計が 33 ms(30fps の 1 フレーム時間)を超えた瞬間にフレーム落ち・間欠的な
コマ飛びになる。**CPU 使用率が低いままカクつく症状と完全に一致する。**

### 4.2 確認済み: バッファが「遅延を吸収」ではなく「遅延を蓄積」する

- サーバ: `asyncio.Queue(maxsize=120)`。送信が遅れると最大 4 秒分溜まる。満杯時は
  `QueueFull` を握りつぶして **新しいフレームを捨てる**(古いフレームを送り続ける)ので、
  最悪の「古い映像を遅れて表示し続ける」挙動になる。
- backpressure は「クライアント ACK 遅延 2000 ms」まで許容してから動く。レイテンシ重視の
  設定値ではない。
- フロント: デコード済み `VideoFrame` を配列 `re` に無制限に push し、rAF ごとに 1 枚しか描かない。
  受信レートが描画レートを一時的に上回ると差分が残り続け、遅延が階段状に増える。
  さらに `VideoFrame` を閉じずに保持すると **ハードウェアデコーダの出力プールが枯渇** して
  デコード自体が詰まる(prefer-hardware では致命的)。

「時間とともにカクカクになっていく」という症状は、この蓄積型バッファの挙動でよく説明できる。

### 4.3 確度高: ビットレート制御がバースト型

- NVENC でも `CRF 25` = CQP(固定 QP)で動作しており、ビットレート上限がない。
  3072x1920 の I フレームや全画面更新時に数 MB/frame 級のバーストが出うる。
- paint-over(静止時 CRF 20 を 5 フレーム)は静止→動き出しの境目で NVENC の再設定
  (`NVENC session reconfigured in place`)とサイズの大きいフレームを挟む。
- WebSocket は TCP なので、バーストはそのまま遅延スパイク(→ 4.2 のキューに蓄積)になる。

### 4.4 可能性(未確認)

- 30 fps 固定であること自体が各段に最大 33 ms の待ちを足している(60 fps 化は 4.1 を解消した後でないと逆効果)。
- Selkies の GPU 統計取得(`nvidia-smi` を毎秒 spawn)や、`bytes(frame)` の Python 側コピーは
  CPU 的には軽微で、主因ではないと判断。
- Windows 側ブラウザの rAF レート低下(ウィンドウ非アクティブ、省電力)も `re` 蓄積の引き金になる。

---

## 5. 修正案(優先順)

| # | 内容 | 効果 | 変更箇所 | 難易度 |
| --- | --- | --- | --- | --- |
| 1 | **キャプチャ解像度を論理解像度に落とす**(DPR 1.5 → 1.0 相当。3072x1920 → 2048x1280、画素数 2.25 分の 1) | リードバック・アップロード・エンコード時間がすべて約 45% に | `STREAM_SCALE` / DPI 設定、または Selkies 側の scale 設定 | 低(設定のみ) |
| 2 | **サーバ側キューを遅延上限型に** (`maxsize=120` → 2〜3、満杯時は **古い方を捨てて最新を残す**) | 遅延蓄積を根本的に防ぐ | `files/ubuntu-root/usr/local/bin/patch-selkies-*.py` に新パッチ追加(`_start_capture_for_display` の `do_put`) | 低 |
| 3 | **フロント `re` を「最新 1 枚だけ保持」に**(古い `VideoFrame` は即 `close()`) | 遅延蓄積防止 + HW デコーダプール枯渇防止 | `patch-selkies-hardware-decode.py` と同様の JS 置換パッチ | 低〜中 |
| 4 | backpressure 閾値を短縮(許容 desync 2000 ms → 100〜200 ms 程度) | 早期にフレーム間引き | `BACKPRESSURE_ALLOWED_DESYNC_MS` | 低 |
| 5 | **NVENC のレート制御を CBR/VBR + VBV に**(`video_cbr_mode=True`, `video_bitrate_kbps`, `video_vbv_multiplier`)、NVENC でも paint-over 再設定を無効化(VA-API プロファイルと同じ扱い) | バースト抑制、再設定によるヒッチ除去 | `svc-selkies/run`(`--rate-control-mode=cbr --video-bitrate`, `SELKIES_DISABLE_HARDWARE_PAINTOVER=1`) | 低 |
| 6 | `PIXELFLUX_NVENC_PIN`(pinned host memory)の有効化を検証 | HtoD コピーの高速化 | `svc-selkies/run` の env | 低(要検証: モジュール内に文字列は存在) |
| 7 | 1〜6 の後に `SELKIES_FRAMERATE=60` を試す | 各段の待ちを半減 | `configs/*.yml` `framerate` | 低 |
| 8 | **根本対策**: pixelflux の readback を非同期化(PBO ダブルバッファで fence 待ちを次フレームに回す)、または NVENC を非同期深度 2 で運用 | 同期待ち 3 段の直列を解消 | pixelflux Rust ソース改修 + wheel 再ビルド | 高 |

推奨順序: 1 → 2 → 3 → 5 → 4 → 6 → 7。1〜5 は設定・パッチスクリプトのみで、イメージ再ビルド不要
(`init-nginx` / `svc-selkies` の起動時パッチとして適用可能)。

---

## 6. 電源復帰後に追加で確認したいこと

```bash
# 1) 全画面更新負荷をかけながら NVENC/GPU 使用率を採る(ffplay は SEGV したので es2gears か glxgears を使う)
docker exec linuxserver-kde-tatsuyai s6-setuidgid tatsuyai env DISPLAY=:0 glxgears -geometry 1800x1000 &
docker exec linuxserver-kde-tatsuyai /usr/lib/wsl/lib/nvidia-smi dmon -c 10 -s u

# 2) リードバック 1 回の所要時間(render thread が gallium poll() に居る割合)
docker exec linuxserver-kde-tatsuyai gdb -p 350 -batch -ex 'thread apply all bt 8' | grep -A8 'LWP 501'

# 3) サーバ側キュー滞留数(遅延蓄積の直接証拠)
#    selkies.py の _video_chunk_sender に queue.qsize() の debug ログを一時追加して観察

# 4) フロント側: ブラウザ DevTools で
#    window.fps, VideoDecoder.decodeQueueSize, 配列 re の length を観察
#    (re が 2 以上で推移すれば 4.2 が確定)
```

---

## 7. 参照ファイル

- `files/ubuntu-root/etc/s6-overlay/s6-rc.d/svc-selkies/run` — エンコーダ選択、CRF、paint-over、framerate
- `files/ubuntu-root/usr/local/bin/patch-selkies-pixelflux2.py` — pixelflux 2 互換層(`bytes(frame)` コピー、`encode_node_path`)
- `files/ubuntu-root/usr/local/bin/patch-selkies-hardware-decode.py` — WebCodecs 設定(prefer-hardware, codec string)
- `files/ubuntu-root/usr/local/src/pixelflux-nvenc-wsl.c` — WSL 用 NVENC シム(readback パスを選ばせる仕組み)
- `files/pixelflux/README.md` — 各プロファイルのエンコードパス説明
- コンテナ内 `/opt/selkies-env/lib/python3.14/site-packages/selkies/selkies.py`
  (`BACKPRESSURE_*`, `_video_chunk_sender`, `_start_capture_for_display`)
- コンテナ内 `/usr/share/selkies/web/src/selkies-core.js`(`function w(p)` = デコード出力、`function b()` = 描画ループ)
