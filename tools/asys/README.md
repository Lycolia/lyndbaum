# asys.min.js

管理画面と、ログイン中の公開画面で使うasys.jsを、`pub/assets/js/asys.min.js`の1ファイルにまとめる。ソースは`src/`にあり、`package.json`の`build`に書いた順につなげてterserでminifyする。ソースマップ（`asys.min.js.map`）も一緒に作る。

`src/`は、adiaryから引き継いだ`asys.min.js.map`（2023-02-02の版）の`sourcesContent`から取り出したもの。asys.jsは<https://github.com/nabe-abk/asys.js>で別に開発が続いているが、これとは版が違う（つながる履歴は無い）。

版は`package.json`で固定している。作り直すときは、このディレクトリで次を実行する。

```sh
npm ci
npm run build
```

ソースを足したら、`package.json`の`build`のファイルの並びにも足す。版を上げたら、`package.json`と`package-lock.json`もコミットする。`node_modules/`はコミットしない。

asys.jsは(C)nabe@abk。この版はadiaryの一部として配布されていたもので、adiaryと同じAGPLv3（`src/20_PrefixStorage.js`はMIT）。この版はjQueryを含まない（jQueryを使わない形に書き直した）。
