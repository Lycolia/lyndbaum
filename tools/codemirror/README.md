# codemirror.min.js

記事の本文の編集欄（`tools/js/src/edit-cm.js`）で使うCodeMirror6を、`pub/assets/js/codemirror.min.js`の1ファイルにまとめる。使う部品は`entry.js`で`window.CM6`に出す。

Markdownの読み方と色分けは、Lyndbaumの記法（`docs/markdown-syntax.md`）に合わせて`lyndbaum-markdown.js`で変えている（さつき記法のタグ、注釈、見出しのID、目次、続きを読む、脚注の参照。参照形式のリンクにしない）。さつき記法のタグは、編集画面がサーバーのタグ定義から渡す名前（textareaの`data-satsuki-tags`）だけを色分けする。

版は`package.json`で固定している。作り直すときは、このディレクトリで次を実行する。

```sh
npm ci
npm run build
```

部品を足したり版を上げたりしたら、`package.json`と`package-lock.json`もコミットする。`node_modules/`はコミットしない。

CodeMirrorはMITライセンス（https://codemirror.net/）。
