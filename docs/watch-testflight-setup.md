# MacなしでWatchをTestFlightへ入れる

Appleの画面での登録とキーの発行はアカウント所有者が行う。
証明書・プロファイル作成、署名、アップロードはGitHub Actionsが行う。
Codemagicサービスへの登録は不要（公開CLIツールだけ使用）。
秘密鍵をチャット・リポジトリへ貼らない。

## 1. Bundle ID

[Identifiers](https://developer.apple.com/account/resources/identifiers/list)で次の2個を確認する。

|用途|Explicit Bundle ID|Capabilities|
|---|---|---|
|配布用コンテナ（作成済み）|`com.takafumi.brain-dump`|追加不要|
|Watchアプリ|`com.takafumi.brain-dump.watchkitapp`|Push Notificationsを有効化|

未作成なら「＋ → App IDs → App」。Descriptionは`Brain Dump Watch`。
PushのSSL証明書は作らない。通知用のAPNsキーを手順4で使う。

## 2. App Store Connectのアプリ登録

[Apps](https://appstoreconnect.apple.com/apps)で「＋ → 新規App」。

|項目|入力|
|---|---|
|プラットフォーム|iOS（Watch専用でもiOSの枠で登録）|
|名前|Brain Dump（使用済みならBrain Dump Takafumi等）|
|プライマリ言語|日本語|
|Bundle ID|`com.takafumi.brain-dump`|
|SKU|`brain-dump-watch`|
|ユーザアクセス|フルアクセス|

App Store公開への提出は不要。

## 3. ビルド用のAPIキー

[ユーザとアクセス](https://appstoreconnect.apple.com/access/integrations/api) →
「統合 / Integrations → App Store Connect API → チームキー / Team Keys」。
APIアクセスのリクエストが表示されたらアカウント所有者として実行する。
キー名`Brain Dump GitHub`、アクセス`Admin`で作成する（配布証明書とプロファイルも作成するため）。
Individual KeyではなくTeam Keyを使う。Issuer ID、Key IDを控え、秘密鍵`.p8`を保存する。
チームキーはチーム全体へのアクセスを持つ。

[GitHub Actions secrets](https://github.com/dieu-detruit/brain-dump/settings/secrets/actions)の
「New repository secret」で3個登録する。

|Name|Secret|
|---|---|
|`APP_STORE_CONNECT_ISSUER_ID`|Issuer ID（Team IDではない）|
|`APP_STORE_CONNECT_KEY_IDENTIFIER`|今作成したKey ID|
|`APP_STORE_CONNECT_PRIVATE_KEY`|ダウンロードした.p8をテキストで開き、BEGIN/END行を含む全文|

`CERTIFICATE_PRIVATE_KEY`は保存先への利用者の承認後、作業側で生成・登録する。利用者によるCSRや.p12作成は不要。
APPLE_TEAM_ID、APP_BUNDLE_ID、BRAIN_DUMP_WATCH_API_URLはGitHub Variables設定済み。

## 4. 通知用のAPNsキー

[Apple DeveloperのKeys](https://developer.apple.com/account/resources/authkeys/list)で「＋」。
名前`Brain Dump Push`、Apple Push Notifications serviceを有効にしてConfigure。
環境はProduction（TestFlight用）。Topic Specificを選べる場合は
`com.takafumi.brain-dump.watchkitapp`に限定する。登録後.p8を保存しKey IDを控える。
これは手順3のApp Store Connect APIキーとは別物。

[Supabase Edge Function Secrets](https://supabase.com/dashboard/project/zxiezbwnmqxccfvzarnj/functions/secrets)
に以下を登録する。

|Name|Value|
|---|---|
|`APNS_PRIVATE_KEY`|APNs用.p8の全文（改行を保持）|
|`APNS_KEY_ID`|APNs用Key ID|
|`APPLE_TEAM_ID`|`XLVLA9AY6A`|
|`WATCH_BUNDLE_ID`|`com.takafumi.brain-dump.watchkitapp`|

WATCH_CRON_SECRETとVaultの設定、Cron開始は作業側で行う。
APNsの準備を後回しにしてもアプリのインストールは進められるが、通知はまだ届かない。

## 5. ビルド・アップロード（作業側）

所有者が1〜3の完了を連絡したらSecrets名を確認し、対象コミットに
`watch-testflight-<日付>-<連番>`タグを付けてpushする。
`.github/workflows/watch-testflight.yml`が起動する。通常のbranch pushでは配布しない。
workflow_dispatchも定義しているが、default branchへの統合前はタグで起動する。
証明書の秘密鍵は再利用し、既存の証明書を失効させない。
build numberはGitHub run numberとattemptから生成する。

署名済みIPAをApp Store Connectへアップロードする。公開App Storeへの提出や外部ベータ審査はしない。
Appleの処理が完了したら内部テストへ追加する。
署名ファイル・秘密鍵はActions artifactへ保存しない。

## 6. 実機に入れる（利用者）

1. App Store Connect → 対象アプリ → TestFlight → 内部テストで`Internal`グループを作成。
2. 自分のApp Store Connectアカウントをテスターとして追加し、処理済みビルドを追加。
   輸出コンプライアンスが求められたら、実装で使う暗号（OSのHTTPS・Keychain）に沿って回答する。
3. WatchとペアリングしているiPhoneへTestFlightをインストール。
4. 招待をiPhoneで開いて承諾し、TestFlightのBrain Dumpで「インストール」。
   Watch専用アプリなのでWatchへインストールされる。
5. Watchのアプリ一覧からBrain Dumpを開き、通知を許可する。
6. 表示された8桁コードを、Googleログインした[Web版](https://brain-dump-one-phi.vercel.app/)のWatch接続画面で承認。
7. Thread一覧・切り替え・実行中Threadの再タップを確認し、通知有効化後は画面を閉じて継続回答を実機確認する。

## 参考

- [Apple: APIキー](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
- [Apple: 新規App登録](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
- [Apple: APNsキー](https://developer.apple.com/help/account/keys/create-a-private-key)
- [Apple: TestFlightインストール（watchOSの節）](https://testflight.apple.com/)
- [Codemagic CLIを他環境で使用](https://docs.codemagic.io/knowledge-codemagic/codemagic-cli-tools/)

2026-09-28更新: 利用者の明示承認後、証明書用秘密鍵を生成しGitHub Secretsへ保存済み。
Adminチームキーへの更新で配布証明書・プロファイル作成が成功。
Watch子IDのPush Notifications有効化を自動化し、配布コンテナのアプリ種別を修正。
[署名済みIPAの作成とアップロード](https://github.com/dieu-detruit/brain-dump/actions/runs/36371400329)が成功（1.0 / build 1）。
ビルド番号の自動採番を両アプリに反映し、[最終版1.0 / build 4.1](https://github.com/dieu-detruit/brain-dump/actions/runs/36371618891)もアップロード済み。内部テストではこちらを選ぶ。
Apple側の処理完了と内部テスターへの追加、実機導入は未確認。
APNs設定はSupabaseに保存済み。WATCH_CRON_SECRETをEdge/Vaultへ設定し、認証付き通知エンドポイントが200（outcomes空）を返すことを確認。
`enable-watch-cron.sql`を適用。端末未登録なのでAPNsへの実配送は未確認。
