# Brain Dump for Apple Watch

watchOS 10以降向け。現在のThreadの表示、「続けている」、既存Threadへの切り替えを提供します。
Web版の「Watch」から一度登録すると、Watch単独でAPIに接続できます。

## 現在の検証範囲

Linux側でWeb・Edgeのテスト、独立PostgreSQLでDB動作を検証します。
Swift/Xcodeのビルド、Codemagicの実行、署名・TestFlight導入、実機での通知配送は別途確認が必要です。
ソースが存在することと実機動作の確認は別です。実施結果は `../docs/watch-rollout.md` を参照してください。

## Macなし・Apple登録なしでビルド

この公開リポジトリでは `.github/workflows/watch.yml` が標準macOSランナーでビルドとXCTestを実行します。
`feat/watch-app` へのWatch関連変更のpushで起動します。
Appleの証明書・有料加入・Codemagic登録は不要です。
シミュレーターのKeychain検証には、証明書不要のad hoc署名を使います。
続いてWatch-only配布コンテナを未署名archiveし、Watchアプリが内包されることを確認します。
実機へインストールできるIPAのexportは署名設定後に行います。

Codemagicを使う場合はリポジトリを接続し、ルートの `codemagic.yaml` の `watch-simulator` を手動実行します。
初期設定はXcode 26.3 / M2です。

シミュレーター端末はインストール済みのwatchOS runtimeから選びます。
XcodeGenはCIでインストールするため、初回は使用バージョンをログで確認し、成功した版を固定してください。

Macが利用可能なら、リポジトリルートで `bash brain-dump-watch/scripts/test.sh` を実行できます。

## TestFlight

必要な登録:

- Apple Developer Programと配布コンテナ用App ID（例 `dev.example.braindump`）、Watch用App ID（同じIDに `.watchkitapp` を追加）。Watch側でPush Notificationsを有効化する。
- App Store Connectのアプリと内部テスターグループ `Internal`。
- Apple Distribution証明書、配布コンテナとWatch両方のApp ID用App Store provisioning profiles。
- CodemagicのApp Store Connect連携名 `brain-dump`。
- Codemagicの環境変数グループ `brain-dump-watch` に `APP_BUNDLE_ID`、`APPLE_TEAM_ID`、`BRAIN_DUMP_WATCH_API_URL`。
- `BRAIN_DUMP_WATCH_API_URL` は `https://PROJECT.supabase.co/functions/v1/watch-api`。

`watch-testflight` は手動実行専用です。pushで自動配布しません。
署名ファイルはCodemagicの署名管理へ登録してください。`xcode-project use-profiles` が作る
`/Users/builder/export_options.plist` を使ってexportします。
Watch-onlyのarchive/exportは最初のMac実行で検証してください。一般的なiOSアプリのビルド成功で代用しないでください。

このアプリの通知tokenはTestFlightではproduction、開発ビルドではsandboxとして登録します。
Appleの証明書・APNs秘密鍵・Supabase service role keyはアプリやリポジトリへ含めません。

## 操作

Watchを開き、8桁コードをWeb版「Watch」に入力します。コードは5分間有効です。
Watchで通知を許可し、Web画面に「通知登録済み」と表示されることを確認してください。
画面を開いている間は15秒ごとに最新状態へ更新します。
通知の「続けている」はバックグラウンドで回答し、「切り替える」はアプリを開きます。
通信断では「未更新」と表示し、状態を再取得するまで変更しません。
不要になったWatchはWeb版で解除できます。

初版の通知は確認から55分で送信対象になり、60分で回答期限になります。
APNs受理は配送保証ではありません。集中モードや通信状態で届かないことがあります。

配布時はコードを持たない `BrainDumpContainer` をiOS archiveとして出力し、Watchアプリを同梱します。
これはWatch-only配布用のラッパーで、利用者が操作するiPhoneアプリは作りません。
APNs側の `WATCH_BUNDLE_ID` は `${APP_BUNDLE_ID}.watchkitapp` と一致させてください。

現在の提出SDK要件に合わせてXcode 26.3を指定しています。
[Appleの要件](https://developer.apple.com/news/?id=ueeok6yw)・[Codemagicの環境](https://docs.codemagic.io/specs-macos/xcode-26-3/)を参照してください。
