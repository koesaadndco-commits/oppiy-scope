# OPPIY SCOPE — 開発ルール

ダンス動画をブラウザ内で YOLOv8n-pose 解析し、6指標をスコア化して記録する静的Webアプリ。詳細は `README.md`。

## 構成(社内標準)

- **GitHub** = 司令塔:ソース・マイグレーション・変更履歴の起点
- **Cloudflare Workers** = 表側:`public/` の配信・SSL・AIコーチのAPI中継(`src/worker.js`、設定は `wrangler.jsonc`)
- **Supabase** = 裏側:DB(`analyses`)・Auth
- **Claude Code** = 開発担当

## 流れ

作業ブランチ → テスト → セルフレビュー → push → PR(テンプレート5項目を必ず埋める)→ Cloudflare プレビューURLで人が確認 → `main` へマージ。
`main` へ直接 push しない。「ちょっと直すだけ」も同じ流れ。

## push 前の必須チェック

- `.env*`・APIキー・Service Role Key を含めていない
- フロント(`public/index.html`)に書くのは Supabase の anon(publishable)key のみ
- Claude API はブラウザから呼ばない。必ず Workers 経由
- 全テーブルで RLS 有効、本人の記録しか読めない
- 動画そのものは保存しない(端末内で解析のみ)

## ファイル

| パス | 役割 |
|---|---|
| `public/index.html` | アプリ本体(HTML/CSS/JS 1枚) |
| `public/yolov8n-pose.onnx` | 姿勢推定モデル(AGPL-3.0。社外公開前にライセンス確認) |
| `public/ort-wasm-simd-threaded.wasm` | ONNX Runtime Web 1.20.1 |
| `src/worker.js` | Worker:静的配信 + AIコーチ API。Secret `ANTHROPIC_API_KEY` を Cloudflare 側に登録 |
| `wrangler.jsonc` | Workers 設定(assets = `public/`) |
| `supabase/migrations/` | DBマイグレーション(本番は管理画面から直接変更しない) |

## 環境

- Development: 作業ブランチ / Supabase ブランチDB
- Preview: PR / Cloudflare プレビューURL(Workers Builds の非本番ブランチ)/ Supabase 検証DB
- Production: `main` のみ / Supabase 本番

本番データを開発・確認環境に持ち込まない。検証はダミーデータ。

## 作業の分担(最優先ルール)

**Claude Code が自分でできることは、確認せず全部自分でやる。** 担当者に頼むのは、本当に担当者の画面でしか出来ないことだけ。頼むときは「何を・どこで・何回クリックか」を1回でまとめて書き、同じことを何度も聞き返さない。

### Claude Code が自分でやる(聞かない)
- ブランチ作成、コミット、push、PR 作成(テンプレート記入込み)、`main` 以外のブランチ操作
- `main` ブランチの初回作成(空リポジトリの立ち上げ時)
- Supabase:マイグレーション作成と適用、RLS、テーブル変更、セキュリティ診断の確認(接続済み MCP で可能な範囲)
- Cloudflare:Workers のコード作成、接続済み MCP で可能な操作
- テスト、セルフレビュー、README / CLAUDE.md の更新
- 動作確認用のダミーデータ投入

### 担当者にしか出来ないこと(これだけ頼む)
- Cloudflare ダッシュボードでの GitHub 連携、本番ブランチ設定、環境変数(Secrets)の登録
- Supabase ダッシュボードでのユーザー追加、セルフ登録オフ、Service Role Key を使う操作
- Claude API など有料サービスのキー発行と利用上限の設定
- 課金が発生する判断(有料プランへの変更)
- PR の最終承認とマージ(プレビューURLでの実画面確認)

### 聞き方のルール
- 「〜していいですか?」で止めない。できるならやる。できないなら「ここだけお願いします」と手順を1回で出す
- 環境の制約(ネットワーク遮断・権限ブロック)で出来なかったときは、何が出来なかったかを一言で言い、代わりに担当者がやる最短手順を出す
