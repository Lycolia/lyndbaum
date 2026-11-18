//##############################################################################
// LyndbaumのMarkdownに合わせた読み方と色分け（編集欄、edit-cm.js）
//##############################################################################
// CodeMirrorのMarkdown（Lezer、CommonMark）は、[…]をすべて参照形式のリンクとして読む。
// Lyndbaumは参照形式のリンクに対応せず、[…]はさつき記法のタグ（知っている名前のときだけ）
// なので、docs/markdown-syntax.mdに合わせて読み方を変える。
// Lyndbaumが対応しない記法（下線の見出し、インデントのコード、~~~、*と+のリスト、***と___の
// 区切り線、継続行、__太字__、タイトル付きのリンク）も、記法として読まない。
//
// lyndbaumMarkdown(tag_names) … CM.markdown()の引数（tag_namesはサーバーのタグ定義のキー）
// lyndbaumHighlight            … 足した記法の色分け
// lyndbaumEditKeys             … リストの記号を続けるEnter、太字・強調・リンクのショートカット（Ctrl+B/I/K）
// lyndbaumPasteURL             … 文字を選んでURLを貼ったら、[文字](URL)にする
// lyndbaumCloseBrackets        … ( [ を打ったら閉じるカッコを足す
import {Table, Strikethrough, TaskList, InlineContext} from "@lezer/markdown";
import {Tag, tags as t} from "@lezer/highlight";
import {HighlightStyle, syntaxTree} from "@codemirror/language";
import {EditorSelection, EditorState, Prec} from "@codemirror/state";
import {EditorView, keymap} from "@codemirror/view";
import {markdownLanguage, insertNewlineContinueMarkupCommand, deleteMarkupBackward} from "@codemirror/lang-markdown";
import {closeBrackets, closeBracketsKeymap} from "@codemirror/autocomplete";

const tag = {
	name:   Tag.define(),	// タグの名前（image:S など）
	mark:   Tag.define(),	// タグの [ ] : 、注釈の (( ))
	quiet:  Tag.define(),	// 見出しのID、目次、続きを読む
	note:   Tag.define()	// 脚注の参照
};

export const lyndbaumHighlight = HighlightStyle.define([
	{ tag: tag.name,  color: "#708" },
	{ tag: tag.mark,  color: "#999" },
	{ tag: tag.quiet, color: "#999" },
	{ tag: tag.note,  color: "#708" }
]);

const C_BACKSLASH = 92, C_OPEN = 91, C_CLOSE = 93, C_PAREN = 40, C_PAREN_CLOSE = 41,
      C_SPACE = 32, C_TAB = 9, C_COLON = 58, C_STAR = 42, C_PLUS = 43, C_UNDER = 95, C_TILDE = 126;

//------------------------------------------------------------------------------
// ●[ から対応する ] の次の位置（無ければ -1）。\[ \] は飛ばす
//------------------------------------------------------------------------------
function find_close(cx, pos) {
	let depth = 0;
	for (let i = pos; i < cx.end; i++) {
		const c = cx.char(i);
		if (c == C_BACKSLASH) { i++; continue; }
		if (c == C_OPEN)  depth++;
		if (c == C_CLOSE && --depth == 0) return i + 1;
		if (c == 10 && depth == 0) return -1;
	}
	return -1;
}

//------------------------------------------------------------------------------
// ●タグの名前の判定（Satsuki.pmのspecial_commandと同じ）
//------------------------------------------------------------------------------
// 名前の長さを返す（タグでなければ0）
function tag_name_length(body, names) {
	if (/^&[^#]/.test(body)) return names.has('filter') ? 1 : 0;	// [&URL]
	if (body[0] == '$') return 1;					// [$変数]
	if (/^\*toc\d*(?::|$)/.test(body)) return -1;			// [*toc]（Markdownパーサーが処理する）
	// \: は区切りにしない
	const parts = body.replace(/\\[\[\]]/g, 'xx').replace(/\\:/g, '\x00\x00').split(':');
	let cmd = parts.shift();
	while (parts.length && names.has(cmd + ':' + parts[0].replace(/\x00\x00/g, '\\:'))) cmd += ':' + parts.shift();
	return names.has(cmd.replace(/\x00\x00/g, '\\:')) ? cmd.length : 0;
}

//------------------------------------------------------------------------------
// ●タグの要素を作る（中のタグも子として読む）
//------------------------------------------------------------------------------
function tag_element(cx, from, to, names, verb) {
	const open  = verb ? 2 : 1;
	const body  = cx.slice(from + open, to - open);
	const len   = tag_name_length(body, names);
	if (len == 0) return null;
	if (len < 0) return cx.elt('LyndbaumToc', from, to);

	const ch = [ cx.elt('LyndbaumTagMark', from, from + open) ];
	const name_end = from + open + len;
	ch.push(cx.elt('LyndbaumTagName', from + open, name_end));
	if (!verb) {
		const url = (body[0] == '&' || body[0] == '$');	// [&URL]の : はURLの一部
		for (let i = name_end; i < to - 1; i++) {
			const c = cx.char(i);
			if (c == C_BACKSLASH) { i++; continue; }
			if (c == C_COLON && !url) { ch.push(cx.elt('LyndbaumTagMark', i, i + 1)); continue; }
			if (c != C_OPEN) continue;
			const end = find_close(cx, i);
			if (end < 0 || end > to - 1) continue;
			const inner = tag_element(cx, i, end, names, false);
			if (inner) ch.push(inner);
			i = end - 1;
		}
	}
	ch.push(cx.elt('LyndbaumTagMark', to - open, to));
	return cx.elt('LyndbaumTag', from, to, ch);
}

//------------------------------------------------------------------------------
// ●[ で始まるもの：タグ、[[…]]、見出しのID、脚注の参照
//------------------------------------------------------------------------------
function bracket_parser(names) {
	return function(cx, next, pos) {
		if (next != C_OPEN) return -1;
		const c1 = cx.char(pos + 1);

		// [[…]]（中は引数を区切らない）
		if (c1 == C_OPEN) {
			const m = /^\[\[(.*?)\]\]/.exec(cx.slice(pos, cx.end));
			if (m && m[1].indexOf("\n") < 0) {
				const elt = tag_element(cx, pos, pos + m[0].length, names, true);
				if (elt) return cx.addElement(elt);
			}
			return -1;
		}

		const end = find_close(cx, pos);
		if (end < 0) return -1;
		const body = cx.slice(pos + 1, end - 1);

		// 脚注の参照 [^id]
		if (/^\^[^\]\s]+$/.test(body)) return cx.addElement(cx.elt('LyndbaumFootnote', pos, end));

		// 見出しのID：空白の後ろで、行末まで空白だけ
		if (body[0] == '#' && /^#[^\x00-\x20\]]+$/.test(body)) {
			const before = pos > cx.offset ? cx.char(pos - 1) : -1;
			if ((before == C_SPACE || before == C_TAB) && /^[ \t]*$/.test(cx.slice(end, cx.end)))
				return cx.addElement(cx.elt('LyndbaumHeadingId', pos, end));
			return -1;
		}

		if (cx.char(end) == C_PAREN) return -1;	// [文字](URL) はリンク
		const elt = tag_element(cx, pos, end, names, false);
		return elt ? cx.addElement(elt) : -1;
	};
}

//------------------------------------------------------------------------------
// ●参照形式のリンク、タイトル付きのリンクにしない
//------------------------------------------------------------------------------
// ] の直後が ( でないとき、(URL "タイトル") のときは、開いた [ を取り下げて普通の文字にする
// （画像の ![ も同じ）。タイトルは、URLの後ろの空白に続く " か ' で見分ける
const LINK_TITLE = /^\([ \t]*(?:<[^<>\n]*>|(?:[^\s()\\]|\\.|\((?:[^\s()\\]|\\.)*\))*)[ \t]+["']/;
function close_bracket(cx, next, pos) {
	if (next != C_CLOSE) return -1;
	if (cx.char(pos + 1) == C_PAREN && !LINK_TITLE.test(cx.slice(pos + 1, cx.end))) return -1;
	const a = cx.findOpeningDelimiter(InlineContext.linkStart);
	const b = cx.findOpeningDelimiter(InlineContext.imageStart);
	const i = (a == null) ? b : (b == null) ? a : Math.max(a, b);
	if (i == null) return -1;
	for (const e of cx.takeContent(i)) cx.addElement(e);
	return pos + 1;
}

//------------------------------------------------------------------------------
// ●注釈 ((…))
//------------------------------------------------------------------------------
// 閉じる位置は、Markdown.pmと同じ正規表現で開くときに決める（中の ( ) は1段まで）。
// Markdown.pmの[^()]++（強欲な量指定子）はJSで書けない。[^()]+にすると、閉じる ))の無い
// 段落で文字の区切り方を総当たりしてタブが固まるので、1文字ずつ読む（一致する範囲は同じ）。
// 中のインラインの記法（リンクなど）はそのまま読む
const Annotation = { resolve: 'LyndbaumAnnotation', mark: 'LyndbaumAnnotationMark' };
const ANNOTATION = /^\(\(((?:[^()]|\([^()]*\))*)\)\)/;
const annotation_close = new WeakMap();		// InlineContext → 閉じる位置のSet
function annotation_parser(cx, next, pos) {
	if (next != C_PAREN && next != C_PAREN_CLOSE) return -1;
	if (cx.char(pos + 1) != next) return -1;
	let close = annotation_close.get(cx);
	if (next == C_PAREN) {
		const m = ANNOTATION.exec(cx.slice(pos, cx.end));
		if (!m) return -1;
		if (!close) annotation_close.set(cx, close = new Set());
		close.add(pos + m[0].length - 2);
		return cx.addDelimiter(Annotation, pos, pos + 2, true, false);
	}
	if (!close || !close.has(pos)) return -1;
	close.delete(pos);
	return cx.addDelimiter(Annotation, pos, pos + 2, false, true);
}

//------------------------------------------------------------------------------
// ●続きを読む（空行の後の ==== か ===== だけの行）
//------------------------------------------------------------------------------
const SeeMore = {
	name: 'LyndbaumSeeMore',
	before: 'HorizontalRule',
	parse(cx, line) {
		if (line.text != '====' && line.text != '=====') return false;
		cx.addElement(cx.elt('LyndbaumSeeMore', cx.lineStart, cx.lineStart + line.text.length));
		cx.nextLine();
		return true;
	}
};

//------------------------------------------------------------------------------
// ●対応しない記法で始まる行は、ブロックにせず文章として読む
//------------------------------------------------------------------------------
// ~~~（フェンス）、「* 」「+ 」（リスト）、* か _ だけの行（区切り線）。
// その行を1つの段落にする（中の太字やリンクなどは読む）
function is_plain_line(line) {
	const text = line.text, pos = line.pos, c = line.next;
	if (c == C_TILDE) return text.charCodeAt(pos + 1) == C_TILDE && text.charCodeAt(pos + 2) == C_TILDE;
	if (c != C_STAR && c != C_PLUS && c != C_UNDER) return false;
	if (c != C_UNDER) {
		const c1 = text.charCodeAt(pos + 1);
		if (pos + 1 == text.length || c1 == C_SPACE || c1 == C_TAB) return true;
	}
	if (c == C_PLUS) return false;
	let count = 0;
	for (let i = pos; i < text.length; i++) {
		const ch = text.charCodeAt(i);
		if (ch == c) count++;
		else if (ch != C_SPACE && ch != C_TAB) return false;
	}
	return count >= 3;
}
const PlainLine = {
	name: 'LyndbaumPlainLine',
	before: 'FencedCode',
	parse(cx, line) {
		if (!is_plain_line(line)) return false;
		const from = cx.lineStart + line.pos, to = cx.lineStart + line.text.length;
		cx.addElement(cx.elt('Paragraph', from, to, cx.parser.parseInline(line.text.slice(line.pos), from)));
		cx.nextLine();
		return true;
	},
	// 引用の > や、リストの項目の字下げが無い行は、前の段落の続き（継続行）にしない
	endLeaf(cx, line) { return line.depth < cx.depth; }
};

//------------------------------------------------------------------------------
// ●__太字__ にしない
//------------------------------------------------------------------------------
// _ が2つ以上続く所は、強調の記号にせず文字として読む（_強調_ は読む）
function underscore_run(cx, next, pos) {
	if (next != C_UNDER) return -1;
	let end = pos + 1;
	while (cx.char(end) == C_UNDER) end++;
	return end - pos >= 2 ? end : -1;
}

//------------------------------------------------------------------------------
// ●CM.markdown()の引数
//------------------------------------------------------------------------------
export function lyndbaumMarkdown(tag_names) {
	const names = new Set(tag_names || []);
	const config = {
		defineNodes: [
			{ name: 'LyndbaumTag' },
			{ name: 'LyndbaumTagName',        style: tag.name  },
			{ name: 'LyndbaumTagMark',        style: tag.mark  },
			{ name: 'LyndbaumToc',            style: tag.quiet },
			{ name: 'LyndbaumHeadingId',      style: tag.quiet },
			{ name: 'LyndbaumSeeMore',        block: true, style: tag.quiet },
			{ name: 'LyndbaumFootnote',       style: tag.note  },
			{ name: 'LyndbaumAnnotation' },
			{ name: 'LyndbaumAnnotationMark', style: tag.mark  }
		],
		parseBlock: [ PlainLine, SeeMore ],
		parseInline: [
			{ name: 'LyndbaumBracket',    parse: bracket_parser(names), before: 'Link' },
			{ name: 'LyndbaumClose',      parse: close_bracket,         before: 'LinkEnd' },
			{ name: 'LyndbaumAnnotation', parse: annotation_parser,     before: 'Emphasis' },
			{ name: 'LyndbaumUnderscore', parse: underscore_run,        before: 'Emphasis' }
		],
		remove: [ 'SetextHeading', 'IndentedCode', 'LinkReference', 'HardBreak' ]
	};
	return {
		extensions: [ Table, Strikethrough, TaskList, config ],
		addKeymap: false,	// lyndbaumEditKeysを使う
		pasteURLAsLink: false	// lyndbaumPasteURLを使う
	};
}

//##############################################################################
// ■編集の補助（Markdownの記事だけ。edit-cm.jsがlyndbaumMarkdown()と一緒に入れる）
//##############################################################################
//------------------------------------------------------------------------------
// ●太字・強調で囲む（選択が無ければ記号だけ入れて、カーソルを間に置く）
//------------------------------------------------------------------------------
// 複数行を選んでいれば、行ごとに囲む（記法ヘルパーと同じ）。空白だけの行は囲まない。
// 行の前後の空白は囲みの外に出す（「** 文字**」は太字にならないため）
export function lyndbaum_wrap(state, mark) {
	return state.changeByRange(function(range) {
		if (range.empty) return {
			changes: { from: range.from, insert: mark + mark },
			range:   EditorSelection.cursor(range.from + mark.length)
		};
		const text  = state.sliceDoc(range.from, range.to);
		const lines = text.split("\n").map(function(line) {
			const m = /^(\s*)(.*?)(\s*)$/.exec(line);
			return m[2] == '' ? line : m[1] + mark + m[2] + mark + m[3];
		});
		const out = lines.join("\n");
		if (lines.length == 1 && out != text) {
			// 1行なら、囲んだ中身を選んだままにする
			const lead = /^\s*/.exec(text)[0].length;
			const body = text.trim().length;
			const from = range.from + lead + mark.length;
			return { changes: { from: range.from, to: range.to, insert: out }, range: EditorSelection.range(from, from + body) };
		}
		return { changes: { from: range.from, to: range.to, insert: out }, range: EditorSelection.range(range.from, range.from + out.length) };
	});
}

//------------------------------------------------------------------------------
// ●リンク（選択があれば [選択](|)、無ければ [|]()）
//------------------------------------------------------------------------------
// 複数行の選択はリンクにしない（記法ヘルパーのリンクと同じ）
export function lyndbaum_link(state) {
	let multi = false;
	const spec = state.changeByRange(function(range) {
		if (range.empty) return {
			changes: { from: range.from, insert: '[]()' },
			range:   EditorSelection.cursor(range.from + 1)
		};
		if (state.sliceDoc(range.from, range.to).indexOf("\n") >= 0) { multi = true; return { range }; }
		return {
			changes: [ { from: range.from, insert: '[' }, { from: range.to, insert: ']()' } ],
			range:   EditorSelection.cursor(range.to + 3)
		};
	});
	return multi ? null : spec;
}

//------------------------------------------------------------------------------
// ●Enterでリストと引用の記号を続ける
//------------------------------------------------------------------------------
// lang-markdownのinsertNewlineContinueMarkupは、番号付きの項目の続きの行（「1. a」の次の
// 「   b」）でEnterすると、記号の無い行を足すだけなのに、後ろの「2.」を「3.」にする。
// 項目を足していないので、カーソルの行より後ろの変更（番号の振り直し）を捨てる
const continue_markup = insertNewlineContinueMarkupCommand({ nonTightLists: false });
export function enter_continue_markup(view) {
	const state = view.state;
	let tr = null;
	if (!continue_markup({ state, dispatch: function(t){ tr = t } }) || !tr) return false;

	const main = state.selection.main;
	const line = state.doc.lineAt(main.head);
	let item = syntaxTree(state).resolveInner(main.head, -1);
	while (item && item.name != 'ListItem') item = item.parent;
	const continued = state.selection.ranges.length == 1 && item && item.parent.name == 'OrderedList'
		&& state.doc.lineAt(item.from).number < line.number;
	if (!continued) { view.dispatch(tr); return true; }

	const changes = [];
	tr.changes.iterChanges(function(from, to, _from, _to, insert) {
		if (from <= line.to) changes.push({ from, to, insert });
	});
	view.dispatch({ changes, selection: tr.selection, scrollIntoView: true, userEvent: 'input' });
	return true;
}

//------------------------------------------------------------------------------
// ●Backspaceで番号付きの項目の記号を消したら、後ろの番号を振り直す
//------------------------------------------------------------------------------
// lang-markdownのdeleteMarkupBackwardは、「2. 」を空白にする（最初の項目なら消す）だけで、
// 後ろの「3.」を残す。後ろの同じ段の項目を、番号が1ずつ続いている間だけ1ずつ減らす
// （lang-markdownがEnterで使うrenumberListと同じ止め方。外に出されていないので書く）
function item_number(state, item) {
	return /^(\s*)(\d+)(?=[.)])/.exec(state.sliceDoc(item.from, item.from + 12));
}
export function renumber_after_delete(state) {
	const main = state.selection.main;
	if (!main.empty || state.selection.ranges.length > 1) return [];
	let item = syntaxTree(state).resolveInner(main.head, -1);
	while (item && !(item.name == 'ListItem' && item.parent && item.parent.name == 'OrderedList')) item = item.parent;
	if (!item) return [];
	// カーソルが、その項目の行の「番号.」か「番号. 」の直後にあるときだけ（記号が消えるとき）
	if (!/^\d+[.)] ?$/.test(state.sliceDoc(item.from, main.head))) return [];

	const changes = [];
	let prev = +item_number(state, item)[2];
	for (let node = item.nextSibling; node && node.name == 'ListItem'; node = node.nextSibling) {
		const m = item_number(state, node);
		if (!m || +m[2] != prev + 1) break;
		changes.push({ from: node.from + m[1].length, to: node.from + m[0].length, insert: String(prev) });
		prev = +m[2];
	}
	return changes;
}
export function delete_markup_renumber(view) {
	const state = view.state;
	let tr = null;
	if (!deleteMarkupBackward({ state, dispatch: function(t){ tr = t } }) || !tr) return false;
	view.dispatch(
		{ changes: tr.changes, selection: tr.selection, scrollIntoView: true, userEvent: 'delete' },
		{ changes: renumber_after_delete(state) }	// どちらも押す前の文書の位置
	);
	return true;
}

function key_command(make) {
	return function(view) {
		if (view.state.readOnly) return true;	// ブラウザのキー（ブックマークなど）には渡さない
		const spec = make(view.state);
		if (spec) view.dispatch(view.state.update(spec, { scrollIntoView: true, userEvent: 'input' }));
		return true;
	};
}
// Enter：リストと引用の記号を続ける（lang-markdownのmarkdownKeymapと同じ）。空の項目でEnterすると
//   記号を消す。lang-markdownの既定では、2つ目の項目が空のときは、記号を消さずに項目の間に空行を
//   入れる（各項目が<p>になる）ので、それはしない（nonTightLists: false）。番号付きの項目の続きの行
//   では番号を振り直さない（enter_continue_markup）
// Backspace：記号の直後なら、記号を消す。番号付きの項目なら、後ろの番号を振り直す
// defaultKeymapのEnter、Backspace、Mod-i（構文の親を選ぶ）より先に効かせる
export const lyndbaumEditKeys = Prec.high(keymap.of([
	{ key: 'Enter',     run: enter_continue_markup },
	{ key: 'Backspace', run: delete_markup_renumber },
	{ key: 'Mod-b', run: key_command(function(s){ return lyndbaum_wrap(s, '**') }), preventDefault: true },
	{ key: 'Mod-i', run: key_command(function(s){ return lyndbaum_wrap(s, '*')  }), preventDefault: true },
	{ key: 'Mod-k', run: key_command(lyndbaum_link), preventDefault: true }
]));

//------------------------------------------------------------------------------
// ●文字を選んでURLを貼ったら、[文字](URL)にする
//------------------------------------------------------------------------------
// lang-markdownのpasteURLAsLinkと同じ形で、Lyndbaumに合わせて変える。
// ・URLは http:// https:// ftp:// で始まり、空白を含まないもの
// ・URLに ( ) があれば [文字](<URL>) にする
// ・選んだ文字が、コード、リンク、さつき記法のタグ、目次などの中にあるとき、選択の中で
//   記法が始まる・終わるとき、[ ] や改行を含むときは、普通に貼る。注釈の中はリンクにする
// 選択が無いときや、条件に合わないときはnullを返す（普通に貼る）
const NON_PLAIN = /code|horizontalrule|html|link|comment|processing|escape|entity|image|url|^Lyndbaum(?!Annotation$)/i;
export function lyndbaum_paste_url(state, text) {
	const main = state.selection.main;
	if (main.empty || state.selection.ranges.length > 1) return null;
	const url = (text || '').trim();
	if (!/^(?:https?|ftp):\/\/[^\s<>]+$/i.test(url)) return null;
	const label = state.sliceDoc(main.from, main.to);
	if (/[\[\]\n]/.test(label)) return null;
	if (!markdownLanguage.isActiveAt(state, main.from, 1)) return null;

	let plain = true;
	syntaxTree(state).iterate({
		from: main.from, to: main.to,
		enter: function(node) {
			if (!plain) return false;
			if (node.to <= main.from || main.to <= node.from) return false;	// 選択に接するだけ
			if (main.from < node.from || node.to < main.to) { plain = false; return false; }	// 選択の中で始まる・終わる
			if (NON_PLAIN.test(node.name)) { plain = false; return false; }
		}
	});
	if (!plain) return null;

	const dest = /[()]/.test(url) ? '<' + url + '>' : url;
	return {
		changes: [ { from: main.from, insert: '[' }, { from: main.to, insert: '](' + dest + ')' } ],
		selection: EditorSelection.cursor(main.to + 4 + dest.length),	// )の後ろ
		userEvent: 'input.paste',
		scrollIntoView: true
	};
}
export const lyndbaumPasteURL = EditorView.domEventHandlers({
	paste: function(evt, view) {
		if (view.state.readOnly || !evt.clipboardData) return false;
		const spec = lyndbaum_paste_url(view.state, evt.clipboardData.getData('text/plain'));
		if (!spec) return false;
		evt.preventDefault();
		view.dispatch(spec);
		return true;
	}
});

//------------------------------------------------------------------------------
// ●閉じるカッコを足す
//------------------------------------------------------------------------------
// ( [ だけ。' " は日本語の文で邪魔になり、` はフェンス（```）を打つと6つになるので入れない。
// 次の文字が空白、行末、)]}:;> のときだけ閉じる（closeBracketsの既定。文の途中では閉じない）。
// 文字を選んで打つと、選択を囲む
export const lyndbaumCloseBrackets = [
	EditorState.languageData.of(function(){ return [{ closeBrackets: { brackets: ['(', '['] } }] }),
	closeBrackets(),
	Prec.high(keymap.of(closeBracketsKeymap))	// Backspaceで対を消す（defaultKeymapより先に）
];
