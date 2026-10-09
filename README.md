# OPPIY SCOPE

YOLO-Pose(YOLOv8n-pose)でダンス動画をブラウザ内で解析し、
動きの大きさ・メリハリ・音ハメ・可動域・左右バランス・揃いを数値化して記録するWebアプリ。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `index.html` | アプリ本体(HTML/CSS/JS 1枚) |
| `yolov8n-pose.onnx` | 姿勢推定モデル(Ultralytics YOLOv8n-pose を ONNX 変換、入力 640×640、出力 [1,56,8400]) |
| `ort-wasm-simd-threaded.wasm` | ONNX Runtime Web 1.20.1 の実行エンジン |

3ファイルを同じフォルダに置いて、静的ホスティング(Cloudflare Pages など)で配信すれば動きます。
`file://` で直接開くと fetch が失敗するので、ローカル確認は `npx serve .` などで。

## 動作の流れ

1. 動画を選ぶ → `<video>` で指定コマ数/秒ごとにシーク
2. 640×640 にレターボックス → YOLO-Pose で人物と関節17点を検出 → NMS
3. 位置の近さで人物を追跡(最大8人、左から D1, D2…)
4. 音声を OfflineAudioContext でデコード → テンポ(BPM)と拍の位置を推定
5. 関節の速さ・角度・止めの瞬間から6指標を計算 → 総合スコア(重み付き平均)
6. 見本と比較する場合: 8関節の角度の時系列(約4コマ/秒)を、部分一致のDTW(動的時間伸縮)で見本に合わせ、振りの一致度・タイミング・部位別ズレ・2秒ごとの一致度を算出。左右反転の見本も自動判定

## 裏側(Supabase)

- プロジェクト: `oppiy-scope`(東京 `ap-northeast-1`)
- テーブル: `analyses`(`id` uuid / `user_id` / `created_at` / `data` jsonb に記録を丸ごと)。定義は `supabase/migrations/`
- RLS: ログイン済みユーザーのみ読み書き可。匿名は不可。スタジオ内共有ツールの前提で、ログイン済み同士は互いの記録を見られる
- ログイン: Supabase Auth のメール+パスワード。**セルフ登録は無効**にし、ユーザーは管理画面(Authentication → Users → Add user)で追加する
- `index.html` 先頭の `SUPABASE_URL` / `SUPABASE_KEY` は公開してよい publishable key。Service Role Key は絶対に置かない

`index.html` 側は `db.collection("analyses").doc(id).set / update / delete` の形を `makeDb()` で保っているので、保存系の呼び出し元(`saveBtn`、`confirmDelete`、`clearSamples`、`wireCompare`、`data-refmark`)は触っていない。

## まだ差し替えが必要な箇所

| 箇所 | 今 | 差し替え先 |
|---|---|---|
| AIコーチ(`runCoach` の `window.claude.use("sample")`) | claude.ai 専用。外では「この画面ではAIコーチを使えません」と出る | Cloudflare Workers から Claude API を呼ぶ。APIキーはブラウザに置かない |

## 保存しているデータ(analyses の1件)

`title, dancer, song, date, createdAt, fps, start, end, duration, bpm, beatsCount, people,
scores{size, merihari, otohame, range, balance, sync, total}, dancers[], energy[], energyStep,
hits[], onBeat, grid[], gridOffset, beatTimes[], thumb(JPEGのdata URL), coach,
angles{fps, t0, n, dancers[][], mean[], energy[]}(比較用の関節角度), isRef(見本フラグ), refId, compare{…比較結果}`

動画そのものは保存していません(端末内で解析のみ)。

## 外部読み込み

- ONNX Runtime Web: `https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/ort.wasm.min.js`
  (同梱の wasm を `wasmBinary` で渡し、glue の .mjs のみ CDN から読む。シングルスレッド)
- supabase-js: `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.49.4/dist/umd/supabase.min.js`
- フォント: Google Fonts(Unbounded / Dela Gothic One / Zen Kaku Gothic New / IBM Plex Mono)

## ライセンス上の注意

YOLOv8 のモデルは Ultralytics の **AGPL-3.0** です。社外向けサービスとして公開する場合は、
ソース公開義務が生じるか、Ultralytics の商用ライセンスが必要になります。公開前に確認してください。

## スコアの基準

各指標の0〜100への換算式は仮置きです(`computeMetrics` 内の `sizeOf` / `meriOf` / `rangeOf` など)。
実際の練習動画で講師の評価と照らし合わせて調整してください。
