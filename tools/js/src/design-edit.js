//##############################################################################
// adiaryデザイン編集用JavaScript
//							(C)2013-2016 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';
////////////////////////////////////////////////////////////////////////////////
// ●モジュール情報のロード
////////////////////////////////////////////////////////////////////////////////
// プラグインのCSS設定画面（css_setting.html）が使う。$f、$fsec は iframe の jQuery と $secure
var $f;
var $fsec;
var loading_css_flag;
adiary.ready(function(){
	var iframe = document.getElementById('iframe');
	var module_data_id   = '#design-modules-data';
	var module_selector  = '[data-module-name]';
	var not_sortable     = ':not([data-fix])';

	var btn_save = document.getElementById('save-btn');
	var btn_close_title   = text_of('btn-close')   || 'delete';
	var btn_setting_title = text_of('btn-setting') || 'setting';
	var btn_cssset_title  = text_of('btn-css-setting') || 'design setting';

	//----------------------------------------------------------------------
	// サブルーチン
	//----------------------------------------------------------------------
	function text_of(id) {
		const dom = document.getElementById(id);
		return dom ? dom.textContent : '';
	}
	function html_of(id) {
		const dom = document.getElementById(id);
		return dom ? dom.innerHTML : '';
	}
	function create(tag, cls, doc) {
		const dom = (doc || document).createElement(tag);
		if (cls) dom.className = cls;
		return dom;
	}
	function children(ary, sel) {
		const ret = [];
		for(const el of ary)
			for(const c of el.children) if (c.matches(sel)) ret.push(c);
		return ret;
	}
	// jQueryの .show()、.hide()（hide は display:none、show は外し、CSSで隠れていれば既定の表示にする）
	function show(dom) {
		if (dom.style.display === 'none') dom.style.display = '';
		const win = dom.ownerDocument.defaultView;
		if (win.getComputedStyle(dom).display !== 'none') return;
		const tmp = dom.ownerDocument.body.appendChild( dom.ownerDocument.createElement(dom.nodeName) );
		let d = win.getComputedStyle(tmp).display;
		tmp.remove();
		dom.style.display = (d === 'none') ? 'block' : d;
	}
	function hide(dom) {
		dom.style.display = 'none';
	}
	// jQueryの .offset()、.outerWidth()、.height()
	function offset_of(dom) {
		if (!dom.getClientRects().length) return { top: 0, left: 0 };
		const r   = dom.getBoundingClientRect();
		const win = dom.ownerDocument.defaultView;
		return { top: r.top + win.pageYOffset, left: r.left + win.pageXOffset };
	}
	function css_size(dom, dim, outer) {
		const cs  = dom.ownerDocument.defaultView.getComputedStyle(dom);
		const val = cs[dim];
		const ary = dim === 'width' ? ['Left', 'Right'] : ['Top', 'Bottom'];
		let   pb  = 0;
		for(const s of ary)
			pb += (parseFloat(cs['padding' + s]) || 0) + (parseFloat(cs['border' + s + 'Width']) || 0);
		if (val === 'auto' || isNaN(parseFloat(val))) {
			const x = dim === 'width' ? dom.offsetWidth : dom.offsetHeight;
			return outer ? x : x - pb;
		}
		const border_box = cs.boxSizing === 'border-box';
		const x = parseFloat(val);
		if (outer) return border_box ? x : x + pb;
		return border_box ? x - pb : x;
	}
	// jQueryの .data() と同じく、data-* の値を変換する（"0" は数の0など）
	function jq_value(s) {
		if (s === undefined || s === null) return undefined;
		if (s === 'true')  return true;
		if (s === 'false') return false;
		if (s === 'null')  return null;
		if (s === +s + '') return +s;
		if (/^(?:\{[\w\W]*\}|\[[\w\W]*\])$/.test(s)) {
			try { return JSON.parse(s) } catch(e) { /* そのまま */ }
		}
		return s;
	}
	// モジュールの情報（今までの jQuery の .data()）。初めて読んだときに data-* を取り込む
	const mstore = new WeakMap();
	function camel(key) {
		return key.replace(/-([a-z])/g, function(w, c){ return c.toUpperCase() });
	}
	function mdata_all(el) {
		let h = mstore.get(el);
		if (h) return h;
		h = {};
		for(const k in el.dataset) h[k] = jq_value(el.dataset[k]);
		mstore.set(el, h);
		return h;
	}
	function mdata(el, key, val) {
		const h = mdata_all(el);
		if (arguments.length > 2) h[camel(key)] = val;
		return h[camel(key)];
	}

	var modules = {};	// 各モジュールを取得し保存
	var mod_list= [];
	var data = adiary.secure(module_data_id);
	if (data) Array.from(data.children).forEach(function(obj){
		if (!obj.matches(module_selector)) return;
		var name = String(mdata(obj, 'module-name'));
		obj.remove();
		if (name.match(/[^\w\-]/)) return;
		modules[name] = obj;
		mod_list.push(name);
	});

////////////////////////////////////////////////////////////////////////////////
// ●iframeの自動リサイズ
////////////////////////////////////////////////////////////////////////////////
	var body = document.getElementById('body');
	// jQueryの $(body).height()、$(iframe).position().top と同じ値を求める
	function body_height() {
		return css_size(body, 'height');
	}
	function iframe_top() {
		const op = iframe.offsetParent || document.documentElement;
		const pr = op.getBoundingClientRect();
		const pt = pr.top + (parseFloat(getComputedStyle(op).borderTopWidth) || 0);
		return iframe.getBoundingClientRect().top - pt - (parseFloat(getComputedStyle(iframe).marginTop) || 0);
	}
	iframe_resize();
	window.addEventListener('resize', iframe_resize);
	function iframe_resize() {
		var h = body_height() - iframe_top();
		const dbg = document.getElementById('debug-msg');
		if (dbg) dbg.innerHTML = body_height() + ' / ' + iframe_top();
		iframe.style.height = h + 'px';
	}


////////////////////////////////////////////////////////////////////////////////
// ●初期化処理
////////////////////////////////////////////////////////////////////////////////
var iframe_onload;
iframe.addEventListener('load', on_iframe_load);
function on_iframe_load(){
	if (iframe_onload) return;
	iframe_onload = true;
	var if_cw = iframe.contentWindow;
	var doc   = iframe.contentDocument;
	    $f    = if_cw.$;		// global（プラグインのCSS設定画面が使う）
	    $fsec = if_cw.$secure;	// global
	// iframeの中で探す
	function F(sel) {
		return Array.from(doc.querySelectorAll(sel));
	}
	function fsec(sel) {	// 同じidが2つ以上あるときは使わない
		const id   = sel.replace(/^#/, '');
		const list = doc.querySelectorAll('[id="' + id.replace(/["\\]/g, '\\$&') + '"]');
		return list.length == 1 ? [ list[0] ] : [];
	}
	var side_a = fsec('#side-a');
	var side_b = fsec('#side-b');
	var f_main = fsec('#main-first');
	var f_head = fsec('#header');
	var f_hdiv = children(f_head, 'div:first-child');
	var view_mode;
	var zidx_module;	// hoverによる操作ボタン優先度の入れ替え用
	var sortables = [];	// 並べ替え（下の sortable()）
	var drag;		// 動かしている間の情報

	// フレーム内check
	const fbody = doc.getElementById('body');
	if (fbody && fbody.classList.contains('system-mode')) {
		btn_save.disabled = true;
		return;
	}
	btn_save.disabled = false;

	// 複数記事表示の2つ目のモジュールを除去
	F('#art-2 ' + module_selector).forEach(function(x){ x.removeAttribute('data-module-name') });

	// モジュールにボタン追加
	F(module_selector).forEach( function(obj){
		init_module( obj );
	});

	// 記事本体（単一表示）
	var selector= '>' + module_selector + not_sortable;
	var artbody = F('#article-box div.body');
	var arthead = children(artbody, 'div.body-header');
	var artfoot = children(artbody, 'div.body-footer');
	var artmain = children(artbody, 'div.body-main');
	sortable(arthead, { items: selector, connectWith: artfoot });
	sortable(artfoot, { items: selector, connectWith: arthead });
	arthead.forEach(function(x){ x.style.minHeight = '16px' });
	artfoot.forEach(function(x){ x.style.minHeight = '16px' });
	if (artmain.length && css_size(artmain[0], 'height') > 300)
		artmain.forEach(function(x){
			x.style.height       = '300px';
			x.style.overflowY    = 'hidden';
			x.style.marginBottom = '12px';
			x.style.borderBottom = '2px dashed #900';
		});
	// コメント欄
	var combody = F('#com>div.commentbody');
	var comview = children(combody, 'div.commentview');
	comview.forEach(hide);

	// 記事本体（複数表示）
	var martbody = F('#art-1 div.body');
	var marthead = children(martbody, 'div.body-header');
	var martfoot = children(martbody, 'div.body-footer');
	var martmain = children(martbody, 'div.body-main');
	marthead.forEach(function(x){ x.style.minHeight = '16px' });
	martfoot.forEach(function(x){ x.style.minHeight = '16px' });

	// sortable設定
	sortable(side_a, { items: selector, connectWith: side_b });
	sortable(side_b, { items: selector, connectWith: side_a });
	sortable(f_hdiv, { items: selector });
	sortable(f_main, {
			items: selector + ', #article-box' + ', #articles>article, #articles ' + selector,
			cancel: 'article:not(' + module_selector + ')',
			update: main_update
	});
	sortable(marthead, { items: selector, connectWith: martfoot });
	sortable(martfoot, { items: selector, connectWith: marthead });

	// iframe内のリンク書き換え
	F('a').forEach(function(obj) {
		var url = obj.getAttribute('href');
		if (!url) return;

		// if (url.substr(0, if_cw.adiary.myself.length) != if_cw.adiary.myself
		//  || url.indexOf('?&')<0 && 0<url.indexOf('?')) {
			obj.setAttribute('target', '_top');
		//}
	});

////////////////////////////////////////////////////////////////////////////////
// ●並べ替え（今までの jQuery UI の sortable の代わり）
////////////////////////////////////////////////////////////////////////////////
// つかんだモジュールがマウスについて動き、入る所に空き（ui-sortable-placeholder）を開ける。
// マウスとペンだけ（今までの jQuery UI と同じく、タッチでは並べ替えない）。
//	containers	並べ替える入れ物（配列）
//	opt.items	並べ替えるもの（入れ物からの選択子。">" で始まるものは直下）
//	opt.connectWith	行き来できる入れ物（配列）
//	opt.cancel	ここをつかんだときは始めない（closest で見る）
//	opt.update	並びが変わったときに呼ぶ
function sortable(containers, opt) {
	for(const el of containers) {
		const s = {
			el:	 el,
			items:	 opt.items.split(',').map(function(x){ x = x.trim(); return x.substr(0,1) == '>' ? ':scope ' + x : x }).join(', '),
			connect: opt.connectWith || [],
			cancel:	 opt.cancel || 'input, textarea, button, select, option',
			update:	 opt.update
		};
		sortables.push(s);
		el.classList.add('ui-sortable');
		// jQuery UI と同じく、中の ui-sortable-handle をいったん外してから、自分のものに付ける
		// （メインは記事の上下より後に作るので、記事の上下のモジュールには付かない。つかめるのは同じ）
		el.querySelectorAll('.ui-sortable-handle').forEach(function(x){ x.classList.remove('ui-sortable-handle') });
		items_of(s).forEach(function(x){ x.classList.add('ui-sortable-handle') });
		el.addEventListener('pointerdown', function(evt){ sort_down(s, evt) });
	}
}
function items_of(s) {
	return Array.from(s.el.querySelectorAll(s.items));
}
function group_of(s) {	// 入れられる並べ替え（自分と、つないだ入れ物）
	return sortables.filter(function(x){ return x === s || s.connect.indexOf(x.el) >= 0 });
}
function sort_down(s, evt) {
	if (evt._sort_handled || drag) return;		// 内側の並べ替えが受けた
	if (evt.pointerType === 'touch' || evt.button !== 0) return;
	if (evt.target.closest(s.cancel)) return;

	// つかんだもの（この並べ替えのもの）
	const items = items_of(s);
	let item = evt.target;
	while(item && item !== s.el && items.indexOf(item) < 0) item = item.parentElement;
	if (!item || item === s.el) return;
	evt._sort_handled = true;

	drag = { s: s, item: item, x0: evt.pageX, y0: evt.pageY, started: false, id: evt.pointerId };
	doc.addEventListener('pointermove',   sort_move);
	doc.addEventListener('pointerup',     sort_up);
	doc.addEventListener('pointercancel', sort_cancel);
	doc.addEventListener('keydown',       sort_key);
}
function sort_start() {
	const item = drag.item;
	const win  = doc.defaultView;
	const r    = item.getBoundingClientRect();
	drag.style  = item.getAttribute('style');
	drag.parent = item.parentNode;
	drag.next   = item.nextSibling;

	// 空き（同じタグ、同じクラス、同じ大きさ）
	const w = css_size(item, 'width');
	const h = css_size(item, 'height');
	// 大きさは、jQuery UI と同じく、CSSで大きさが決まらないときだけ入れる
	// （.design-module-edit は min-height があるので、高さは入らない）
	const ph = doc.createElement(item.nodeName);
	ph.className = 'ui-sortable-placeholder ' + item.className;
	ph.classList.remove('ui-sortable-helper');
	ph.style.visibility = 'hidden';
	item.after(ph);
	if (!css_size(ph, 'height')) ph.style.height = h + 'px';
	if (!css_size(ph, 'width'))  ph.style.width  = w + 'px';
	drag.ph = ph;

	// つかんだものを、元の所に浮かせる
	item.classList.add('ui-sortable-helper');
	item.style.width  = w + 'px';
	item.style.height = h + 'px';
	item.style.position = 'absolute';
	item.style.zIndex   = 1000;
	item.style.pointerEvents = 'none';	// 下にあるものを見つけるため
	const op  = item.offsetParent || doc.documentElement;
	const opr = op.getBoundingClientRect();
	const ocs = win.getComputedStyle(op);
	const ics = win.getComputedStyle(item);
	drag.left0 = r.left - opr.left - (parseFloat(ocs.borderLeftWidth) || 0) + op.scrollLeft - (parseFloat(ics.marginLeft) || 0);
	drag.top0  = r.top  - opr.top  - (parseFloat(ocs.borderTopWidth)  || 0) + op.scrollTop  - (parseFloat(ics.marginTop)  || 0);
	item.style.left = drag.left0 + 'px';
	item.style.top  = drag.top0  + 'px';

	drag.select = doc.body.style.userSelect;
	doc.body.style.userSelect = 'none';
	drag.started = true;
}
function sort_move(evt) {
	if (!drag || evt.pointerId !== drag.id) return;
	if (!drag.started) {
		if (Math.max(Math.abs(evt.pageX - drag.x0), Math.abs(evt.pageY - drag.y0)) < 1) return;
		sort_start();
	}
	evt.preventDefault();
	const item = drag.item;
	item.style.left = (drag.left0 + evt.pageX - drag.x0) + 'px';
	item.style.top  = (drag.top0  + evt.pageY - drag.y0) + 'px';

	// 端に近づいたら、iframeの中をスクロールする
	const win = doc.defaultView;
	if (evt.clientY < 20)			win.scrollBy(0, -20);
	else if (win.innerHeight - evt.clientY < 20) win.scrollBy(0, 20);

	place(evt.clientX, evt.clientY);
}
// マウスの下に空きを動かす
function place(x, y) {
	const ph    = drag.ph;
	const item  = drag.item;
	const group = group_of(drag.s);
	const under = doc.elementFromPoint(x, y);
	if (!under) return;

	// 入れられるもの
	let cands = [];
	for(const g of group) cands = cands.concat( items_of(g) );
	cands = cands.filter(function(c){ return c !== item && !item.contains(c) && c !== ph });

	// マウスの下のもの
	let el = under;
	while(el && cands.indexOf(el) < 0) el = el.parentElement;
	if (el) {
		const r = el.getBoundingClientRect();
		if (y < r.top + r.height/2) { if (el.previousElementSibling !== ph) el.before(ph); }
		else			    { if (el.nextElementSibling !== ph)     el.after(ph);  }
		return;
	}
	// マウスの下の入れ物（いちばん内側）
	let box = under;
	while(box && !group.some(function(g){ return g.el === box })) box = box.parentElement;
	if (!box) return;
	const s  = group.find(function(g){ return g.el === box });
	const in_box = cands.filter(function(c){ return items_of(s).indexOf(c) >= 0 });
	if (!in_box.length) {
		if (ph.parentNode !== box) box.appendChild(ph);
		return;
	}
	// 入れ物の中の、いちばん近いものの前か後ろ
	let near, dist;
	for(const c of in_box) {
		const r = c.getBoundingClientRect();
		const d = y < r.top ? r.top - y : (y > r.bottom ? y - r.bottom : 0);
		if (near === undefined || d < dist) { near = c; dist = d; }
	}
	const r = near.getBoundingClientRect();
	if (y < r.top + r.height/2) { if (near.previousElementSibling !== ph) near.before(ph); }
	else			    { if (near.nextElementSibling !== ph)     near.after(ph);  }
}
function sort_end(cancel) {
	doc.removeEventListener('pointermove',   sort_move);
	doc.removeEventListener('pointerup',     sort_up);
	doc.removeEventListener('pointercancel', sort_cancel);
	doc.removeEventListener('keydown',       sort_key);
	const d = drag;
	drag = null;
	if (!d || !d.started) return;

	const item = d.item;
	if (cancel) d.ph.remove();
	       else d.ph.replaceWith(item);
	if (cancel) d.parent.insertBefore(item, d.next);
	item.classList.remove('ui-sortable-helper');
	if (d.style === null) item.removeAttribute('style');
		else	      item.setAttribute('style', d.style);
	doc.body.style.userSelect = d.select;

	// ドラッグの直後のクリック（離したときに起きる）は止める（今までの jQuery UI と同じ）。
	// クリックは pointerup と同じ流れで起きるので、その後には外す
	const stop = function(evt){
		evt.stopPropagation();
		evt.preventDefault();
	};
	doc.addEventListener('click', stop, true);
	setTimeout(function(){ doc.removeEventListener('click', stop, true) }, 0);

	if (cancel) return;
	const moved = item.parentNode !== d.parent || item.nextSibling !== d.next;
	if (!moved) return;
	for(const g of group_of(d.s)) {
		if (!g.update) continue;
		if (g.el.contains(item) || g.el.contains(d.parent)) g.update();
	}
}
function sort_up(evt)     { if (drag && evt.pointerId === drag.id) sort_end(false) }
function sort_cancel(evt) { if (drag && evt.pointerId === drag.id) sort_end(true)  }
function sort_key(evt)    { if (evt.keyCode == 27) sort_end(true) }

////////////////////////////////////////////////////////////////////////////////
// ●モード切り替え
////////////////////////////////////////////////////////////////////////////////
var article_box = doc.getElementById('article-box');
var articles    = doc.getElementById('articles');
var view_sel    = document.getElementById('view-mode');
function view_change(){
	var val = view_sel.value;
	if (view_mode == val) return;

	if (view_mode == undefined) {
		if (article_box && articles) article_box.after( articles );
	}
	view_mode = val;
	if (!article_box || !articles) return;
	if (val == '_article') {
		articles.before( article_box );
		hide(articles);
		show(article_box);
	} else {
		article_box.after( articles );
		show(articles);
		hide(article_box);
	}
}
view_sel.addEventListener('change', view_change);
view_change();

////////////////////////////////////////////////////////////////////////////////
// ●要素の位置調整
////////////////////////////////////////////////////////////////////////////////
//※複数表示モードでの main_a/b 相当の位置にある要素を、正しい位置に移動。
//
function main_update() {
	if (!articles) return;
	var items = children([articles], module_selector + ', #art-1, #art-2');

	// main_a
	var i=0;
	for(; i<items.length; i++) {
		var id = items[i].getAttribute('id');
		if (id == 'art-1') break;
		article_box.before( items[i] );
	}
	for(i++; i<items.length; i++) {
		var id = items[i].getAttribute('id');
		if (id == 'art-2') break;
	}
	// main_b
	for(i++; i<items.length; i++) {
		articles.after( items[i] );
	}
}

////////////////////////////////////////////////////////////////////////////////
// ●要素タイプの選択
////////////////////////////////////////////////////////////////////////////////
var mod_type = document.getElementById('module-type');
var add_sel  = document.getElementById('add-module');
function type_change(){
	var type = mod_type.value;
	var sel  = add_sel;
	sel.innerHTML = '';
	var o0 = create('option');
	o0.value = '';
	o0.textContent = text_of('msg-append-module-select');
	sel.appendChild(o0);
	var t = (type == 'between') ? 'main' : type ;
	for(var i=0; i<mod_list.length; i++) {
		var name = mod_list[i];
		var mod = modules[name];
		if (String(mdata(mod, 'type')).indexOf(t)<0) continue;
		//
		var first = mod.firstElementChild;
		var id = first && first.getAttribute('id');
		if (id) {
			const x = doc.getElementById(id);
			if (x && jq_value(x.dataset.fix)) continue;	// 固定要素は無視
		} else {
			const x = doc.querySelector('[data-module-name="' + name + '"]');
			if (x && jq_value(x.dataset.fix)) continue;
		}

		// 追加
		var o = create('option');
		o.setAttribute('value', name);
		o.textContent = mod.getAttribute('title');
		sel.appendChild(o);
	}
	if (type == 'between') {
		view_sel.value = '_main';
		view_change();
		view_sel.disabled = true;
	} else {
		view_sel.disabled = false;
	}
	if (type == 'main') {
		view_sel.value = '_article';
		view_change();
	}
}
mod_type.addEventListener('change', type_change);
type_change();

////////////////////////////////////////////////////////////////////////////////
// ●要素を追加する
////////////////////////////////////////////////////////////////////////////////
add_sel.addEventListener('change', function(evt){
	var name = add_sel.value;
	if (name == '') return;
	add_sel.value = '';

	var mod = modules[ name ];
	if (!mod || !mod.firstElementChild) return;
	var obj = doc.importNode(mod.firstElementChild, true);
	mdata(obj, 'module-name', name);
	obj.setAttribute('data-module-name', name);

	var id = obj.getAttribute('id');
	if (id && doc.getElementById(id)) {	// 同じidが既に存在する、↓同じモジュール名が存在する
		adiary.show_error( '#msg-duplicate-id', {
			n: mod.getAttribute('title') || name
		});
		return false;
	}

	// data-id to id
	obj.querySelectorAll('*[data-id]').forEach(function(el){
		el.setAttribute('id', String(jq_value(el.getAttribute('data-id'))));
	});

	// 多重インストールが許可されている場合、エイリアスを作る
	if (!id) {
		name = String(mdata(obj, 'module-name'));
		for(var i=1; i<9999; i++) {
			var name2 = name + ',' + i.toString();
			if (doc.querySelector('*[data-module-name="'+ name2 +'"]')) continue;
			break;
		}
		mdata(obj, 'module-name', name2);
		obj.setAttribute('data-module-name', name2);	// 必須
		name = name2;
		id = name.replace(/_/g, '-').replace(',', '');
		obj.setAttribute('id', id);			// 個別CSS適用のための細工
	}

	// 追加
	var type = mod_type.value;
	if (type == 'header')	f_hdiv.forEach(function(x){ x.appendChild(obj) });
	if (type == 'main') 	f_main.forEach(function(x){ x.prepend(obj) });
	if (type == 'sidebar')	side_a.forEach(function(x){ x.prepend(obj) });
	if (type == 'between')  { const a2 = doc.getElementById('art-2'); if (a2) a2.before(obj); }
	if (type == 'article') {
		if (view_mode == '_article')  artfoot.forEach(function(x){ x.appendChild(obj) });
		if (view_mode == '_main')    martfoot.forEach(function(x){ x.appendChild(obj) });
	}

	// モジュール初期化（表示後に呼び出すこと）
	init_module(obj);

	// モジュールHTMLをサーバからロード？
	if (mdata(obj, 'load-module-html')) load_module_html( obj );
});

////////////////////////////////////////////////////////////////////////////////
// ●モジュールクラスやアイコンを設定
////////////////////////////////////////////////////////////////////////////////
function init_module(obj) {
	var div = create('div', 'module-edit-header', doc);
	var name = String(mdata(obj, 'module-name')).replace(/,\d+$/,'');
	if (! modules[ name ]) {
		// 使われてるモジュールが削除されてる等
		obj.remove();
		return ;
	}
	var hash = mdata_all( modules[ name ] );
	if (hash) {
		const h = mdata_all(obj);
		for (var k in hash) {
			// 元々持つのdata要素を上書きしないようにする
			if (h[k] != undefined) continue;
			h[k] = hash[k];
		}
	}

	// モジュールに title 属性を設定
	if (!obj.getAttribute('title')) {
		var title = children([obj], '.hatena-moduletitle');
		title = title.length ? title.map(function(x){ return x.textContent }).join('') : '';
		title = title || modules[name].getAttribute('title') ||  mdata(obj, 'module-name') || '(unknown)';
		obj.setAttribute('title', title);
	}

	// <button type="button" class="js-info" data-class="pre" data-title="notify_mailのREADME"
	//  data-url="/adiary/?plugin/plugin_readme&amp;name=(plugin_name)">README</button>
	// js-info（admin.js）は属性から読むので、data-title、data-class も属性で入れる
	if (mdata(obj, 'readme')) {
		var info = create('span', 'ui-icon ui-icon-help ui-button ui-button-icon-only js-info', doc);
		info.setAttribute('onclick', '');
		const rurl = mdata(obj, 'readme-url');
		if (rurl !== undefined && rurl !== null) info.setAttribute('data-url', rurl);
		const rtitle = mdata(obj, 'readme-title');
		if (rtitle !== undefined && rtitle !== null) info.setAttribute('data-title', rtitle);
		info.setAttribute('data-class', 'pre');
			div.appendChild(info);
	}

	if (mdata(obj, 'setting')) {
		var set = create('span', 'ui-icon ui-icon-wrench ui-button ui-button-icon-only', doc);
		set.setAttribute('title', btn_setting_title);
		set.addEventListener('click', function(){
			module_setting(obj);
		});
		div.appendChild(set);
	}

	if (mdata(obj, 'css-setting')) {
		var set2 = create('span', 'ui-icon ui-icon-image ui-button ui-button-icon-only', doc);
		set2.setAttribute('title', btn_cssset_title);
		set2.addEventListener('click', function(){
			module_setting(obj, 'css');
		});
		div.appendChild(set2);
	}

	if (!mdata(obj, 'fix')) {
		var close = create('span', 'ui-icon ui-icon-close ui-button ui-button-icon-only', doc);
		close.setAttribute('title', btn_close_title);
		close.addEventListener('click', function(){
			adiary.confirm({
				id: '#msg-delete-confirm',
				hash: { n: obj.getAttribute('title') },
				btn_ok: text_of('btn-close'),
				callback: function(flag) {
					if (flag) obj.remove();
				}
			});
		});
		div.appendChild(close);
	}
	var divs = F('.module-edit-header');

	obj.classList.add('design-module-edit');
	obj.prepend(div);
	show(obj);
	obj.addEventListener('mouseenter', function(){
		if (drag && drag.started) return;	// 並べ替えている間は変えない（つかんだものの下を通るため）
		if (zidx_module == div) return;
		const z = function(x){ return parseInt(doc.defaultView.getComputedStyle(x).zIndex) };
		if (zidx_module) zidx_module.style.zIndex = z(zidx_module) - 1;
		div.style.zIndex = z(div) + 1;
		zidx_module = div;
	});

	// 表示位置が重ならないように調整
	var offset = offset_of(div);
	var x = offset.left + css_size(div, 'width', true);
	var y = offset.top;
	var margin = 16;

	for(var i=0; i<divs.length; i++) {
		var btn = divs[i];
		var off = offset_of(btn);
		var dx  = off.left + css_size(btn, 'width', true);
		var dy  = off.top;
		if (dx == 0 && dy == 0) continue;	// 非表示要素
		if (x <= (dx-    50) || (dx+    50) <= x) continue;
		if (y <= (dy-margin) || (dy+margin) <= y) continue;
		// 位置をずらす
		y += margin; i=0;
	}
	if (offset.top != y) {
		// console.log("set ",btn.parent().attr('id')," x=",x," y=",y);
		div.style.top = (y-offset.top) + 'px';
	}
};

////////////////////////////////////////////////////////////////////////////////
// ●モジュールの設定を変更する
////////////////////////////////////////////////////////////////////////////////
// URLが無いフォームは、今までの $.ajax と同じく、今のページに送る
function action_of(form) {
	return form.getAttribute('action') || location.href;
}
function form_params(form) {	// jQuery の .serialize() と同じく、ファイルは送らない
	const data = new URLSearchParams();
	for(const [k, v] of new FormData(form))
		if (typeof(v) === 'string') data.append(k, v);
	return data;
}
function module_setting(obj, mode) {
	var name = mdata(obj, 'module-name');

	var formdiv = create('div');
	formdiv.setAttribute('id', 'popup-dialog');
	var form = adiary.secure('#setting-form').cloneNode(true);
	var url  = String(jq_value(form.dataset.url)) + name;
	if (mode) url += '&mode=' + mode;
	form.removeAttribute('id');
	function hidden(n, v) {
		const inp = create('input');
		inp.setAttribute('type', 'hidden');
		inp.setAttribute('name', n);
		if (v !== undefined) inp.setAttribute('value', v);
		form.appendChild(inp);
	}
	hidden('module_name',  name);
	hidden('setting_mode', mode);
	var body = create('div');
	body.setAttribute('id', 'js-form-body');
	form.appendChild( body );
	formdiv.appendChild( form );

	// エラー表示用
	var errdiv = create('div', 'error-message');
	var errmsg = create('strong', 'error');
	errmsg.style.display = 'block';
	var erradd = create('div');
	errdiv.append(errmsg, erradd);

	var error_msg = (adiary.secure('#msg-save-error') || {}).textContent || '';
	function success(data) {
		const ma = data.match(/ret=(-?\d+)(?:\n|$)/);
		if (! ma ) {
			errmsg.innerHTML = error_msg;
		} else if (ma[1] != '0') {
			errmsg.innerHTML = error_msg +'(ret='+ ma[1] +')';
		} else {
			//成功
			dialog.close();
			if (mode == 'css')
				load_module_css ( obj, load_module_html );
			else
				load_module_html( obj );
			return;
		}
		errmsg.setAttribute('title', data);
		const msg = data.match(/\nmsg=([\s\S]*)$/);
		if (msg) erradd.innerHTML = msg[1];
	}
	function post(url, data) {
		fetch(url, { method: 'POST', body: data }).then(function(res){
			if (!res.ok) throw res.status;
			return res.text();
		}).then(success, function(){
			errmsg.innerHTML = html_of('msg-ajax-error');
		});
	}

	var buttons = {};
	var ok_func = buttons[ text_of('btn-ok') ] = function(){
		// ファイルアップロードチェック
		var file;
		form.querySelectorAll('input[type="file"]').forEach(function(x){ if (x.value) file=true });

		// フォームデータ生成。今すぐ保存
		post(action_of(form), file ? new FormData( form ) : form_params(form));
	};
	buttons[ text_of('btn-reset-setting') ] = function(){
		adiary.confirm('#msg-reset-confirm', function(flag){
			if (!flag) return;

			const rst  = adiary.secure('#reset-form').cloneNode(true);
			const data = form_params(rst);
			data.append('name', name);
			error_msg  = text_of('msg-reset-error');
			post(action_of(rst), data);
		});
	};
	buttons[ adiary.msg('cancel') ] = function(){
		dialog.close();
	};

	// Enterキーで設定ウィンドウを閉じる
	form.addEventListener('keypress', function(evt) {
		if (!evt.target.closest('input') || evt.keyCode !== 13) return;
		ok_func();
		evt.preventDefault();
		evt.stopPropagation();
	});

	// ダイアログの設定
	var dialog = adiary.dialog(formdiv, {
		autoOpen: false,
		modal: true,
		width:  adiary.DialogWidth,
		minHeight: 100,
		maxHeight: document.documentElement.clientHeight,
		title:   obj.getAttribute('title').replace('%n', obj.getAttribute('title')),
		buttons: buttons,
		beforeClose: function() {
			formdiv.remove();
		}
	});

	// フォーム本体をロード。読み込めなくても開く（今までの .load() と同じ）
	fetch(url).then(function(res){
		return res.ok ? res.text() : '';
	}).catch(function(){
		return '';
	}).then(function(html){
		body.innerHTML = html;
		const scripts = adiary.take_scripts(body);	// 開いた後に動かす（asys.js）

		// if (id) body.prepend( $('<div>').text('id = #' + id).addClass('plugin-setting-id') );
		if (1 || mode == 'css') {	// HTMLソースを表示
			var vbtn = create('button');
			vbtn.setAttribute('type','button');
			vbtn.textContent = text_of('btn-view-html');
			vbtn.style.float = 'right';
			vbtn.addEventListener('click', function(){
				view_html_source(obj)
			});
			body.prepend( vbtn );
		}
		body.appendChild( errdiv );
		adiary.dom_init( formdiv );
		dialog.open();
		scripts.run();
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●結果を保存する
////////////////////////////////////////////////////////////////////////////////
btn_save.addEventListener('click', function(evt){
	document.querySelectorAll('#js-form input.js-value').forEach(function(x){ x.remove() });	// 戻るをされた時の対策
	var form = adiary.secure('#js-form');
	if (!form) return;

	form.querySelectorAll('.js-value').forEach(function(x){ x.remove() });
	var generate_inp = function(key,val) {
		const inp = create('input', 'js-value');
		inp.setAttribute('type',  'hidden');
		inp.setAttribute('name',  key);
		inp.setAttribute('value', val);
		return inp;
	};
	var form_append = function(key, obj, fixmod) {
		if (fixmod) {
			for(var i=0; i<obj.length; i++) {
				if (mdata(obj[i], 'module-name') != fixmod) continue;
				fixmod = null;
				break;
			}
		}
		if (fixmod) {
			form.appendChild( generate_inp(key, fixmod) );
			form.appendChild( generate_inp('debug_ary', '[design-edit.js] Add fix module "' + fixmod + '" for "' + key + '"') );
		}

		obj.forEach( function(dom){
			var name = mdata(dom, 'module-name');
			if (!name || name == '') return;
			form.appendChild( generate_inp(key, name) );
			// console.log(key + '=' + name);
		});
	};
	function find_all(ary, sel) {
		let ret = [];
		for(const el of ary) ret = ret.concat( Array.from(el.querySelectorAll(sel)) );
		return ret;
	}

	form_append('side_a_ary', children(side_a, module_selector));
 	form_append('side_b_ary', children(side_b, module_selector));
 	form_append('header_ary', find_all(f_head, module_selector), 'deh_login');

	var main_a_ary = [];
	var main_b_ary = [];
	{
		var x = main_a_ary;
		var items = children(f_main, module_selector + ', #article-box, #articles');
		for(var i=0; i<items.length; i++) {
			var id = items[i].getAttribute('id');
			if (id == 'article-box' || id == 'articles') {
				x = main_b_ary;
				continue;
			}
			x.push(items[i]);
		}
	}

	form_append('main_a_ary', main_a_ary);
 	form_append('main_b_ary', main_b_ary);

	// 記事本体とコメント欄
	form_append('art_h_ary', children(arthead, module_selector), 'dea_art-info');
	form_append('art_f_ary', children(artfoot, module_selector));
	form_append('com_ary'  , children(combody, module_selector), 'dec_comment-form');

	// 複数表示
	form_append('mart_h_ary',  children(marthead, module_selector), 'dea_art-info');
	form_append('mart_f_ary',  children(martfoot, module_selector));
	form_append('between_ary', articles ? children([articles], module_selector) : []);

	// if (evt.ctrlKey) form.submit();
	form.submit();
});

////////////////////////////////////////////////////////////////////////////////
// ●モジュールをロードして置き換える
////////////////////////////////////////////////////////////////////////////////
function load_module_html(obj) {
	if (!mdata(obj, 'load-module-html')) return;

	// HTML取得用フォーム
	var name = mdata(obj, 'module-name');
	var form = adiary.secure('#load-module-form');
	document.getElementById('js-load-module-name').value = name;

	fetch(action_of(form), { method: 'POST', body: form_params(form) }).then(function(res){
		if (!res.ok) throw res.status;
		return res.text();
	}).then(function(data){
		if (data.match(/^[\r\n\s]*$/)) return;
		var div = create('div');
		div.innerHTML = data;		// <script>は動かさない（今までと同じ）
		var newobj = children([div], module_selector);
		if (!newobj.length) return;

		adiary.dom_init( newobj );
		obj.replaceWith( ...newobj );
		newobj.forEach(init_module);	// 表示後に呼び出すこと
	}, function(){});
}

////////////////////////////////////////////////////////////////////////////////
// ●CSSをロードして置き換える
////////////////////////////////////////////////////////////////////////////////
function load_module_css(obj, call) {
	var callback = function(){
		if (!call) return;
		call(obj);
	};

	var name = String(mdata(obj, 'module-name'));
	if (!mdata(obj, 'css-setting')) return callback();

	var form = adiary.secure('#load-module-form');
	document.getElementById('js-load-module-name').value = name;
	var data = form_params(form);
	data.append('mode', 'css');

	fetch(action_of(form), { method: 'POST', body: data }).then(function(res){
		if (!res.ok) throw res.status;
		return res.text();
	}).then(function(data){
		// モジュールのstyleを削除
		F(module_selector).forEach(function(x){ x.removeAttribute('style') });
		if (data.match(/^\s*reload=1\s*$/)) {
			if (!doc.getElementById('user-css')) {	// usercssが読み込まれてない
				var style = create('link', '', doc);
				style.setAttribute('id',   'user-css');
				style.setAttribute('rel',  'stylesheet');
				style.setAttribute('href', String(jq_value((adiary.secure('#user-css-url') || {dataset:{}}).dataset.url)));
				doc.head.appendChild(style);
				return ;
			}
			// インストール済の時は、CSS強制リロード
			var link = doc.getElementById('user-css');
			var url  = link.getAttribute('href');
			if (!url || !url.length) {
				// error
			} else {
				url = url.replace(/\?.*/, '');	// ?より後ろを除去
				url += '?' + Math.random().toString().replace('.', '');
				link.setAttribute('href', url);
				console.log('reload user css:', url);
				return;
			}
		}

		// CSSテキストを適用
		var id = 'js-css-' + name.replace(/[_,]/g, '-');
		const old = doc.getElementById(id);
		if (old) old.remove();
		var css = create('style', '', doc);
		css.setAttribute('id',   id);
		css.setAttribute('type', 'text/css');
		css.textContent = data;
		doc.head.appendChild(css);
	}, function(){}).then(callback);
}

////////////////////////////////////////////////////////////////////////////////
// ●モジュールの背景色を変えて表示
////////////////////////////////////////////////////////////////////////////////
var disp_modules = document.getElementById('display-modules');
function disp_change() {
	var flag = disp_modules.checked;
	F(module_selector).forEach(function(x){ x.classList.toggle('display', !!flag) });
}
disp_modules.addEventListener('change', disp_change);
disp_change();


////////////////////////////////////////////////////////////////////////////////
// ●モジュールのHTMLソースを表示
////////////////////////////////////////////////////////////////////////////////
function view_html_source(_obj) {
	var div = create('div');
	var obj = _obj.cloneNode(true);
	{	// 整形する
		obj.querySelectorAll('.module-edit-header').forEach(function(x){ x.remove() });	// 編集ボタンの削除
		obj.classList.remove('design-module-edit', 'ui-sortable-handle', 'display');
		obj.removeAttribute('title');
		obj.removeAttribute('style');
		if (obj.getAttribute('class') == '') obj.removeAttribute('class');

		// いらない属性の削除
		obj.querySelectorAll('[target]').forEach(function(x){ x.removeAttribute('target') });
		obj.querySelectorAll('[title]').forEach(function(x){ x.removeAttribute('target') });
		obj.querySelectorAll('[for]').forEach(function(x){ x.removeAttribute('for') });
		obj.querySelectorAll('[style]').forEach(function(x){ x.removeAttribute('style') });
		obj.querySelectorAll('.resize-parts').forEach(function(x){ x.remove() });

		// hrefを'#'に置換
		obj.querySelectorAll('[href]').forEach(function(x){ x.setAttribute('href', '#') });

		// id=js-generate の削除
		obj.querySelectorAll('[id]').forEach(function(ob){
			var id = ob.getAttribute('id');
			if (! id.match(/^js-generate/)) return;
			ob.removeAttribute('id');
		});
	}
	div.setAttribute('title', text_of('msg-html-source') );
	div.classList.add( 'pre' );
	div.textContent = obj.outerHTML;
	adiary.dialog(div, { width: adiary.DialogWidth, maxHeight: document.documentElement.clientHeight });
}

//##############################################################################
}
//------------------------------------------------------------------------------
// ロードが早すぎて iframe の load が呼ばれない時の対策
//------------------------------------------------------------------------------
if (!iframe_onload && iframe && iframe.contentWindow && iframe.contentWindow.$)
	// jQuery-uiよりも早いことがあるで、少しウエイトを入れる
	setTimeout(on_iframe_load, 200);
//------------------------------------------------------------------------------
});

//##############################################################################
// 設定画面用のサブルーチン
//##############################################################################
// プラグインのCSS設定画面（css_setting.html）から呼ぶ。obj は jQuery の要素（$f で探したもの）
// FX : rgb(200,200,200), tranparent
// GC : rgb(200,200,200), rgb(0, 0, 0, 0)
function parse_color(col) {
	if (col == '') return '';
	col = col.toLowerCase();
	if (col == 'transparent') return '';
	if (col.match(/^#[0-9a-f]{6}$/)) return col;

	var ma = col.match(/rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
	if (ma) {
		var c1 = Number(ma[1]).toString(16);
		var c2 = Number(ma[2]).toString(16);
		var c3 = Number(ma[3]).toString(16);
		if (c1.length == 1) c1 = '0' + c1;
		if (c2.length == 1) c2 = '0' + c2;
		if (c3.length == 1) c3 = '0' + c3;
		return '#' + c1 + c2 + c3;
	}
	return '';	// unknown type
}

function parse_px(m) {
	return Math.round( parse_px_float(m) );
}
function parse_px_float(m) {
	var ma = m && m.match(/^(-?\d+(?:\.\d+)?)\s*(?:px)$/);
	if (ma) return ma[1];
	return 0;
}

function get_border_color(obj) {
	return parse_color(
		obj.css('border-color')
		|| obj.css('border-bottom-color')
		|| obj.css('border-top-color')
		|| obj.css('border-right-color')
		|| obj.css('border-left-color')
	);
}

function delay_color_setting(target, obj, style, func) {
	setTimeout( function(){
		var col = parse_color(obj.css('background-color'));
		const sel = document.getElementById('select-bg');
		if (col && sel) sel.value = col;
		if (func) {
			if (typeof(func) == 'function')	return func(obj);
			obj.removeClass(func);
		}
	}, 500);
}
