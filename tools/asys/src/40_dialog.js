//##############################################################################
// dialog functions
//##############################################################################
// jQueryを使わずに書いてある。21_adiary-ui.js の $.fn.adiaryDialog などは、これを呼ぶ包み。
// asys.js を消すときは、この中身を admin.js へ移す
{
////////////////////////////////////////////////////////////////////////////////
// sub functions
////////////////////////////////////////////////////////////////////////////////
// idで要素を探す。同じidが2つ以上あるときは使わない（adiary.js の secure() と同じ）
function secure(sel) {
	const id   = sel.replace(/^#/, '');
	const list = document.querySelectorAll('[id="' + id.replace(/["\\]/g, '\\$&') + '"]');
	if (list.length > 1) {
		console.error('secure() error! : id="' + id + '" is duplicate.');
		return null;
	}
	return list[0] || null;
}
// jQueryの要素も受け取る（移行中）
function to_dom(x) {
	if (!x) return null;
	if (window.jQuery && x instanceof window.jQuery) return x[0] || null;
	return x instanceof Node ? x : null;
}
function create(tag, cls) {
	const dom = document.createElement(tag);
	if (cls) dom.className = cls;
	return dom;
}
function add_class(dom, cls) {
	const ary = String(cls).split(/\s+/).filter(Boolean);
	if (ary.length) dom.classList.add(...ary);
}
// jQueryの .append() と同じ。文字列はHTML、要素、jQueryの要素を受け取る
function append_any(dom, x) {
	if (x === undefined || x === null) return;
	if (window.jQuery && x instanceof window.jQuery) {
		x.each(function(i, d){ dom.appendChild(d) });
		return;
	}
	if (x instanceof Node) return dom.appendChild(x);
	dom.insertAdjacentHTML('beforeend', String(x));
}
// jQueryの .outerWidth()、.outerHeight()。CSSの計算値から求める（getBoundingClientRectとは端数が違う）
function outer(dom, dim) {
	const cs  = getComputedStyle(dom);
	const val = cs[dim];
	if (val === 'auto' || isNaN(parseFloat(val)))
		return dim === 'width' ? dom.offsetWidth : dom.offsetHeight;
	if (cs.boxSizing === 'border-box') return parseFloat(val);

	const ary = dim === 'width' ? ['Left', 'Right'] : ['Top', 'Bottom'];
	let   x   = parseFloat(val);
	for(const s of ary)
		x += (parseFloat(cs['padding' + s]) || 0) + (parseFloat(cs['border' + s + 'Width']) || 0);
	return x;
}
function outer_w(dom) { return outer(dom, 'width');  }
function outer_h(dom) { return outer(dom, 'height'); }
// jQueryの $(window).width()、.height()
function win_w() { return document.documentElement.clientWidth;  }
function win_h() { return document.documentElement.clientHeight; }
// jQueryの .css() に数を渡したとき（pxを付ける）
function px(v) { return typeof(v) === 'number' ? v + 'px' : v; }
function in_body(dom) { return document.body.contains(dom); }

////////////////////////////////////////////////////////////////////////////////
// z-index順に、bodyに足す
////////////////////////////////////////////////////////////////////////////////
const ZIndexStart = 1000;
let   ui_objs     = [];
const ui_zindex   = new WeakMap();

$$.ui_append = function(dom) {
	if (!dom) return;

	let zindex = ZIndexStart - 1;
	ui_objs = ui_objs.filter(function(x){
		if (!in_body(x)) return false;
		const zi = ui_zindex.get(x);
		if (zindex<zi) zindex=zi;
		return true;
	});
	ui_objs.push(dom);

	dom.style.zIndex = ++zindex;
	ui_zindex.set(dom, zindex);

	// jQueryがあるあいだは、今までどおりjQueryで足す。中の<script>のうち、まだ動いていないもの
	// （jQueryの .load() や .html() で、文書の外の要素に入れたもの）は、文書に入れたときに動くため。
	// プラグインの設定画面（.load() で読み込む）のスクリプトは、ダイアログを開いたときに動く。
	// jQueryを外すときは、読み込んだ側でスクリプトを動かすようにしてから appendChild にする
	if (window.jQuery) window.jQuery(document.body).append(dom);
		else	   document.body.appendChild(dom);
};

$$.overlay = function() {
	return create('div', 'ui-overlay aui-overlay');
};
$$.overlay_show = function() {
	const overlay = this.overlay();
	this.ui_append(overlay);
	return overlay;
};

////////////////////////////////////////////////////////////////////////////////
// draggable
////////////////////////////////////////////////////////////////////////////////
function set_iframe_events(val) {
	document.querySelectorAll('iframe').forEach(function(f){ f.style.pointerEvents = val });
}
$$.draggable = function(dom, opt) {
	let sx;
	let sy;
	let obj;
	dom.classList.add('aui-draggable');

	dom.addEventListener('mousedown', function(evt){
		set_iframe_events('none');
		const tar = evt.target;
		obj = tar.classList.contains('aui-draggable') ? tar : tar.parentElement.closest('.aui-draggable');

		// 押した要素そのものだけで判断する（今までと同じ。見出しの文字を押しても動かさない）
		if (opt) {
			if (opt.cancel &&  tar.matches(opt.cancel)) return;
			if (opt.handle && !tar.matches(opt.handle)) return;
		}
		const r = obj.getBoundingClientRect();
		sx = r.left + window.pageXOffset - evt.pageX;
		sy = r.top  + window.pageYOffset - evt.pageY;
		document.addEventListener('mousemove', move);
		evt.preventDefault();
	});

	// mouseupではpreventDefaultしない。ダイアログの中の数値入力の矢印を押して離したとき、
	// 値が増え（減り）続けてしまうため（Chromeでは、離したときの既定の動作で繰り返しを止める）
	dom.addEventListener('mouseup', function(evt){
		set_iframe_events('auto');
		document.removeEventListener('mousemove', move);
	});

	function move(evt) {
		const x = sx + evt.pageX;
		const y = sy + evt.pageY;
		obj.style.position = 'absolute';
		obj.style.left     = x + 'px';
		obj.style.top      = y + 'px';
		evt.preventDefault();
	}
};

////////////////////////////////////////////////////////////////////////////////
// dialog, only modal mode.
////////////////////////////////////////////////////////////////////////////////
//	const dlg = $$.dialog(dom, opt);	dlg.open();  dlg.close();
//	$$.dialog(dom, 'open')、$$.dialog(dom, 'close') でも開け閉めできる
//
//	opt.title, width(-1 is auto), minWidth, minHeight, maxWidth, maxHeight,
//	    dialogClass, buttons{label: func}, autoOpen, closeOnEscape, dialog(use <dialog>),
//	    open(null, dom), beforeClose(dom), close(dom), exit()
//	opt._remove(dom) … 消すときの処理（$.fn.adiaryDialog が、jQueryのデータも消すために使う）
const dialog_data = new WeakMap();
let   esc_dialogs = [];
let   esc_hook;

$$.dialog = function(dom, opt) {
	if (opt === 'open' )	return this.dialog_open (dom);
	if (opt === 'close')	return this.dialog_close(dom);
	opt = opt || {};

	const useDialog = opt.dialog;

	////////////////////////////////////////////////////////////////////////
	// init dialog
	////////////////////////////////////////////////////////////////////////
	const dialog = create(useDialog ? 'dialog' : 'div', 'ui-dialog aui-dialog');
	if (useDialog) {
		dialog.setAttribute('method', 'dialog');
	}
	const min_w = opt.minWidth  || 200;
	const min_h = opt.minHeight || 150;
	let   width = opt.width     || 300;
	if (width<0) width='auto';
	dialog.style.width     = px(width);
	dialog.style.minWidth  = px(min_w);
	dialog.style.minHeight = px(min_h);
	if (opt.maxWidth)  dialog.style.maxWidth  = px(opt.maxWidth);
	if (opt.maxHeight) dialog.style.maxHeight = px(opt.maxHeight);
	if (opt.dialogClass)
		add_class(dialog, opt.dialogClass);

	const data = {};
	dialog_data.set(dom, data);
	////////////////////////////////////////////////////////////////////////
	// header
	////////////////////////////////////////////////////////////////////////
	{
		const title = create('div', 'ui-dialog-titlebar ui-widget-header');
		const span  = create('span', 'ui-dialog-title');
		span.innerHTML = opt.title || dom.getAttribute('title') || '&ensp;';
		title.appendChild( span );
		const close = create('button', 'ui-button');
		close.setAttribute('title',    'Close');
		close.setAttribute('tabindex', -1);
		close.appendChild( create('span', 'ui-icon ui-icon-closethick') );
		title.appendChild( close );
		dialog.appendChild( title );

		close.addEventListener('click', function(){
			if (opt.exit) opt.exit();
			$$.dialog_close(dom);
		});
		data.header = title;
	}

	////////////////////////////////////////////////////////////////////////
	// ESC
	////////////////////////////////////////////////////////////////////////
	if (!('closeOnEscape' in opt) || opt.closeOnEscape) {
		esc_dialogs = esc_dialogs.filter(in_body);
		esc_dialogs.push( dialog );

		if (!esc_hook) {
			esc_hook = true;
			window.addEventListener('keydown', function(evt){
				if (evt.keyCode != 27)  return;	// ESC

				// 閉じた後のダイアログが残っていれば、何もしない（今までと同じ。jQueryの .remove() で
				// 閉じるボタンのイベントも消えていたため）
				const dialog = esc_dialogs.pop();
				if (!dialog || !in_body(dialog)) return;
				const btn    = dialog.querySelector('div.ui-dialog-titlebar .ui-icon-closethick');
				if (btn) btn.click();
			});
		}
	}

	////////////////////////////////////////////////////////////////////////
	// main
	////////////////////////////////////////////////////////////////////////
	dom.classList.add('ui-dialog-content');
	data.restore = dom.parentElement;
	dialog.appendChild( dom );
	if (dom.style.display === 'none') dom.style.display = '';	// jQueryの .show()（まだ文書の外なので、CSSで隠れていても変えない）

	////////////////////////////////////////////////////////////////////////
	// button
	////////////////////////////////////////////////////////////////////////
	if (opt.buttons) {
		const footer = create('div', 'ui-dialog-buttonpane');
		const btnset = create('div', 'ui-dialog-buttonset');
		const btns   = opt.buttons;
		for(let i in btns) {
			const btn = create('button', 'ui-button');
			btn.setAttribute('type', 'button');
			btn.textContent = i;
			btn.addEventListener('click', btns[i]);
			btnset.appendChild(btn);
		}
		footer.appendChild( btnset );
		dialog.appendChild( footer );
		data.footer = footer;
	}

	////////////////////////////////////////////////////////////////////////
	// disable tab indexes
	////////////////////////////////////////////////////////////////////////
	if (!useDialog) {
		const tabs = [];
		data.tabs = tabs;
		document.querySelectorAll('a, input, button, select, textarea').forEach(function(obj){
			tabs.push({
				obj:	obj,
				index:	obj.getAttribute('tabindex')
			});
			obj.setAttribute('tabindex', -1);
		});
		if (document.activeElement) document.activeElement.blur();
	}

	////////////////////////////////////////////////////////////////////////
	// append dialog obj
	////////////////////////////////////////////////////////////////////////
	if (!useDialog) data.overlay = this.overlay();
	data.dialog      = dialog;
	data.open        = opt.open;
	data.close       = opt.close;
	data.beforeClose = opt.beforeClose;
	data.remove      = opt._remove || function(x){ x.remove() };
	data.useDialog   = useDialog;
	data.min_h       = min_h;

	const ret = {
		dom:	dom,
		open:	function(){ return $$.dialog_open (dom) },
		close:	function(){ return $$.dialog_close(dom) }
	};
	if (opt && !opt.autoOpen && 'autoOpen' in opt) return ret;

	this.dialog_open(dom);
	return ret;
};

$$.dialog_open = function(dom) {
	const data    = dialog_data.get(dom) || {};
	const overlay = data.overlay;
	const dialog  = data.dialog;
	if (!dialog) throw("Do not open dialog!");

	if (overlay) overlay.style.visibility = 'hidden';
	dialog.style.visibility = 'hidden';
	this.ui_append( overlay );
	this.ui_append( dialog  );

	// set css
	const hf = outer_h(data.header) + (data.footer ? outer_h(data.footer) : 0);
	dom.style.minHeight = (data.min_h - hf) + 'px';
	dom.style.maxHeight = (win_h()    - hf) + 'px';

	const x = window.pageXOffset + (win_w() - outer_w(dialog))/2;
	const y = window.pageYOffset + (win_h() - outer_h(dialog))/2;
	dialog.style.left = x + 'px';
	dialog.style.top  = y + 'px';
	this.draggable(dialog, {
		handle: '.ui-dialog-titlebar'
	});
	if (overlay) overlay.style.visibility = 'visible';
	dialog.style.visibility = 'visible';

	if (data.open) data.open( null, dom );

	return dom;
};

$$.dialog_close = function(dom) {
	const data = dialog_data.get(dom) || {};
	if (!data.dialog) return dom;		// 閉じた後（閉じるボタンとOKを続けて押したときなど）
	if (data.beforeClose) data.beforeClose.call( null, dom );

	if (data.overlay) data.remove(data.overlay);
	data.remove(data.dialog);
	if (data.restore) data.restore.appendChild( dom );

	data.overlay=null;
	data.dialog =null;

	// recovery tab index
	if (!data.useDialog) {
		const tabs = data.tabs;
		for(let i in tabs) {
			let tab = tabs[i];
			let idx = tab.index;
			if (idx === null) tab.obj.removeAttribute('tabindex');
				else	  tab.obj.setAttribute('tabindex', idx);
		}
	}
	if (data.close) data.close.call( null, dom );

	return dom;
};

////////////////////////////////////////////////////////////////////////////////
// error dialog
////////////////////////////////////////////////////////////////////////////////
$$.show_error = function(h, _arg) {
	if (typeof(h) === 'string') h = {id: h, html:h, hash:_arg};
	h.class = (h.class ? h.class : '') + ' error-dialog';
	h.default_title = this.msg('error');
	return this.show_dialog(h, _arg);
}
$$.show_dialog = function(h, _arg, callback) {
	if (!callback && typeof(_arg) === 'function') {
		callback = _arg; _arg = {};
	}
	if (typeof(h) === 'string') h = {id: h, html:h, hash:_arg};
	// 要素を渡されたとき（jQueryの要素も可）。#idが無いときは、今までどおり中身の無いダイアログにする
	let obj = to_dom(h);
	if (!obj && h.id && h.id.substr(0,1) == '#') obj = secure( h.id ) || create('div');

	let div;
	if (h.hash && Object.keys(h.hash).length || !obj) {
		div = create('div');
		let html = obj ? obj.innerHTML : h.html;
		html = html.replace(/%([A-Za-z])/g, function(w,m1){ return h.hash[m1] });
		html = html.replace(/%[A-Za-z]/g, '');
		div.innerHTML = html;
	} else {
		div = obj;
	}

	div.setAttribute('title', h.title || obj && obj.dataset.title || (_arg && _arg.title) || h.default_title || this.msg('confirm'));
	this.dialog(div, {
		modal: true,
		dialogClass: h.class,
		buttons: {
			OK: function(){
				$$.dialog_close(div);
				if (callback) callback( true, div );
			}
		},
		exit: function(){
			if (callback) callback( false )
		}
	});
	return false;
}

////////////////////////////////////////////////////////////////////////////////
// confirm dialog
////////////////////////////////////////////////////////////////////////////////
$$.confirm = function(h, callback) {
	if (typeof(h) === 'string') h = {id: h, html:h };
	const obj = h.id && h.id.substr(0,1) == '#' && secure( h.id ) || null;
	let html = (obj && obj.innerHTML) || h.html;
	if (h.hash) html = html.replace(/%([A-Za-z])/g, function(w,m1){ return h.hash[m1] });

	callback = callback || h.callback;

	const div = create('div');
	div.innerHTML = html;
	div.setAttribute('title', h.title || obj && obj.dataset.title || this.msg('confirm'));
	const btn = {};
	btn[ h.btn_ok || this.msg('ok') ] = function(){
		$$.dialog_close(div);
		if (callback) callback(true);
	};
	btn[ h.btn_cancel || this.msg('cancel') ] = function(){
		$$.dialog_close(div);
		if (callback) callback(false);
	};
	this.dialog(div, {
		modal: true,
		dialogClass: h.class,
		buttons: btn,
		open: function(){
			const btns = div.parentElement.querySelectorAll('.ui-dialog-buttonpane button');
			if (h.focus == 'ok'     && btns[0]) btns[0].focus();
			if (h.focus == 'cancel' && btns[1]) btns[1].focus();
		},
		exit: function(){
			if (callback) callback(false);
		}
	});
}

////////////////////////////////////////////////////////////////////////////////
// textarea dialog
////////////////////////////////////////////////////////////////////////////////
$$.textarea_dialog = function(dom, func) {
	dom = to_dom(dom);
	this.form_dialog({
		title: dom.dataset.title,
		elements: [
			{type: 'p', html: dom.dataset.msg},
			{type: 'textarea', name: 'ta'}
		],
		callback: function( h ) { func( h.ta ) }
	});
}

////////////////////////////////////////////////////////////////////////////////
// form dialog
////////////////////////////////////////////////////////////////////////////////
$$.form_dialog = function(h) {
	let ele = h.elements || { type:'text', name:'str', class:'w80p' };
	if (!Array.isArray(ele)) ele = [ ele ];
	const div = create('div');
	div.setAttribute('id', 'popup-dialog');

	const form = create('form');
	for(let i=0; i<ele.length; i++) {
		const x = ele[i];
		if (!x) continue;
		if (typeof(x) == 'string') {
			const line = create('div');
			line.innerHTML = x;
			form.appendChild( line );
			continue;
		}
		if (x.type == 'p') {
			const p = create('p');
			if (x.html !== undefined) p.innerHTML = x.html;
			form.appendChild( p );
			continue;
		}
		if (x.type == 'textarea') {
			const t = create('textarea');
			t.setAttribute('rows', x.rows || 5);
			if (x.name !== undefined) t.setAttribute('name', x.name);
			t.className = 'w100p';
			if (x.val !== undefined && x.val != '') t.textContent = x.val === null ? '' : x.val;
			form.appendChild( t );
			continue;
		}
		if (x.type == '*') {
			append_any(form, x.html);
			continue;
		}
		// else
		const inp = create('input');
		inp.setAttribute('type', x.type || 'text');
		if (x.name !== undefined && x.name !== null) inp.setAttribute('name',  x.name);
		if (x.val  !== undefined && x.val  !== null) inp.setAttribute('value', x.val );
		add_class(inp, x.class || 'w80p');
		form.appendChild( inp );
	}
	div.appendChild( form );

	// button setting
	const buttons = {};
	const ok_func = buttons[ this.msg('ok') ] = function(){
		const inputs = div.querySelectorAll('input');
		for(let i=0; i<inputs.length; i++) {
			const obj = inputs[i];
			if (obj.validity && !obj.validity.valid) return; // validation error
		}
		$$.dialog_close(div);
		const ret = {};
		for(const [name, val] of new FormData(form)) {
			if (typeof(val) !== 'string') continue;		// ファイルは使わない（今までの serializeArray と同じ）
			ret[ name ] = val.replace(/\r/g, '');
		}
		h.callback( ret );	// callback
	};
	buttons[ this.msg('cancel') ] = function(){
		$$.dialog_close(div);
		if (h.cancel) h.cancel();
	};
	// stop submit by enter
	form.addEventListener('keypress', function(evt) {
		if (!evt.target.closest('input') || evt.keyCode !== 13) return;
		ok_func();
		evt.preventDefault();
		evt.stopPropagation();
	});

	// show dialog
	const title = document.getElementById('msg-setting-title');
	this.dialog(div, {
		modal:     true,
		width:     this.DialogWidth     || -1,
		minWidth:  this.DialogMinWidth  || 200,
		minHeight: this.DialogMinHeight || 100,
		title:   h.title || (title ? title.textContent : ''),
		buttons: buttons
	});
}

//##############################################################################
}
