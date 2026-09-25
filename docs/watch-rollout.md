# Watch版の検証・導入

## 実行済みと未実行

- ローカルWebのテスト・lint・build: 実行可能。最新結果は実装報告を参照。
- DenoのAPI・APNs署名/応答テスト: 実行可能。
- PostgreSQL 17で既存migrationからの追加と操作・認証・通知テスト: 実行可能。
- Supabaseの実際のAuthゲートウェイ・Vault・Cron・Edge runtime: 未デプロイ。
- Swift/Xcodeのコンパイル・XCTest（8件）・未署名watch-only archive: GitHub Actionsで成功。署名付きexportは未実行。
- TestFlight導入・実機通知・バックグラウンド回答: 未実行。

## ローカル検証

```sh
cd brain-dump
pnpm test
pnpm lint
pnpm build
deno test supabase/functions/
deno check supabase/functions/watch-api/index.ts supabase/functions/watch-notifications/index.ts
```

`supabase/tests/run-postgres.sh` は新しい一時コンテナを作り、PostgreSQL本体でテストして削除します。
Dockerアクセスが必要です。既存DB・本番DBには接続しません。
テストの `auth.uid()`・ユーザーテーブルはSupabase互換の最小fixtureです。Authサービス全体の統合検証ではありません。

## 導入順序

1. 開発用Supabaseへ既存migrationに続けて20260924の3本を適用する。
2. Web更新前に `execution_snapshot` / `apply_execution_command` が動くことを確認する。
3. `watch-api` と `watch-notifications` を配置する。
   端末トークンはSupabase JWTではないため、関数設定の `verify_jwt=false` を使う。
   API自身が経路ごとに認証する。Cron用関数は専用Bearer secretを検証する。
4. APNsの本番設定前に、Edge runtimeからAPNsへのHTTP/2疎通を検証する。
   `scripts/check-apns-transport.ts` は非認証の拒否応答を確認する検証用コード。アプリ配送の証拠にはしない。
5. Webを更新し、Watchの証明書不要CIを実行する。
6. Apple登録と署名設定を済ませてTestFlightから導入する。
7. Webで紐づけ、Watchの通知許可・token登録を確認する。
8. Edge SecretsとVault設定後、`supabase/scripts/enable-watch-cron.sql` をSQL Editorで適用する。
9. 以下の実機受け入れ試験を実施する。

## Secrets

Edge FunctionsのSecretsに設定するもの:

| 名前 | 値 |
|---|---|
| `WATCH_CRON_SECRET` | 暗号学的乱数32byte以上から作るsecret |
| `APPLE_TEAM_ID` | Apple Team ID |
| `APNS_KEY_ID` | APNsキーID |
| `APNS_PRIVATE_KEY` | Appleから取得した `.p8` の内容 |
| `WATCH_BUNDLE_ID` | 署名したWatchアプリのbundle IDと完全一致 |

`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` はSupabaseが提供する関数側環境変数を使います。
ブラウザーとWatchにはservice role keyを渡しません。

Vaultに `watch_notifications_url`（送信関数のHTTPS URL）と `watch_cron_secret`（上と同じsecret）を登録します。
SecretをSQLファイル、CIログ、スクリーンショットへ保存しないでください。

## 実機受け入れ試験

- [ ] WatchのモデルとOSが対応下限を満たす。
- [ ] TestFlightでWatchへ導入できる。
- [ ] 初回コードをWebで承認し、Watchで一覧を取得できる。
- [ ] PCで開始した作業が、両アプリを閉じても55分後にWatchへ通知される。
- [ ] 通知の「続けている」でWebの確認時刻が更新される。
- [ ] Watchで切り替えた結果がWebへ反映される。
- [ ] 旧通知・同じ通知の二重回答で、別Threadや期限が変更されない。
- [ ] 60分を過ぎて未回答なら終了し、期限後の回答で復活しない。
- [ ] 通信断からの回答は成功表示されず、アプリの更新で状態を確認できる。
- [ ] アプリ再起動後も紐づけは維持される。
- [ ] Webで解除するとWatchからアクセスできず、通知対象から外れる。

通知の集中モード・端末ロック状態・ネットワーク条件を記録します。実時間試験は省略しません。

## 運用と停止

Cron停止: `select cron.unschedule('brain-dump-watch');`
端末の停止: Web版からそのWatchを解除する。
データを消すrollbackは不要です。旧Webの継続確認は誤操作防止のため再読み込みを求めます。既存Threadと履歴は維持します。

キューの `configuration_error` はAPNsの鍵・topic・環境を確認してください。
修正後に期限内の該当行を `pending` に戻すと再試行できます。期限後の通知を再送しないでください。
APNsの410/BadDeviceTokenでは登録tokenを無効化します。Watchを開いてtokenを再登録します。

個人利用向けの紐づけ作成上限は全体で60回/時です。信頼できる送信元IPの前提を置かず、永続DBで制限します。
制限に達した場合は時間を置いて再試行してください。既に登録した端末の操作には影響しません。

## 今回の実装上の判断

- worktreeは作らず現在の作業ディレクトリを使用。追加の権限で `feat/watch-app` ブランチへcommit・push済み。
- DB検証はSupabase全体の起動に代えて、独立PostgreSQLと最小Auth fixtureを使用。実際のAuth/Vault/Cronの統合確認は導入時に必要。
- 紐づけ開始は送信元IPを信用せず全体60回/時で制限。第三者が上限を使い切った場合は新規登録を待つ必要がある。
- セッションを指定しない旧確認RPCは再読み込みを要求。古いWebキャッシュからの誤確認を防止するため。
- Xcode 26.3とWatch-only配布コンテナを採用。動作下限はwatchOS 10のまま。署名は親App IDとWatch App IDの両方が必要。
- 公開リポジトリの標準GitHub Actions macOSランナーで未署名ビルド・XCTestを実行する。最初の検証にCodemagic登録やApple有料加入は不要。署名と実機配送は別途確認する。

## ローカル確認結果（2026-09-24）

Web: Vitest 3件、lint、production buildが成功。
Edge: Deno 12件、lint、両入口の型チェックが成功。
DB: 新規PostgreSQL 17への全migration、実行・端末・通知・紐づけ復帰・旧確認拒否の回帰テスト、
確認と終了・同時切り替えの複数接続テストが成功。
YAML/JSON/entitlementsの構文読み込みとshell syntaxチェックも成功。

これらはネイティブコンパイル、TestFlight配布、実機配送の確認を含みません。

追加の疎通確認: ローカルDenoからAPNs sandboxへ接続し、`403 MissingProviderToken` を受信。
ネットワーク制限を外した検証でAPNsまで到達したことは確認できました。
認証・配送の成功ではなく、SupabaseのEdge runtimeからの疎通確認も別途必要です。

## Mac環境での確認結果（2026-09-25）

[GitHub Actionsの実行](https://github.com/dieu-detruit/brain-dump/actions/runs/36075053474)で、
Xcode 26.3 / XcodeGen 2.46.0によるWatchアプリのコンパイルとXCTest 8件が成功。
Keychain実保存、古い401応答からの保護、紐づけ復帰、通知登録再試行、通信失敗、通知payloadを検証。
最初の実行では署名を完全に無効化してKeychainテストが失敗したため、
Appleの証明書を必要としないシミュレーター用ad hoc署名へ変更して再検証した。
これは実機の署名、APNs配送、バックグラウンド実行の確認を含まない。

[配布構成を含む最終実行](https://github.com/dieu-detruit/brain-dump/actions/runs/36075441723)でもXCTest 8件が成功。
`BrainDumpContainer` の未署名iOS archive生成に成功し、生成物の `Watch/BrainDumpWatch.app` と実行ファイルの存在を確認。
配布コンテナの画面方向・起動画面についてXcode警告が残るため、実際の署名exportとApp Store Connectの検証時に確認する。

## 利用者が次に行うこと

1. [Apple Developer Program](https://developer.apple.com/jp/programs/enroll/)へ個人として登録する。年99米ドル、現地通貨の請求額は登録画面で確認する。本人確認と支払いは本人が行う。
2. 登録完了後にアプリID・署名・APNsキーの設定を進める。最初のビルド検証用のCodemagic登録は不要。
3. サーバー配置と署名ビルドが済んだら、TestFlightで導入して上記の実機受け入れ試験を行う。
