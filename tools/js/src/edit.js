//##############################################################################
// 記事編集画面用JavaScript
//							(C)2014 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';
//### global variables #######################################################
var insert_image;	// global function for media.js

adiary.ready(function(){
//##############################################################################
// ■サブルーチン
//##############################################################################
function create(tag, cls) {
	const dom = document.createElement(tag);
	if (cls) dom.className = cls;
	return dom;
}
function text_of(id) {
	const dom = document.getElementById(id);
	return dom ? dom.textContent : '';
}
// jQueryの .show()、.hide() と同じ。CSSで隠れていれば、その要素の既定の表示にする
const default_display = {};
function show(dom) {
	if (!dom) return;
	if (dom.style.display === 'none') dom.style.display = '';
	if (getComputedStyle(dom).display !== 'none') return;
	const tag = dom.nodeName;
	if (!default_display[tag]) {
		const tmp = document.body.appendChild( document.createElement(tag) );
		default_display[tag] = getComputedStyle(tmp).display;
		tmp.remove();
		if (default_display[tag] === 'none') default_display[tag] = 'block';
	}
	dom.style.display = default_display[tag];
}
function hide(dom) {
	if (dom) dom.style.display = 'none';
}
// サーバーにPOSTして、JSONを受け取る（今までの $.ajax の dataType:'json' と同じ扱い）。
// 成り立つのは2xxか304で、JSONとして読めたとき。そうでなければ error。最後に complete
function post_json(url, data, opt) {
	const xhr = new XMLHttpRequest();
	xhr.open('POST', url);
	if (opt.progress) xhr.upload.addEventListener('progress', opt.progress);
	function done(ok) {
		let json;
		if (ok) {
			try {
				json = JSON.parse(xhr.responseText);
			} catch(e) {
				ok = false;
			}
		}
		if (ok) { if (opt.success) opt.success(json); }
		  else  { if (opt.error)   opt.error(xhr);    }
		if (opt.complete) opt.complete(xhr);
	}
	xhr.addEventListener('load', function(){
		done(xhr.status >= 200 && xhr.status < 300 || xhr.status === 304);
	});
	xhr.addEventListener('error',   function(){ done(false) });
	xhr.addEventListener('abort',   function(){ done(false) });
	xhr.addEventListener('timeout', function(){ done(false) });
	xhr.send(data);
	return xhr;
}
// フォームの欄の値（jQueryの .val() と同じ）
function val_of(el) {
	if (el.type === 'select-multiple')
		return Array.from(el.options).filter(function(o){ return o.selected }).map(function(o){ return o.value });
	if (el.type === 'select-one' && el.selectedIndex < 0) return null;
	return typeof(el.value) === 'string' ? el.value.replace(/\r/g, '') : el.value;
}

//##############################################################################
const tagsel = adiary.secure('#tag-select');
const upsel  = adiary.secure('#upnode-select');
const edit   = document.getElementById('editarea');

// タグ一覧 [{ name: "親::子", qt: 使用数 }, ...]
const all_tags = [];
adiary.load_tags_list(tagsel, function(data){
	const r_func = function(ary, head) {
		for(var i=0; i<ary.length; i++) {
			const name = head + ary[i].title;
			all_tags.push({ name: name, lc: name.toLowerCase(), qt: ary[i].qt || 0 });
			if (ary[i].children) r_func( ary[i].children, name + '::' );
		}
	};
	r_func(data, '');
});
// 読み込んで、optionを足してchangeを起こした後に終わる（失敗しても終わる）
const contents_loaded = Promise.resolve( adiary.load_contents_list(upsel) ).catch(function(){});

//##############################################################################
// ■下書きを開く
//##############################################################################
{
	const draft = document.getElementById('select-draft');
	const open_draft    = document.getElementById('open-draft');
	const open_template = document.getElementById('open-template');
	if (open_draft) open_draft.addEventListener('click', function(){
		var pkey = draft.value;
		window.location = adiary.myself2 + '0' + pkey + '?edit';
	});
	if (open_template) open_template.addEventListener('click', function(){
		var pkey = draft.value;
		window.location = adiary.myself2 + '0' + pkey + '?edit&template=1';
	});
}

//##############################################################################
// ■タグの削除ボタン、タグの追加
//##############################################################################
{
	//----------------------------------------------------------------------
	// ●タグの削除ボタン（×ボタン）
	//----------------------------------------------------------------------
	function make_tagdel() {
		const span = create('span', 'ui-icon ui-icon-close');
		span.addEventListener('click', function(evt){
			evt.target.parentElement.remove();
		});
		return span;
	}
	document.querySelectorAll('#edit-tags span.tag').forEach(function(tag){
		tag.appendChild( make_tagdel() );
	});

	//----------------------------------------------------------------------
	// ●タグの追加
	//----------------------------------------------------------------------
	function tag_append(text) {
		if (text=="") return;

		const tags = document.getElementById('tags');
		const ch   = tags.children;
		for(var i=0; i<ch.length; i++) {
			if (ch[i].textContent == text) return;
		}
		// append
		const tag = create('span', 'tag');
		tag.innerHTML = adiary.tag_esc_amp(text);
		const inp = create('input');
		inp.setAttribute('type',  'hidden');
		inp.setAttribute('name',  'tag_ary');
		inp.setAttribute('value', text);
		tag.append( inp, make_tagdel() );
		tags.appendChild( tag );
	}

	//--------------------------------------------------------------------------------
	// ●タグ追加ダイアログの表示
	//--------------------------------------------------------------------------------
	const addtag  = adiary.secure('#edit-add-tag');
	const tagform = adiary.secure('#tag-select-form');
	if (tagform) tagform.remove();
	const inp     = tagform.querySelector('#input-new-tag');
	const cands   = tagform.querySelector('#tag-candidates');
	const max_cands = 20;
	let   dialog;

	//--------------------------------------------------------------------------------
	// ●候補の絞り込み
	//--------------------------------------------------------------------------------
	// 空白区切りの全語を含むタグを、完全一致→階層名の先頭一致→使用数の多い順に並べる
	function match_rank(t, lc, words) {
		if (t.lc == lc) return 2;
		const segs = t.lc.split('::');
		return words.every(function(w){
			return segs.some(function(s){ return s.indexOf(w) == 0 });
		}) ? 1 : 0;
	}
	function update_candidates() {
		cands.innerHTML = '';
		const text  = inp.value.trim();
		const words = text.toLowerCase().split(/\s+/).filter(function(w){ return w != '' });
		if (!words.length) return;

		const added = {};
		document.querySelectorAll('#tags input[name="tag_ary"]').forEach(function(obj){ added[obj.value] = true; });

		const lc = text.toLowerCase();
		const hits = all_tags.filter(function(t){
			if (added[t.name]) return false;
			for(var i=0; i<words.length; i++)
				if (t.lc.indexOf(words[i]) < 0) return false;
			return true;
		});
		hits.forEach(function(t){ t.rank = match_rank(t, lc, words) });
		hits.sort(function(a, b){
			return (b.rank - a.rank) || (b.qt - a.qt);
		});

		for(var i=0; i<hits.length && i<max_cands; i++) {
			const li = create('li');
			li.setAttribute('data-tag', hits[i].name);
			const s1 = create('span');
			s1.textContent = hits[i].name;
			const s2 = create('span', 'qt');
			s2.textContent = hits[i].qt;
			li.append(s1, s2);
			cands.appendChild(li);
		}
		// 一致するタグがなければ新規タグとして追加
		const exists = all_tags.some(function(t){ return t.name == text });
		if (!exists && !added[text] && text.indexOf(',') < 0) {
			const msg = text_of('new-tag-create').replace('%t', text);
			const li  = create('li', 'new-tag');
			li.setAttribute('data-tag', text);
			li.textContent = msg;
			cands.appendChild(li);
		}
		if (cands.firstElementChild) cands.firstElementChild.classList.add('selected');
	}

	function move_selected(dir) {
		const li = Array.from(cands.children);
		if (!li.length) return;
		const cur  = li.findIndex(function(x){ return x.classList.contains('selected') });
		const next = (cur + dir + li.length) % li.length;
		li.forEach(function(x){ x.classList.remove('selected') });
		li[next].classList.add('selected');
		li[next].scrollIntoView({ block: 'nearest' });
	}

	// 追加したらダイアログは閉じずに次の入力へ
	function append_and_continue(tag) {
		if (tag == '' || tag.indexOf(',') >= 0) return;
		tag_append( tag );
		inp.value = '';
		update_candidates();
		inp.focus();
	}

	function append_selected() {
		const sel = Array.from(cands.children).find(function(x){ return x.classList.contains('selected') });
		if (sel) return append_and_continue( sel.getAttribute('data-tag') );
		append_and_continue( inp.value.trim() );
	}

	inp.addEventListener('input', update_candidates);
	inp.addEventListener('keydown', function(evt){
		// IME変換中のキー操作は無視
		if (evt.isComposing || evt.keyCode == 229) return;
		let stop;
		if      (evt.keyCode == 38) { move_selected(-1); stop = true; }	// ↑
		else if (evt.keyCode == 40) { move_selected( 1); stop = true; }	// ↓
		else if (evt.keyCode == 13) { append_selected(); stop = true; }
		if (!stop) return;
		evt.preventDefault();
		evt.stopPropagation();
	});
	cands.addEventListener('click', function(evt){
		const li = evt.target.closest('li');
		if (!li || !cands.contains(li)) return;
		append_and_continue( li.getAttribute('data-tag') );
	});

	addtag.addEventListener('click', function(){
		const div = create('div');
		div.appendChild( tagform );

		// ボタンの設定
		var buttons = {};
		buttons[ text_of('new-tag-append') ] = append_selected;
		buttons[ text_of('new-tag-close') ] = function(){
			dialog.close();
		};
		dialog = adiary.dialog(div, {
			modal:	true,
			width:	Math.min(420, document.documentElement.clientWidth - 20),
			minHeight: 200,
			title:   addtag.dataset.title,
			buttons: buttons,
			open: function(){
				inp.focus();
			},
			beforeClose: function(){
				if (tagsel) tagsel.value = '';
				inp.value = '';
				cands.innerHTML = '';
				tagform.remove();
			}
		});
	});

	//--------------------------------------------------------------------------------
	// ●タグ選択フォームの処理
	//--------------------------------------------------------------------------------
	if (tagsel) tagsel.addEventListener('change', function(){
		const opt = tagsel.selectedOptions[0];
		if (opt && opt.dataset.new) return;
		tag_append( tagsel.value );
		tagsel.value = '';
		update_candidates();
	});
}

//##############################################################################
// ■アイキャッチ画像（OGP画像）
//##############################################################################
// name="ogp" の欄が実体（main_image）。空ならブログの画像を使う。本文の画像は拾わない。
// 画像はメディア管理を別のウィンドウで開いて選ぶ（media.js が set_eyecatch() を呼ぶ）
{
	const preview  = document.getElementById('eyecatch-preview');
	const pick     = document.getElementById('eyecatch-pick');
	const remove   = document.getElementById('eyecatch-remove');
	const ogp      = document.getElementById('ogp-input');
	const imgdir   = text_of('image-dir');		// 画像ディレクトリ（相対）
	const img_url  = adiary.Basepath + imgdir;
	const img_ext  = /\.(?:jpe?g|png|gif|webp|apng|avif)$/i;

	// 古い保存値の [image:S:folder/:file:caption] 記法と、画像ディレクトリ内を指すURLを拾う
	const dir_re = imgdir.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const img_re = new RegExp('\\[image:[^:\\]]*:([^:\\]]*/):([^:\\]]+)|' + dir_re + '([^\\s"\'<>()\\]]+)', 'g');

	// 画像ディレクトリからの相対パスの一覧を返す（サムネイルは元画像に戻す）
	function find_images(text) {
		const list = [];
		img_re.lastIndex = 0;
		let m;
		while((m = img_re.exec(text))) {
			let path = (m[3] !== undefined) ? m[3] : m[1] + m[2];
			path = path.replace(/(^|\/)\.thumbnail\/(.+)\.(?:jpg|avif)$/, '$1$2');
			if (img_ext.test(path) && list.indexOf(path) < 0) list.push(path);
		}
		return list;
	}

	// 表示用のパスにする。本文から自動で入った古い値はURLエンコードされている
	function decode_path(path) {
		try {
			return decodeURIComponent(path);
		} catch(e) {
			return path;
		}
	}

	// 欄の値を画像パスにする。保存した値の末尾の「?幅,高さ」と、記法で書いた古い値に対応する
	function current_value() {
		const val = ogp.value.trim().replace(/\?\d+,\d+$/, '');
		if (val.indexOf(':') < 0) return decode_path(val);
		return find_images(val)[0] || val;
	}

	function enc(path) {
		return path.split('/').map(encodeURIComponent).join('/');
	}
	// サムネイルはAVIFかJPEG（サーバーの thumbnail_ext）。AVIF、JPEG、元画像の順に試す
	function thumb_url(path, ext) {
		const x = path.lastIndexOf('/');
		return img_url + enc(path.substr(0, x+1) + '.thumbnail/' + path.substr(x+1) + '.' + ext);
	}
	function make_img(path) {
		const urls = [ thumb_url(path, 'jpg'), img_url + enc(path) ];
		const img  = create('img');
		img.setAttribute('src', thumb_url(path, 'avif'));
		img.setAttribute('alt', '');
		img.addEventListener('error', function(){
			if (urls.length) img.setAttribute('src', urls.shift());
		});
		return img;
	}

	function render() {
		const cur = current_value();
		preview.innerHTML = '';
		if (cur != '') {
			// 選んだ画像は、押すと選び直せる
			const btn = create('button');
			btn.setAttribute('type',  'button');
			btn.setAttribute('title', '画像を変更');
			btn.className = 'eyecatch-change';
			btn.appendChild( make_img(cur) );
			preview.appendChild(btn);
		} else {
			const img = create('img');
			img.setAttribute('src', preview.dataset.blogImage);
			img.setAttribute('alt', '');
			preview.appendChild(img);
		}
		(cur == '' ? show : hide)(pick);
		(cur != '' ? show : hide)(remove);
	}

	// メディア管理を開く。選んである画像があれば、そのフォルダを開く
	function open_media() {
		const cur = current_value();
		let url   = pick.dataset.url;
		const x   = cur.lastIndexOf('/');
		if (x >= 0) url += '&folder=' + encodeURIComponent(cur.substr(0, x+1));
		const win = window.open(url, 'media', 'location=yes, menubar=no, resizable=yes, scrollbars=yes');
		win.focus();
	}
	pick.addEventListener('click', open_media);
	preview.addEventListener('click', function(evt){
		const btn = evt.target.closest('.eyecatch-change');
		if (btn && preview.contains(btn)) open_media();
	});
	remove.addEventListener('click', function(){
		ogp.value = '';
		render();
	});

	// メディア管理から呼ばれる。path は画像ディレクトリからの相対パス
	window.set_eyecatch = function(path) {
		ogp.value = path;
		render();
	};

	render();
}

//##############################################################################
// ■差分（更新履歴、保存の競合で使う）
//##############################################################################
//------------------------------------------------------------------------------
// ●行単位の差分（a → b）。大きすぎる場合はnull
//------------------------------------------------------------------------------
function line_diff(a, b) {
	// 前後の共通部分は比較しない
	let s = 0;
	while(s < a.length && s < b.length && a[s] === b[s]) s++;
	let ea = a.length, eb = b.length;
	while(ea > s && eb > s && a[ea-1] === b[eb-1]) { ea--; eb--; }
	const A = a.slice(s, ea), B = b.slice(s, eb);
	const n = A.length, m = B.length, w = m + 1;
	if (n * m > 4000000) return null;	// 差分計算の上限（行数の積）

	// LCS
	const L = new Uint32Array((n+1) * w);
	for(let i=n-1; i>=0; i--)
		for(let j=m-1; j>=0; j--)
			L[i*w+j] = (A[i] === B[j]) ? L[(i+1)*w+j+1] + 1 : Math.max(L[(i+1)*w+j], L[i*w+j+1]);

	const out = [];
	for(let k=0; k<s; k++) out.push([' ', a[k]]);
	let i=0, j=0;
	while(i<n && j<m) {
		if (A[i] === B[j])                  { out.push([' ', A[i]]); i++; j++; }
		else if (L[(i+1)*w+j] >= L[i*w+j+1]) { out.push(['-', A[i]]); i++; }
		else                                 { out.push(['+', B[j]]); j++; }
	}
	for(; i<n; i++) out.push(['-', A[i]]);
	for(; j<m; j++) out.push(['+', B[j]]);
	for(let k=ea; k<a.length; k++) out.push([' ', a[k]]);
	return out;
}

// 変更行の前後だけを表示する
function render_diff(diff, body) {
	const ctx = 2;
	const show = new Array(diff.length).fill(false);
	diff.forEach(function(d, i){
		if (d[0] == ' ') return;
		for(let k=Math.max(0, i-ctx); k<=Math.min(diff.length-1, i+ctx); k++) show[k] = true;
	});
	body.innerHTML = '';
	function span(cls, text) {
		const s = create('span', cls);
		s.textContent = text;
		body.appendChild(s);
	}
	let skipped = false;
	diff.forEach(function(d, i){
		if (!show[i]) { skipped = true; return; }
		if (skipped) { span('rev-skip', "…"); skipped = false; }
		const cls = d[0] == '-' ? 'rev-del' : d[0] == '+' ? 'rev-add' : 'rev-ctx';
		span(cls, d[0] + ' ' + d[1]);
	});
	if (skipped) span('rev-skip', "…");
}

// 記事の更新履歴、今の記事の要約を取り寄せる（失敗したらnull）
function ajax_revision(data, callback) {
	data.action = 'ajax_revision';
	post_json(adiary.myself + '?etc/ajax_dummy', new URLSearchParams(data), {
		success: callback,
		error:   function(){ callback(null) }
	});
}

//##############################################################################
// ■更新履歴
//##############################################################################
{
	const btn    = adiary.secure('#edit-revision');
	const dialog = adiary.secure('#revision-dialog');
	if (dialog) dialog.remove();
	const list   = dialog.querySelector('#revision-list');
	const title  = dialog.querySelector('#revision-title');
	const body   = dialog.querySelector('#revision-body');
	let cur_rev;			// 表示中の版
	let dlg;

	function format_tm(tm) {
		const d = new Date(tm * 1000);
		const z = function(n){ return (n < 10 ? '0' : '') + n };
		return d.getFullYear() + '/' + z(d.getMonth()+1) + '/' + z(d.getDate())
			+ ' ' + z(d.getHours()) + ':' + z(d.getMinutes());
	}

	function show_revision() {
		title.innerHTML = '';
		body.innerHTML  = '';
		body.classList.remove('rev-full');
		if (!cur_rev) {
			body.textContent = text_of('rev-select');
			return;
		}
		title.innerHTML = cur_rev.title;

		const checked = dialog.querySelector('input[name="rev_mode"]:checked');
		const mode = checked ? checked.value : undefined;
		const text = cur_rev.text;
		if (mode == 'diff') {
			const now  = edit.value.replace(/\r\n?/g, "\n");
			if (now === text) { body.textContent = text_of('rev-same'); return; }
			const diff = line_diff(text.split("\n"), now.split("\n"));
			if (diff) return render_diff(diff, body);
			const note = create('div', 'rev-note');
			note.textContent = text_of('rev-too-large');
			title.appendChild(note);
		}
		body.classList.add('rev-full');
		body.textContent = text;
	}
	dialog.querySelectorAll('input[name="rev_mode"]').forEach(function(x){
		x.addEventListener('change', show_revision);
	});

	//--------------------------------------------------------------------------
	// ●一覧
	//--------------------------------------------------------------------------
	// 直前の保存（data-last）は記事のpkeyで、履歴は版のpkeyで読む
	list.addEventListener('click', function(evt){
		const li = evt.target.closest('li[data-pkey]');
		if (!li || !list.contains(li)) return;
		Array.from(list.children).forEach(function(x){ x.classList.remove('selected') });
		li.classList.add('selected');
		const req = li.getAttribute('data-last') ? { last: document.getElementById('edit-pkey').value } : { rev: li.getAttribute('data-pkey') };
		ajax_revision(req, function(data){
			if (!data || !li.classList.contains('selected')) return;
			data.text = data.text.replace(/\r\n?/g, "\n");
			cur_rev = data;
			show_revision();
		});
	});

	function load_list() {
		list.innerHTML = '';
		cur_rev = undefined;
		show_revision();
		ajax_revision({ pkey: document.getElementById('edit-pkey').value }, function(data){
			if (!data || !data.length) {
				const li = create('li', 'rev-empty');
				li.textContent = text_of('rev-empty');
				list.appendChild(li);
				return;
			}
			const chars = text_of('rev-chars');
			data.forEach(function(r){
				const li = create('li');
				li.setAttribute('data-pkey', r.pkey);
				function add(tag, cls, text, html) {
					const x = create(tag, cls);
					if (html) x.innerHTML = text;
					     else x.textContent = text;
					li.appendChild(x);
				}
				if (r.last) {
					li.setAttribute('data-last', 1);
					li.classList.add('rev-last');
					add('span', 'rev-last-label', text_of('rev-last'));
				}
				add('span', 'rev-tm',    format_tm(r.update_tm || r.tm));
				add('span', 'rev-len',   chars.replace('%n', r.length.toLocaleString()));
				add('div',  'rev-title', r.title, true);
				list.appendChild(li);
			});
		});
	}

	//--------------------------------------------------------------------------
	// ●ダイアログ
	//--------------------------------------------------------------------------
	// 履歴のボタンは、保存した記事を編集するときだけある（新しい記事には無い）
	if (btn) btn.addEventListener('click', function(){
		const div = create('div');
		div.appendChild(dialog);
		const buttons = {};
		buttons[ text_of('rev-load') ] = function(){
			if (!cur_rev) return;
			const msg = text_of('rev-confirm').replace('%t', format_tm(cur_rev.update_tm || cur_rev.tm));
			adiary.confirm(msg, function(ok){
				if (!ok) return;
				edit.value = cur_rev.text;
				edit.dispatchEvent(new Event('input', { bubbles: true }));
				dlg.close();
			});
		};
		buttons[ text_of('new-tag-close') ] = function(){
			dlg.close();
		};
		dlg = adiary.dialog(div, {
			modal:	true,
			width:	Math.min(960, document.documentElement.clientWidth - 20),
			minHeight: 300,
			title:	btn.dataset.title,
			buttons: buttons,
			beforeClose: function(){ dialog.remove(); }
		});
		load_list();
	});
}

//##############################################################################
// ■保存していない変更があるまま離れるときの確認
//##############################################################################
// タブを閉じる、再読み込み、リンク、戻るなどで離れるときに確かめる（Lyndbaumの admin-unsaved.js と同じ）。
// 開いたときの中身を覚えておき、離れるときに今の中身と比べる（書き換えても元に戻せば確かめない。
// タグやアイキャッチ画像など、JavaScriptで変えた欄も比べる）。mediaから貼り付けて開いたときは、
// 貼り付けた本文（edit-helper.jsが後で入れる）が変更になる。
// 記事の保存と削除で送るときは確かめない。確かめる文言はブラウザが決める（ページからは変えられない）
let submitting = false;
{
	const form = document.querySelector('form[name="edit"]');
	// 固定ページの一覧を読み込んだ後に決まる欄（親を選び、パーマリンクを補う）
	const late = { upnode: true, link_key_txt: true };

	// 名前のある欄の値を並べたもの。編集ロックで無効にした欄も比べる。
	// ファイルの欄と、ブラウザに覚えさせる設定（js-save）は比べない
	function snapshot(is_late) {
		const pairs = [];
		Array.from(form.elements).forEach(function(el){
			if (!el.name || !late[el.name] !== !is_late) return;
			if (/^(?:submit|button|reset|file)$/.test(el.type) || el.classList.contains('js-save')) return;
			if ((el.type === 'checkbox' || el.type === 'radio') && !el.checked) return;
			pairs.push([ el.name, val_of(el) ]);
		});
		return JSON.stringify(pairs);
	}
	const initial = snapshot();
	let initial_late;
	contents_loaded.then(function(){ initial_late = snapshot(true) });

	function changed() {
		return snapshot() !== initial
		    || (initial_late !== undefined && snapshot(true) !== initial_late);
	}

	// 送るのを取りやめたとき（競合の確認、削除の確認で「キャンセル」など）は、確かめる対象のまま。
	// 削除の確認（js-check-form）の後は、asys.js が requestSubmit で送るので、ここに届く
	window.addEventListener('submit', function(evt){
		if (!evt.defaultPrevented && evt.target.closest && evt.target.closest('#edit')) submitting = true;
	});
	// 送った後に「戻る」で戻ってきたとき（bfcache）は、また確かめる
	window.addEventListener('pageshow', function(evt){
		if (evt.persisted) submitting = false;
	});
	window.addEventListener('beforeunload', function(evt){
		if (submitting || !changed()) return;
		evt.preventDefault();
		evt.returnValue = '';
	});
}

//##############################################################################
// ■保存の競合の確認（ほかの画面で先に保存されていないか）
//##############################################################################
// 保存する前に今の記事の要約を取り寄せ、この画面を開いたときの要約と比べる。
// 違えば保存せず、今の記事とこの画面の本文の差分を見せる。
// 取り寄せに失敗したときはそのまま送る（サーバー側でも確かめる）。
{
	const form   = document.querySelector('form[name="edit"]');
	const digest = document.getElementById('edit-digest');
	const dialog = adiary.secure('#conflict-dialog');
	if (dialog) dialog.remove();
	const title  = dialog.querySelector('#conflict-title');
	const body   = dialog.querySelector('#conflict-body');
	let checked = false;

	function submit(submitter) {
		if (form.requestSubmit) {
			// submitイベントは同期で起きる。入力のチェックで止まったら、次はまた確かめる
			checked = true;
			submitter ? form.requestSubmit(submitter) : form.requestSubmit();
			checked = false;
			return;
		}
		if (submitter && submitter.name) {	// 押したボタン（下書き保存など）を送る
			const inp = create('input');
			inp.setAttribute('type',  'hidden');
			inp.setAttribute('name',  submitter.name);
			inp.setAttribute('value', submitter.value);
			form.appendChild(inp);
		}
		submitting = true;	// form.submit() は submit イベントが起きない
		form.submit();
	}

	function show_conflict(now, submitter) {
		const text = now.text.replace(/\r\n?/g, "\n");
		const mine = edit.value.replace(/\r\n?/g, "\n");
		const now_title  = adiary.tag_decode(now.title);
		const mine_title = form.querySelector('input[name="title"]').value;

		title.innerHTML = '';
		if (now_title !== mine_title)
			title.textContent = text_of('conflict-title-diff').replace('%n', now_title).replace('%m', mine_title);
		body.innerHTML = '';
		body.classList.remove('rev-full');
		if (text === mine) {
			body.textContent = text_of('conflict-same-body');
		} else {
			const diff = line_diff(text.split("\n"), mine.split("\n"));
			if (diff) render_diff(diff, body);
			else {
				body.classList.add('rev-full');
				body.textContent = text_of('rev-too-large') + "\n\n" + text;
			}
		}
		dialog.querySelector('#conflict-open').setAttribute('href', adiary.myself2 + '0' + now.pkey);

		const div = create('div');
		div.appendChild(dialog);
		let dlg;
		const buttons = {};
		buttons[ text_of('conflict-save') ] = function(){
			digest.value = now.digest;	// 今の記事を見た上で上書きする
			dlg.close();
			submit(submitter);
		};
		buttons[ text_of('conflict-cancel') ] = function(){
			dlg.close();
		};
		dlg = adiary.dialog(div, {
			modal:	true,
			width:	Math.min(960, document.documentElement.clientWidth - 20),
			minHeight: 300,
			title:	dialog.dataset.title,
			buttons: buttons,
			beforeClose: function(){ dialog.remove(); }
		});
	}

	form.addEventListener('submit', function(evt){
		if (checked || !digest) return;
		evt.preventDefault();
		const submitter = evt.submitter;
		post_json(adiary.myself + '?etc/ajax_dummy', new URLSearchParams({ action: 'ajax_revision', now: document.getElementById('edit-pkey').value }), {
			success: function(now){
				if (!now || now.digest === digest.value) return submit(submitter);
				show_conflict(now, submitter);
			},
			error: function(){ submit(submitter) }
		});
	});
}

//##############################################################################
// ■公開状態の変更
//##############################################################################
{
	const echk = document.getElementById('enable-chk');
	const dchk = document.getElementById('draft-chk');
	if (echk) echk.addEventListener('change', echk_change);
	if (dchk) dchk.addEventListener('change', echk_change);
	echk_change();

	function set_title(text) {
		document.querySelectorAll('.save-btn-title').forEach(function(x){ x.textContent = text });
	}
	function echk_change() {
		if (dchk && dchk.checked) {	// 下書き
			set_title( dchk.dataset.on );
			return;
		}
		if (!echk) return;
		if (echk.checked)
			set_title( echk.dataset.on );
		else
			set_title( echk.dataset.off );
	}
}

//##############################################################################
// ■upnodeの変更 / link_keyの設定
//##############################################################################
{
	const lkey = document.getElementById('link-key');
	let   lkey_set;	// 補った値（そのままなら、親を選び直したときに補い直す）

	// data-suggest は "1" か "0" か ""。今までの jQuery の .data() は "0" を数の0（偽）にしていた
	const suggest = lkey && !/^(?:|0|false|null)$/.test(lkey.dataset.suggest || '');

	if (upsel && lkey) upsel.addEventListener('change', function(){
		if (! suggest) return;	// 機能がoff
		var val = lkey.value;
		if (val != '' && val != lkey_set) return;

		const opt = upsel.selectedOptions[0];
		if (!opt) return;

		var set = opt.dataset.link_key;
		if (set == undefined) return;
		if (set.substr(-1) != '/') set += '/';
		lkey.value = set;
		lkey_set   = set;
	});
}

//##############################################################################
// ■ファイルアップロード機能
//##############################################################################
const upform   = document.getElementById('upload-form');
if (upform) upform.remove();
const file_btn = upform.querySelector('#file-btn');
const file_div = upform.querySelector('#file-btn-div');
const fileup   = adiary.secure('#edit-file-upload');
//------------------------------------------------------------------------------
// ●アップロードダイアログ
//------------------------------------------------------------------------------
fileup.addEventListener('click', function(){
	update_files_view([]);
	open_upload_dialog();
});
function open_upload_dialog(files) {
	const div = create('div');
	div.appendChild( upform );

	if (files) {
		hide(file_div);
		update_files_view(files);
	} else {
		show(file_div);
	}

	// ボタンの設定
	let dlg;
	var buttons = {};
	buttons['Upload'] = function(){
		if (!files && !file_btn.value) return;	// no selected

		div.parentElement.querySelectorAll('.ui-button').forEach(function(x){ x.disabled = true });

		ajax_upload( upform, files, {
			callback: function(data, folder){
				const thumb = upform.querySelector('#paste-thumbnail');
				upload_files_insert(data, {
					folder:		folder,
					thumbnail:	thumb.value == '0' ? false : true,
					text:		thumb.value == 'text',	// 画像へのテキストリンク
					caption:	upform.querySelector('#paste-caption').value,
					exif:		upform.querySelector('#paste-to-exif').checked,
					class:		upform.querySelector('#paste-class').value
				});
			},
			complete: function(){
				upform.remove();
				dlg.close();
				div.remove();
			}
		});

		file_btn.value = '';
	};
	buttons[ adiary.msg('cancel') ] = function(){
		upform.remove();
		dlg.close();
		div.remove();
	};

	dlg = adiary.dialog(div, {
		modal: true,
		width:  adiary.DialogWidth,
		// minHeight: 200,
		title:   fileup.dataset.title,
		buttons: buttons
	});
}
//------------------------------------------------------------------------------
// ●選択ファイル一覧表示 / ファイル選択後の処理
//------------------------------------------------------------------------------
function update_files_view(files) {
	const box = upform.querySelector('#dnd-files');
	box.innerHTML = '';
	for(var i=0; i<files.length; i++) {
		if (!files[i]) continue;
		var fs  = adiary.size_format(files[i].size);
		const div = create('div');
		div.textContent = files[i].name + ' (' + fs + ')';
		box.appendChild(div);
	}
}

file_btn.addEventListener('change', function() {
	var files = file_btn.files;
	update_files_view(files)
});

//------------------------------------------------------------------------------
// ●アップロード後の処理
//------------------------------------------------------------------------------
function upload_files_insert(data, opt) {
	try {
		data['fail']    = parseInt(data['fail']);
		data['success'] = parseInt(data['success']);
		data['ret']     = parseInt(data['ret']);
	} catch(e) {
	}

	if (data['fail']) {
		adiary.show_error('#msg-upload-fail', {
			n: data['fail'] + data['success'],
			f: data['fail'],
			s: data['success']
		});
		return;
	} else if (data['ret']) {
		adiary.show_error('#msg-upload-error');
		return;
	}

	// 記事に挿入
	var ary = data['files'];
	if (!data['success'] || !ary) return;

	let files = [];
	for(var i=0; i<ary.length; i++) {
		let file = ary[i];
		let reg  = file.name.match(/\.(\w+)$/);
		let ext  = reg ? reg[1] : '';
		files.push({
			folder: opt.folder,
			file:	file.name,
			ext:	ext,
			isimg:	file.isImg,
			exif:	file.isImg && opt.exif,
			thumbnail: opt.thumbnail,
			text:	opt.text ? true : false
		});
	}

	insert_image({
		caption: opt.caption,
		class:   opt.class,
		files: files
	});

	// 動画のサムネイルを作る（docs/仕様/動画のサムネイル.md）。作り終わる前に保存しても、作り終わったときに記事を作り直す
	const videos = ary.filter(function(file){ return file.isVideo }).map(function(file){
		return { folder: opt.folder, name: file.name };
	});
	if (videos.length)
		adiary.make_video_thumbnails(videos, adiary.Basepath + text_of('image-dir'));
}

//------------------------------------------------------------------------------
// ●アップロード処理
//------------------------------------------------------------------------------
function get_upload_folder() {
	var date = document.getElementById('edit-date').value.toString() || '';
	var year;
	var mon;
	if (date.match(/^\d\d\d\d[\-\/]\d\d/)) {
		year = date.substr(0,4);
		mon  = date.substr(5,2);
	} else {
		var d = new Date();
		year = d.getFullYear();
		mon  = (101 + d.getMonth()).toString().substr(1);
	}
	var folder = fileup.dataset.folder;
	if (folder == '') folder='posts/%y/';
	return folder.replace('%y', year).replace('%m', mon).replace(/^\/+/, '');
}

function ajax_upload( form_dom, files, option ) {
	var folder = get_upload_folder();

	// FormData生成
	var fd = new FormData( form_dom );
	if (!file_btn.value) fd.delete('_file_btn');
	fd.append('action', 'etc/ajax_upload');
	fd.append('folder', folder);

	// DnDされたファイル
	if (files) {
		for(var i=0; i<files.length; i++) {
			if (!files[i]) continue;
			fd.append('file_ary', files[i]);
		}
	}

	// progress bar init
	const prog  = form_dom.querySelector('#progress') || document.getElementById('progress');
	const label = prog.querySelector('.label');
	label.textContent = '';
	show(prog);
	const bar = adiary.progressbar(prog, {
		value: 0,
		change: function(value) {
			label.textContent = value + "%";
		},
		complete: function() {
			label.textContent = "Upload complete!";
		}
	});

	// submit処理
	post_json(adiary.myself + '?etc/ajax_dummy', fd, {
		error: function(xhr) {
			console.log('[ajax_upload()] http post fail');
			adiary.show_error('#msg-upload-error');
		},
		success: function(data) {
			console.log('[ajax_upload()] http post success');
			if (option.callback) option.callback(data, folder);
		},
		complete: function(xhr) {
			hide(prog);
			if (option.complete) option.complete(xhr);
		},
		progress: function(e) {
			var par = Math.floor(e.loaded*100/e.total + 0.5);
			bar.set(par);
		}
	});
}
//------------------------------------------------------------------------------
// ●ドラッグ＆ドロップ
//------------------------------------------------------------------------------
// CodeMirrorのとき（edit-cm.js）は、その枠で受ける。CodeMirrorはファイルを文字として
// 入れてしまうので、それより先に受けるよう捕捉の段階で受ける
const edit_box = document.getElementById('editarea-cm') || edit;
edit_box.addEventListener('dragover', function(evt) {
	evt.stopPropagation();
	evt.preventDefault();
}, true);
edit_box.addEventListener('drop', function(evt) {
	evt.stopPropagation();
	evt.preventDefault();

	if (edit.readOnly) return;
	if (!evt.dataTransfer) return;

	var files = evt.dataTransfer.files;
	if (!files || !files.length) return;
	if (!window.FormData) return;

	// ダイアログを出す
	open_upload_dialog(files);
});

//##############################################################################

//------------------------------------------------------------------------------
// ●クリップボードからのコピペ
//------------------------------------------------------------------------------

const uploadFile = (file, successCb, errorCb) => {
	const folder = get_upload_folder();

	const fd = new FormData();

	fd.append('paste', 1); // 謎パラメタ
	fd.append('action', 'etc/ajax_upload');
	fd.append('folder', folder);
	fd.append('file_ary', file);

	// submit処理
	post_json(`${adiary.myself}?etc/ajax_dummy`, fd, {
		error: function(xhr) {
			console.log('[ajax_upload()] http post fail');
			//errorCb;
		},
		success: function(data) {
			console.log('[ajax_upload()] http post success');
			successCb(data, folder);
		}
	});
}

window.onload = () => {
	/** @type {HTMLElement} */
	const txt = edit_box;	// CodeMirrorのときはその枠（ドラッグ＆ドロップと同じ）
	txt.onpaste = (e) => {
		if (e.clipboardData.files.length) {
			const pasteFile = e.clipboardData.files[0];
			const ext = pasteFile.name.match(/\.([^\.]+)$/)[1];
			const dt = new Date();
			const timestamp = `${dt.getFullYear()}-${dt.getMonth() + 1}-${dt.getDate()}_${dt.getHours()}-${dt.getMinutes()}-${dt.getSeconds()}-${dt.getMilliseconds()}`
			const file = new File([pasteFile], `paste-image-${timestamp}.${ext}`, { type: pasteFile.type });
			uploadFile(file, (data, folder) => {
				upload_files_insert(data, {
					folder:		folder,
					// 編集画面の設定（skel/edit.html）
					thumbnail:	fileup.dataset.paste != 'large',
					caption:	'',
					exif:		fileup.dataset.exif == 1,
					class:		fileup.dataset.class
				});
			});
		} else {
			// 何もしない
		}
	}
};

});
