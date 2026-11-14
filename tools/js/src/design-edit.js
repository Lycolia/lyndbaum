//##############################################################################
// adiaryデザイン編集用JavaScript
//							(C)2013-2016 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';
////////////////////////////////////////////////////////////////////////////////
// ●モジュール情報のロード
////////////////////////////////////////////////////////////////////////////////
// プラグインのCSS設定画面（css_setting.html）が使う。iframeの中の文書（下のframe_find()など）
var frame_doc;
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
	frame_doc = doc;		// global（プラグインのCSS設定画面が使う）
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
	adiary.sortable(arthead, { items: selector, connectWith: artfoot });
	adiary.sortable(artfoot, { items: selector, connectWith: arthead });
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
	adiary.sortable(side_a, { items: selector, connectWith: side_b });
	adiary.sortable(side_b, { items: selector, connectWith: side_a });
	adiary.sortable(f_hdiv, { items: selector });
	adiary.sortable(f_main, {
			items: selector + ', #article-box' + ', #articles>article, #articles ' + selector,
			cancel: 'article:not(' + module_selector + ')',
			update: main_update
	});
	adiary.sortable(marthead, { items: selector, connectWith: martfoot });
	adiary.sortable(martfoot, { items: selector, connectWith: marthead });

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
		if (adiary.sorting()) return;	// 並べ替えている間は変えない（つかんだものの下を通るため）
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
// プラグインのCSS設定画面（css_setting.html）から呼ぶ。objはiframeの中の要素（frame_find()で探したもの）
//	frame_find(sel)		iframeの中の要素（無ければnull）
//	css(obj, 'margin-top')	計算された値（jQueryの.css()と同じ）
//	width(obj)、height(obj)、outer_width(obj)、outer_height(obj)、position(obj)
//				jQuery 3.6の.width()、.height()、.outerWidth()、.outerHeight()、.position()と同じ値
//	set_value('#id', 値)	ダイアログの欄に値を入れる（jQueryの.val(値)と同じ）
// objがnullのときは、jQueryの空の集まりと同じく、undefinedを返す
function frame_find(sel) {
	return frame_doc ? frame_doc.querySelector(sel) : null;
}
function styles_of(obj) {
	return obj.ownerDocument.defaultView.getComputedStyle(obj);
}
function css(obj, prop) {
	if (!obj) return undefined;
	return styles_of(obj).getPropertyValue(prop);
}
function css_num(obj, prop) {	// jQuery.css(elem, prop, true)
	return parseFloat(css(obj, prop)) || 0;
}
// jQuery 3.6のgetWidthOrHeight()とboxModelAdjustment()を写した
function jq_size(obj, dim, box) {
	if (!obj) return undefined;
	const cs = styles_of(obj);
	// 隠れている要素は、jQueryと同じく、一時的に出して測る
	if (/^(none|table(?!-c[ea]).+)/.test(cs.display) && (!obj.getClientRects().length || !obj.getBoundingClientRect().width)) {
		const st  = obj.style;
		const old = { position: st.position, visibility: st.visibility, display: st.display };
		st.position = 'absolute'; st.visibility = 'hidden'; st.display = 'block';
		const ret = jq_size_main(obj, dim, box);
		st.position = old.position; st.visibility = old.visibility; st.display = old.display;
		return ret;
	}
	return jq_size_main(obj, dim, box);
}
function jq_size_main(obj, dim, box) {
	const cs  = styles_of(obj);
	const D   = dim === 'width' ? 'Width' : 'Height';
	const isBorderBox = cs.boxSizing === 'border-box';
	let valueIsBorderBox = isBorderBox;
	let val = cs[dim];
	if ((val === 'auto' || !parseFloat(val) && cs.display === 'inline') && obj.getClientRects().length) {
		valueIsBorderBox = true;
		val = obj['offset' + D];
	}
	val = parseFloat(val) || 0;

	let delta = 0;
	if (box !== (valueIsBorderBox ? 'border' : 'content')) {
		const sides = dim === 'width' ? ['Right', 'Left'] : ['Top', 'Bottom'];
		for(const s of sides) {
			if (!valueIsBorderBox) {
				delta += css_num(obj, 'padding-' + s.toLowerCase());
				delta += css_num(obj, 'border-' + s.toLowerCase() + '-width');
			} else {
				if (box === 'content') delta -= css_num(obj, 'padding-' + s.toLowerCase());
				delta -= css_num(obj, 'border-' + s.toLowerCase() + '-width');
			}
		}
		if (!valueIsBorderBox && val >= 0)	// スクロールバーの分
			delta += Math.max(0, Math.ceil(obj['offset' + D] - val - delta - 0.5)) || 0;
	}
	return val + delta;
}
function width(obj)        { return jq_size(obj, 'width',  'content') }
function height(obj)       { return jq_size(obj, 'height', 'content') }
function outer_width(obj)  { return jq_size(obj, 'width',  'border')  }
function outer_height(obj) { return jq_size(obj, 'height', 'border')  }
function position(obj) {
	if (!obj) return undefined;
	const doc = obj.ownerDocument;
	const win = doc.defaultView;
	const offset_of = function(el) {
		if (!el.getClientRects().length) return { top: 0, left: 0 };
		const r = el.getBoundingClientRect();
		return { top: r.top + win.pageYOffset, left: r.left + win.pageXOffset };
	};
	let offset;
	let po = { top: 0, left: 0 };
	if (css(obj, 'position') === 'fixed') {
		offset = obj.getBoundingClientRect();
	} else {
		offset = offset_of(obj);
		let op = obj.offsetParent || doc.documentElement;
		while(op && (op === doc.body || op === doc.documentElement) && css(op, 'position') === 'static')
			op = op.parentNode;
		if (op && op !== obj && op.nodeType === 1) {
			po = offset_of(op);
			po.top  += css_num(op, 'border-top-width');
			po.left += css_num(op, 'border-left-width');
		}
	}
	return {
		top:  offset.top  - po.top  - css_num(obj, 'margin-top'),
		left: offset.left - po.left - css_num(obj, 'margin-left')
	};
}
function set_value(sel, val) {
	const v = (val === null || val === undefined) ? '' : String(val);
	document.querySelectorAll(sel).forEach(function(x){ x.value = v });
}
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
		css(obj, 'border-color')
		|| css(obj, 'border-bottom-color')
		|| css(obj, 'border-top-color')
		|| css(obj, 'border-right-color')
		|| css(obj, 'border-left-color')
	);
}

function delay_color_setting(target, obj, style, func) {
	setTimeout( function(){
		var col = parse_color(css(obj, 'background-color'));
		const sel = document.getElementById('select-bg');
		if (col && sel) sel.value = col;
		if (func) {
			if (typeof(func) == 'function')	return func(obj);
			obj.classList.remove(func);
		}
	}, 500);
}
