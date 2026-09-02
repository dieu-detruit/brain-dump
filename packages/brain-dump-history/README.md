# brain-dump-history

Brain DumpのDB変更をRealtimeで検知し、独立したローカルGit repositoryへ履歴データだけを書き出す常駐ノードです。Realtime切断中の変更も、DBの連番IDを使った起動時同期で回収します。

```sh
export BRAIN_DUMP_URL=https://PROJECT.supabase.co
export BRAIN_DUMP_ANON_KEY=...
export BRAIN_DUMP_REFRESH_TOKEN=...

uv run brain-dump-history watch \
  --repository /home/genki/my-oss/brain-dump-history \
  --token-file ~/.config/brain-dump/refresh_token
```

`BRAIN_DUMP_REFRESH_TOKEN`の代わりに`BRAIN_DUMP_TOKEN_FILE`を指定できます。bridgeと同じrefresh tokenを共有しないでください。最初にhistory専用tokenを発行します。

```sh
uv run brain-dump-history login \
  --repository /home/genki/my-oss/brain-dump-history \
  --token-file ~/.config/brain-dump/history_refresh_token \
  --manual-code --no-browser
```

ブラウザが常駐ノードと別の端末にある場合は、ログイン後に表示されるcallback URLの`code`値をプロンプトへ貼り付けます。

## 常駐サービス

`~/.config/brain-dump/env`に`BRAIN_DUMP_URL`と`BRAIN_DUMP_ANON_KEY`を設定し、history専用refresh tokenを上の手順で用意したあと、次でuser serviceを開始します。

```sh
./install.sh
```

サービス定義はrepositoryを`~/my-oss/brain-dump-history`、コードを`~/my-oss/brain-dump`に置く前提です。

`sync`を指定すると一度同期して終了します。同期で差分が生じるたび、history repositoryの`data/`だけを自動commitします。`--no-commit`でcommitを無効化できます。

出力は現在のThread一覧、append-onlyな変更ログ、実行区間の現在値、Thread別集計です。

- `data/threads.json`
- `data/change-log.jsonl`
- `data/execution-sessions.jsonl`
- `data/time-summary.json`
