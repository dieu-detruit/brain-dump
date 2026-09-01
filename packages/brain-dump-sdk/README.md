# brain-dump-sdk

Brain Dumpへ外部のPythonコードやCLIからスレッドを追加するSDKです。PyPIへは公開せず、このGitリポジトリからインストールします。

## Install

```console
uv add "git+ssh://git@github.com/USER/brain-dump.git#subdirectory=packages/brain-dump-sdk"
```

安定したインストールには `--tag sdk-v0.1.0` または `--rev <commit>` を指定します。ローカル開発では次のように追加できます。

```console
uv add --editable /path/to/brain-dump/packages/brain-dump-sdk
```

## Configuration

```console
export BRAIN_DUMP_URL="https://PROJECT.supabase.co"
export BRAIN_DUMP_ANON_KEY="..."
export BRAIN_DUMP_ACCESS_TOKEN="..."
# またはヘッドレス運用:
export BRAIN_DUMP_REFRESH_TOKEN="..."
export BRAIN_DUMP_TOKEN_FILE="/home/USER/.config/brain-dump/refresh_token"
```

`BRAIN_DUMP_ACCESS_TOKEN` はログインユーザーのJWT、`BRAIN_DUMP_REFRESH_TOKEN` はその
refresh tokenです。`service_role` キーは使用しないでください。

### アクセストークンの自動更新

refresh token を渡すと `BrainDumpClient` が自動でログインを維持します
（JWTが切れたら `add_thread` がリフレッシュして再試行）。デーモン等の永続プロセスは
これで一度ログインするだけで動き続けられます。回転する refresh token は
`BRAIN_DUMP_TOKEN_FILE`（0600）に保存されます。

### 初回ログイン（一度だけ）

```console
python -c "from brain_dump_sdk import auth; print(auth.login('$BRAIN_DUMP_URL','$BRAIN_DUMP_ANON_KEY'))"
```

ブラウザでGoogleログイン → 表示された refresh token を保存します。Supabase側では
`PKCE flow` の有効化と、リダイレクトURL
`http://127.0.0.1:8881/callback` の登録が必要です。

## Python

```python
from brain_dump_sdk import BrainDumpClient

with BrainDumpClient.from_env() as client:
    thread = client.add_thread("リリースノートを書く", delegation="ai")
print(thread.id)
```

`delegation` は `"ai"`、`"colleague"`、または未指定（待機中）です。

## CLI

```console
brain-dump thread add --title "リリースノートを書く" --delegation ai
printf '%s' "調査結果を整理する" | brain-dump thread add --stdin --json
```
