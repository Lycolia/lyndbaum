// pub/assets/js/codemirror.min.jsの元（本文の編集欄、edit-cm.jsで使う）
// 使う部品をwindow.CM6にまとめて出す。作り直すときはREADME.mdを見る
import {EditorView, keymap} from "@codemirror/view";
import {EditorState, Compartment, Prec} from "@codemirror/state";
import {defaultKeymap, history, historyKeymap, insertNewline} from "@codemirror/commands";
import {syntaxHighlighting, defaultHighlightStyle} from "@codemirror/language";
import {markdown} from "@codemirror/lang-markdown";
import {html} from "@codemirror/lang-html";
import {lyndbaumMarkdown, lyndbaumHighlight} from "./lyndbaum-markdown.js";

window.CM6 = {
	EditorView, keymap,
	EditorState, Compartment, Prec,
	defaultKeymap, history, historyKeymap, insertNewline,
	syntaxHighlighting, defaultHighlightStyle,
	markdown, html,
	lyndbaumMarkdown, lyndbaumHighlight
};
