# brain-dump-bridge

Brain Dump の**ローカル受け口・デーモン**。外部の汎用 push（JSON）を受け取り、
`brain-dump-sdk` で Thread を追加します。Supabase の知識・認証はすべて SDK 側に
あり、このパッケージは薄い HTTP リスナーです（`bridge → brain-dump-sdk`）。

## セットアップ（初回）

1. 設定ファイル `~/.config/brain-dump/env` を作る（0600推奨）:

   ```sh
   BRAIN_DUMP_URL=https://PROJECT.supabase.co
   BRAIN_DUMP_ANON_KEY=...
   ```

2. 一度だけログイン（ブラウザが開きます。Supabase側で **PKCE flow の有効化**と
   リダイレクトURL `http://127.0.0.1:8881/callback` の登録が必要）:

   ```sh
   uv run brain-dump-bridge auth-login
   # → ~/.config/brain-dump/refresh_token に保存（以後は自動更新）
   ```

3. 起動（手動）:

   ```sh
   uv run brain-dump-bridge serve     # 127.0.0.1:8877 で待受
   ```

   常駐にするなら systemd:

   ```sh
   bash install.sh                    # ~/.config/systemd/user へ symlink + enable
   systemctl --user status brain-dump-bridge
   ```

## API

```
POST /items    {"title": "何かやること"}        → 202 {"ok":true,"id":<thread_id>}
GET  /health                                    → 200 {"ok":true}
```

受けるのは `title` のみ（他フィールドは無視）。delegation は null で追加されます。

## 送信例（ai-watanabe-agent の `review.push_url` 等 `POST http://127.0.0.1:8877/items`）

```sh
curl -X POST http://127.0.0.1:8877/items \
  -H 'Content-Type: application/json' \
  -d '{"title":"matter port remap","url":"...","repo":"..."}'
```
