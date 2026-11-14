# 自作JSのminify

`pub/assets/js/`の自作JS（`adiary.min.js`、`admin.min.js`、`edit.min.js`など）を作る。ソースは`src/`にあり、`build.js`が`src/*.js`を1本ずつterserでminifyして、`pub/assets/js/<名前>.min.js`とソースマップ（`<名前>.min.js.map`）を作る。ソースは公開ディレクトリの外にあるので、ソースマップにソースを入れている（`includeSources`）。著作権の表記（`(C)`の行）はminifyした後も残す。

版は`package.json`で固定している。ソースを直したら、このディレクトリで次を実行し、できた`.min.js`と`.min.js.map`もコミットする。

```sh
npm ci
npm run build
```

`src/`に足したファイルは、そのまま`build`の対象になる。読み込む側（スケルトンの`<script>`や`regist_js`）は`.min.js`を指す。

テーマやプラグインのJS、外部のもの（`colorpicker/`、Prismなど）は対象にしていない。asys.jsは`tools/asys/`、CodeMirrorは`tools/codemirror/`で作る。
