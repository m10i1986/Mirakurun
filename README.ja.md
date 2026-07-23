[![Mirakurun](https://gist.githubusercontent.com/kanreisa/0ab27d7771e97edce5a24cc81b9b8ce6/raw/8e08d3d91390794b139ed593e3a834a8b41f651c/logo-mirakurun_2025-03-29.svg)](https://github.com/Chinachu/Mirakurun)

# Mirakurun

"Air" (開発中アプリのコードネーム) のために設計された日本のデジタルテレビチューナー API サーバーです。

[![npm version][npm-img]][npm-url]
[![npm downloads][downloads-image]][downloads-url]
[![Linux Build][azure-pipelines-img]][azure-pipelines-url]
[![tip for next commit](https://tip4commit.com/projects/43158.svg)](https://tip4commit.com/github/Chinachu/Mirakurun)
[![Backers on Open Collective](https://opencollective.com/Mirakurun/backers/badge.svg)](#backers)
[![Sponsors on Open Collective](https://opencollective.com/Mirakurun/sponsors/badge.svg)](#sponsors)

[**CHANGELOG**](CHANGELOG.md) | [**環境構築**](doc/Platforms.ja.md) | [**設定**](doc/Configuration.ja.md)

[**English**](README.md) | [**日本語**](README.ja.md)

## Docker

[![dockeri.co](https://dockeri.co/image/chinachu/mirakurun)][docker-url]

参照: 利用可能な[タグ一覧](https://hub.docker.com/r/chinachu/mirakurun/tags) (Docker Hub)

## 特徴

- HTTP RESTful API (Swagger / Open API 2.0)
- 高度なチューナープロセス管理
- 単一チューニングでの複数ストリーム配信
- ストリーム優先度
- MPEG-2 TS パーサー、フィルター
- リアルタイム EPG パーサー
- 様々なチューナーデバイスと混合環境に対応 (chardev, DVB / ISDB-T, ISDB-S, DVB-S2)
- 自動チャンネルスキャン
- Web UI
- IPTV サーバー (M3U8 プレイリスト, XMLTV)

#### 図: MPEG-2 TS ストリーム API の多様性

![](https://gist.githubusercontent.com/kanreisa/0ab27d7771e97edce5a24cc81b9b8ce6/raw/7409e229648e00b55404f9e8342dccb58bbb4ac4/mirakurun-fig-api-variety2.svg)

#### 図: ストリームフロー

![](https://gist.githubusercontent.com/kanreisa/0ab27d7771e97edce5a24cc81b9b8ce6/raw/7409e229648e00b55404f9e8342dccb58bbb4ac4/mirakurun-fig-flow-stream2.svg)

## 環境構築

👉 [**環境構築**](doc/Platforms.ja.md)

## 設定

👉 [**設定**](doc/Configuration.ja.md)

## Web UI

```sh
# 管理 UI
http://_your_mirakurun_ip_:40772/

# Swagger UI
http://_your_mirakurun_ip_:40772/api/debug
```

## クライアント実装

- [Rivarun](https://github.com/Chinachu/Rivarun)
- [BonDriver_Mirakurun](https://github.com/Chinachu/BonDriver_Mirakurun)
- Mirakurun クライアント ([組み込み](https://github.com/Chinachu/Mirakurun/blob/master/src/client.ts))
  - "Air" (開発コードネーム)
  - [Chinachu γ](https://github.com/Chinachu/Chinachu/wiki/Gamma-Installation-V2)
  - [EPGStation](https://github.com/l3tnun/EPGStation)

## 貢献

- [CONTRIBUTING.md](CONTRIBUTING.md)

## 寄付

- [Tip4Commit](https://tip4commit.com/github/Chinachu/Mirakurun) (BTC) - すべてのコミッターへ分配されます
- [Open Collective](https://opencollective.com/Mirakurun) (USD) - プール (使途未定)

## Discord コミュニティ

- 招待リンク: https://discord.gg/X7KU5W9

## Contributors

このプロジェクトは貢献してくださるすべての方々のおかげで成り立っています。
<a href="https://github.com/Chinachu/Mirakurun/graphs/contributors"><img src="https://opencollective.com/Mirakurun/contributors.svg?width=890&button=false" /></a>

## Backers

すべての Backer の皆様、ありがとうございます！ 🙏 [[Backer になる](https://opencollective.com/Mirakurun#backer)]

<a href="https://opencollective.com/Mirakurun#backers" target="_blank"><img src="https://opencollective.com/Mirakurun/backers.svg?width=890"></a>

## Sponsors

スポンサーになってこのプロジェクトをサポートしてください。あなたのロゴがウェブサイトへのリンクとともにここに表示されます。 [[スポンサーになる](https://opencollective.com/Mirakurun#sponsor)]

<a href="https://opencollective.com/Mirakurun/sponsor/0/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/0/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/1/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/1/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/2/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/2/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/3/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/3/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/4/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/4/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/5/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/5/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/6/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/6/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/7/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/7/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/8/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/8/avatar.svg"></a>
<a href="https://opencollective.com/Mirakurun/sponsor/9/website" target="_blank"><img src="https://opencollective.com/Mirakurun/sponsor/9/avatar.svg"></a>

## 著作権 / ライセンス

&copy; 2016- [kanreisa](https://github.com/kanreisa).

- コード: [Apache License, Version 2.0](LICENSE)
- ドキュメント: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- ロゴ: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

[npm-img]: https://img.shields.io/npm/v/mirakurun.svg
[npm-url]: https://npmjs.org/package/mirakurun
[downloads-image]: https://img.shields.io/npm/dm/mirakurun.svg?style=flat
[downloads-url]: https://npmjs.org/package/mirakurun
[azure-pipelines-img]: https://dev.azure.com/chinachu/Mirakurun/_apis/build/status/Chinachu.Mirakurun?branchName=master
[azure-pipelines-url]: https://dev.azure.com/chinachu/Mirakurun/_build/latest?definitionId=1&branchName=master
[docker-url]: https://hub.docker.com/r/chinachu/mirakurun
