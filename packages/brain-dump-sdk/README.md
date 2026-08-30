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
```

`BRAIN_DUMP_ACCESS_TOKEN` はログインユーザーのJWTです。`service_role` キーは使用しないでください。アクセストークンの期限が切れた場合は更新が必要です。

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
