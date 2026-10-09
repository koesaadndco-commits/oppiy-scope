# OPPIY SCOPE — 開発ルール

ダンス動画をブラウザ内で YOLOv8n-pose 解析し、6指標をスコア化して記録する静的Webアプリ。詳細は `README.md`。

## 構成(社内標準)

- **GitHub** = 司令塔:ソース・マイグレーション・変更履歴の起点
- **Cloudflare Pages / Workers** = 表側:配信・SSL・AIコーチのAPI中継
- **Supabase** = 裏側:DB(`analyses`)・Auth
- **Claude Code** = 開発担当

## 流れ

作業ブランチ → テスト → セルフレビュー → push → PR(テンプレート5項目を必ず埋める)→ Cloudflare プレビューURLで人が確認 → `main` へマージ。
`main` へ直接 push しない。「ちょっと直すだけ」も同じ流れ。

## push 前の必須チェック

- `.env*`・APIキー・Service Role Key を含めていない
- フロント(`index.html`)に書くのは Supabase の anon(publishable)key のみ
- Claude API はブラウザから呼ばない。必ず Workers 経由
- 全テーブルで RLS 有効、本人の記録しか読めない
- 動画そのものは保存しない(端末内で解析のみ)

## ファイル

| パス | 役割 |
|---|---|
| `index.html` | アプリ本体(HTML/CSS/JS 1枚) |
| `yolov8n-pose.onnx` | 姿勢推定モデル(AGPL-3.0。社外公開前にライセンス確認) |
| `ort-wasm-simd-threaded.wasm` | ONNX Runtime Web 1.20.1 |
| `supabase/migrations/` | DBマイグレーション(本番は管理画面から直接変更しない) |

## 環境

- Development: 作業ブランチ / Supabase ブランチDB
- Preview: PR / Cloudflare プレビューURL / Supabase 検証DB
- Production: `main` のみ / Supabase 本番

本番データを開発・確認環境に持ち込まない。検証はダミーデータ。
