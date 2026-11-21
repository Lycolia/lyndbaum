// pub/assets/js/codemirror.min.jsの元（本文の編集欄、edit-cm.jsで使う）
// 使う部品をwindow.CM6にまとめて出す。作り直すときはREADME.mdを見る
import {EditorView, keymap} from "@codemirror/view";
import {EditorState, Compartment, Prec} from "@codemirror/state";
import {defaultKeymap, history, historyKeymap, insertNewline, indentMore, indentLess} from "@codemirror/commands";
import {syntaxHighlighting, defaultHighlightStyle, indentUnit} from "@codemirror/language";
import {search, searchKeymap, openSearchPanel, closeSearchPanel, searchPanelOpen} from "@codemirror/search";
import {markdown} from "@codemirror/lang-markdown";
import {html} from "@codemirror/lang-html";
import {lyndbaumMarkdown, lyndbaumHighlight, lyndbaumEditKeys, lyndbaumPasteURL, lyndbaumCloseBrackets, lyndbaumListIndent} from "./lyndbaum-markdown.js";

window.CM6 = {
	EditorView, keymap,
	EditorState, Compartment, Prec,
	defaultKeymap, history, historyKeymap, insertNewline, indentMore, indentLess,
	syntaxHighlighting, defaultHighlightStyle, indentUnit,
	search, searchKeymap, openSearchPanel, closeSearchPanel, searchPanelOpen,
	markdown, html,
	lyndbaumMarkdown, lyndbaumHighlight, lyndbaumEditKeys, lyndbaumPasteURL, lyndbaumCloseBrackets, lyndbaumListIndent
};
