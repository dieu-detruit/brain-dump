# Brain Dump

頭の中のすべてをThreadとして置き、「自分がいま実行するもの」を常に一つだけ選ぶための個人用PWAです。

## 現在できること

- Threadの追加・削除
- `寝かせる / AI / 他の人`への委譲状態の指定
- 自分が実行するThreadを一つだけ選択（AIや他の人との共同進行も表現可能）
- Googleログインとユーザーごとの完全なデータ分離
- 複数端末および外部追加のリアルタイム反映
- PWAとしてスマートフォン・Chromeへインストール
- Supabase未設定時はブラウザのlocalStorageでデモ利用

## ローカル起動

```sh
pnpm install
pnpm dev
```

`pnpm dev`では認証なしのデモモードで起動し、データはそのブラウザだけに保存されます。Supabase認証をローカルで確認するときは`VITE_DEMO_MODE=false pnpm dev`で起動してください。

## Supabaseのセットアップ

1. SupabaseでProjectを作成する
2. Supabase CLIでリンクし、migrationを反映する

   ```sh
   pnpm dlx supabase link --project-ref YOUR_PROJECT_REF
   pnpm dlx supabase db push
   ```

3. Authentication > ProvidersでGoogleを有効にする
4. Google Cloud Console側のAuthorized redirect URIへ、Supabase画面に表示されるcallback URLを登録する
5. `.env.example`を`.env.local`へコピーし、Project URLとanon keyを設定する
6. Supabase AuthenticationのURL Configurationに、本番URLとローカルの`http://localhost:5173`を登録する

## デプロイ

SupabaseはDB/Auth/API/Realtimeに利用します。静的SPAのホスティング機能は提供しないため、フロントエンドはVercel、Cloudflare Pages、Netlifyなどへ`pnpm build`の成果物`dist/`を配置してください。

必要な環境変数:

```text
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
```

SPAのフォールバックとして、すべてのパスを`/index.html`へ向けてください。現在ルーティングはないため、ルートURLでは追加設定なしでも動作します。

## 外部ツールからThreadを追加する

ユーザーのアクセストークンを使い、通常のREST APIで`threads`へinsertするか、`add_thread` RPCを呼べます。service role keyをブラウザやGitHub Actionsへ直接置かないでください。

```sh
curl -X POST "$SUPABASE_URL/rest/v1/rpc/add_thread" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $USER_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"thread_title":"PR #123をレビューする","assigned_to":null}'
```

将来的には、GitHub App/Webhookを受けるSupabase Edge Functionを追加し、そこで対象ユーザーを特定してこのRPC相当のinsertを行う構成が安全です。

## データモデル

- `threads`: タイトルと委譲先（`null | ai | colleague`）
- `brain_state`: ユーザーにつき一行、`executing_thread_id`のみを保持
- RLSにより、認証ユーザーは自分の行だけ読み書き可能

## DBの変化をローカルGitで追う

最新のmigrationを反映すると、変更履歴とThread別の実行時間がDBへ記録されます。subscribe・ローカルへの書き出しを行うコードは`../packages/brain-dump-history`に置き、履歴データとそのGit履歴だけを独立した`brain-dump-history` repositoryで管理します。
