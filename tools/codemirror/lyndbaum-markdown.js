//##############################################################################
// LyndbaumのMarkdownに合わせた読み方と色分け（編集欄、edit-cm.js）
//##############################################################################
// CodeMirrorのMarkdown（Lezer、CommonMark）は、[…]をすべて参照形式のリンクとして読む。
// Lyndbaumは参照形式のリンクに対応せず、[…]はさつき記法のタグ（知っている名前のときだけ）
// なので、docs/markdown-syntax.mdに合わせて読み方を変える。
//
// lyndbaumMarkdown(tag_names) … CM.markdown()の引数（tag_namesはサーバーのタグ定義のキー）
// lyndbaumHighlight            … 足した記法の色分け
import {Table, Strikethrough, TaskList, InlineContext} from "@lezer/markdown";
import {Tag, tags as t} from "@lezer/highlight";
import {HighlightStyle} from "@codemirror/language";

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
      C_SPACE = 32, C_TAB = 9, C_COLON = 58;

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
// ●参照形式のリンクにしない
//------------------------------------------------------------------------------
// ] の直後が ( でなければ、開いた [ を取り下げて普通の文字にする
function close_bracket(cx, next, pos) {
	if (next != C_CLOSE || cx.char(pos + 1) == C_PAREN) return -1;
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
// 中のインラインの記法（リンクなど）はそのまま読む
const Annotation = { resolve: 'LyndbaumAnnotation', mark: 'LyndbaumAnnotationMark' };
const ANNOTATION = /^\(\(((?:[^()]+|\([^()]*\))*)\)\)/;
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
		parseBlock: [ SeeMore ],
		parseInline: [
			{ name: 'LyndbaumBracket',    parse: bracket_parser(names), before: 'Link' },
			{ name: 'LyndbaumClose',      parse: close_bracket,         before: 'LinkEnd' },
			{ name: 'LyndbaumAnnotation', parse: annotation_parser,     before: 'Emphasis' }
		],
		remove: [ 'SetextHeading', 'IndentedCode', 'LinkReference', 'HardBreak' ]
	};
	return {
		extensions: [ Table, Strikethrough, TaskList, config ],
		addKeymap: false,
		pasteURLAsLink: false
	};
}
