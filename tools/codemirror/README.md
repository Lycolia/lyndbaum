# codemirror.min.js

記事の本文の編集欄（`tools/js/src/edit-cm.js`）で使うCodeMirror6を、`pub/assets/js/codemirror.min.js`の1ファイルにまとめる。使う部品は`entry.js`で`window.CM6`に出す。検索・置換の欄（`@codemirror/search`）も入れている。ブラウザのページ内検索は、CodeMirrorが画面に作っていない行に届かないため。閉じるカッコを足す機能（`@codemirror/autocomplete`の`closeBrackets`）も入れている。Markdownの記事で使う。

Markdownの読み方と色分けは、Lyndbaumの記法（`docs/markdown-syntax.md`）に合わせて`lyndbaum-markdown.js`で変えている（さつき記法のタグ、注釈、見出しのID、目次、続きを読む、脚注の参照。参照形式のリンクにしない）。目次は、いちばん外側の`[*toc]`だけの行にだけ色を付ける。Lyndbaumが対応しない記法（下線の見出し、インデントのコードブロック、`~~~`のフェンス、`*`と`+`のリスト、`***`と`___`の区切り線、字下げしない継続行、`>`の無い継続行、`__太字__`、タイトル付きのリンクと画像、いちばん外側で行頭に空白のある見出し・フェンス・リスト・引用・区切り線・表）は、記法として読まず、文章の色のままにする。`1)`のリスト、リストの中の`#`、内容の開始位置より深く字下げした`#`と`` ``` ``も同じ。`*`の太字と強調、表（各行を`|`で始める）、`- - -`（リストになる）、引用の途中の字下げした`>`の行、リストの項目の浅い字下げの続きの行も、`Markdown.pm`と同じ決まりで読む。引用とリストが次の行に続くかどうかの判定はLezerの設定では変えられないので、パーサーの中の関数（`skipContextMarkup`）を包んでいる。`@lezer/markdown`の版を上げたときは、`> a`の次の行の` > b`が引用の外になること、`- a`の次の行の` - b`が子のリストになることを確かめる。Markdownの記事の編集の補助（リストの記号を続けるEnter、Ctrl+B/I/K、URLを貼ったときのリンク、閉じるカッコ）も、ここに書いている。さつき記法のタグは、編集画面がサーバーのタグ定義から渡す名前（textareaの`data-satsuki-tags`）だけを色分けする。

版は`package.json`で固定している。作り直すときは、このディレクトリで次を実行する。

```sh
npm ci
npm run build
```

部品を足したり版を上げたりしたら、`package.json`と`package-lock.json`もコミットする。`node_modules/`はコミットしない。

CodeMirrorはMITライセンス（https://codemirror.net/）。
