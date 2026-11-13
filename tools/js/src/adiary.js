//##############################################################################
// adiary.js
//	公開画面の処理。jQueryとasys.jsを使わない
//	※ログイン中と管理画面では、asys.js（jQuery）と admin.js も読み込む。そのときは、
//	  <script-defer> の実行と js-switch は asys.js が行い、window.adiary は asys.js（$$）になる。
//	  テンプレートなどから adiary.〜 で呼ぶものは、admin.js が $$ からも呼べるようにする
//##############################################################################
//[TAB=8]
'use strict';
(function(){
const adiary = {
	name:			'adiary',
	SP:			false,		// smart phone mode
	CommentEnableTime:	10000,		// msec
	CommentEnableKeys:	10,
	PopupDelayTime:		300,		// msec
	PopupOffsetX:		15,
	PopupOffsetY:		10
};
const with_asys = !!window.jQuery;	// asys.js を読んだページ（ログイン中、管理画面）

window.adiary        = adiary;		// asys.js を読んだページでは、asys.js が置き換える
window.adiary_public = adiary;		// admin.js から呼ぶ

const inits = [];
function init(func) {
	inits.push(func);
}

// 画面ごとのJS（edit-helper.jsなど）を動かす。jQueryを使わずに書いたものは、$(func)の代わりに
// adiary_public.ready(func) を使う。asys.jsを読んだページでは、今までの$(func)と同じ時と順番
// （asysの初期化の後）にする。jQuery 3のreadyは非同期なので、DOMContentLoadedではasysの初期化より先に動いてしまう。
// adiary.ready と書かないのは、asysの初期化が、後ろのdeferのファイルの読み込みを待たずに動くことがあり、
// そのときは window.adiary がもう asys.js（$$）に置き換わっているため。
// jQueryを外し終えたら、initと同じにする
adiary.ready = function(func) {
	if (with_asys) return window.jQuery(function(){ func.call(window.adiary) });
	init(func);
};

//##############################################################################
// ■基本の関数
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// ●idで要素を探す。同じidが2つ以上あるときは使わない
////////////////////////////////////////////////////////////////////////////////
function secure(sel) {
	const id   = sel.replace(/^#/, '');
	const list = document.querySelectorAll('[id="' + id.replace(/["\\]/g, '\\$&') + '"]');
	if (list.length > 1) {
		console.error('secure() error! : id="' + id + '" is duplicate.');
		return null;
	}
	return list[0] || null;
}
adiary.secure = secure;

////////////////////////////////////////////////////////////////////////////////
// ●スクリプトの読み込み
////////////////////////////////////////////////////////////////////////////////
adiary.load_script = function(url, callback) {
	const script = document.createElement('script');
	script.src   = url;
	script.async = true;
	if (callback) script.addEventListener('load', callback);
	document.head.appendChild(script);
	return script;
}

////////////////////////////////////////////////////////////////////////////////
// ●<style> を足す
////////////////////////////////////////////////////////////////////////////////
adiary.append_style = function(css) {
	const style = document.createElement('style');
	style.textContent = css || '';
	document.head.appendChild(style);
	return style;
}

////////////////////////////////////////////////////////////////////////////////
// ●textareaのカーソルの位置に文字を入れる
////////////////////////////////////////////////////////////////////////////////
function insert_to_textarea(ta, text) {
	const p = ta.selectionStart;
	ta.value = ta.value.substring(0, p) + text + ta.value.substring(ta.selectionEnd);
	ta.setSelectionRange(p + text.length, p + text.length);
}

////////////////////////////////////////////////////////////////////////////////
// ●ブラウザーに覚える（asys.js の PrefixStorage と同じキー）
////////////////////////////////////////////////////////////////////////////////
function storage_key(key) {
	return String(adiary.myself || '/') + '::' + key;
}
function storage_get(key) {
	try { return localStorage.getItem(storage_key(key)); } catch(e) { return null; }
}
function storage_set(key, val) {
	try { localStorage.setItem(storage_key(key), val); } catch(e) {}
}

////////////////////////////////////////////////////////////////////////////////
// ●マウスを乗せたときのポップアップ
////////////////////////////////////////////////////////////////////////////////
// show(dom, div) で div に中身を入れる。中身が無ければ div を空にする
adiary.popup = function(dom, show) {
	const self = this;
	let timer;
	dom.addEventListener('mouseover', function(evt) {
		if (timer) return;
		const x = evt.pageX;
		const y = evt.pageY;
		timer = setTimeout(function(){
			const div = self.popup_div || (self.popup_div = document.body.appendChild(document.createElement('div')));
			div.className = 'popup-block';
			div.removeAttribute('id');
			div.innerHTML = '';
			show(dom, div);
			if (!div.childNodes.length) return;
			div.style.left    = (self.SP ? 0 : x + self.PopupOffsetX) + 'px';
			div.style.top     = (y + self.PopupOffsetY) + 'px';
			div.style.display = 'block';
		}, self.PopupDelayTime);
	});
	dom.addEventListener('mouseleave', function() {
		clearTimeout(timer);
		timer = null;
		if (self.popup_div) self.popup_div.style.display = 'none';
	});
}

//##############################################################################
// ■初期化
//##############################################################################
init(function(){
	// load adiary vars
	const vars = secure('#asys-vars');
	if (vars) {
		try {
			const json = vars.innerHTML.replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
			const data = JSON.parse(json);
			const ary  = ['myself', 'myself2', 'Basepath', 'ScriptDir', 'PubdistDir', 'SpecialQuery', 'Static'];
			for(const k of ary) {
				if (k in data) this[k] = data[k];
			}
			this.vars = data;
		} catch(e) {
			console.error(e);
		}
	}
	const data = this.vars || {};

	// remove #rss-tm hash
	if (window.location.hash.indexOf('#rss-tm') == 0) {
		history.pushState("", document.title, location.pathname + location.search);
	}

	// Smartphone mode（狭い画面。テーマのCSSの @media と同じ幅）
	if (window.matchMedia('(max-width: 640px)').matches) {
		this.SP = true;
	}

	// DB time, Total time
	const db_time    = document.getElementById('system-info-db-time');
	const total_time = document.getElementById('system-info-total-time');
	if (data.DBTime    && db_time)    db_time.textContent    = data.DBTime;
	if (data.TotalTime && total_time) total_time.textContent = data.TotalTime;

	// Google Analytics 4
	if (data.GA4_ID) {
		window.dataLayer = window.dataLayer || [];
		function gtag(){ dataLayer.push(arguments); }
		gtag('js', new Date());
		gtag('config', data.GA4_ID);
		this.load_script('https://www.googletagmanager.com/gtag/js?id=' + data.GA4_ID);
	}

	// load script		ex) twitter-widget of filter syntax
	document.querySelectorAll('script-load').forEach(function(dom) {
		adiary.load_script(dom.getAttribute('src'));
	});
});

//##############################################################################
// ■CSSへの機能提供
//##############################################################################
// テーマのCSSに書いた印を読んで動く。デザインのテーマ選択は、CSSを変えたらプレビューの css_init() を呼ぶ
const css_funcs = [];
function css_init(func) {
	css_funcs.push(func);
}
adiary.css_init = function() {
	for(const func of css_funcs) func.call(this);
}
init(adiary.css_init);

////////////////////////////////////////////////////////////////////////////////
// ●CSSから値を取得する
////////////////////////////////////////////////////////////////////////////////
adiary.get_value_from_css = function(id, attr) {
	const span = document.createElement('span');
	span.id = id;
	span.style.display = 'none';
	document.body.appendChild(span);
	const css = getComputedStyle(span);
	if (attr) {
		attr = css.getPropertyValue(attr);
		span.remove();
		return attr;
	}
	const size = css.minWidth;	// 1pxの時のみ有効
	let   str  = css.fontFamily;
	span.remove();
	if (str == null || size != '1px') return '';
	str = str.replace(/["']/g, '');
	return str || size;
}

////////////////////////////////////////////////////////////////////////////////
//●viewport の上書き
////////////////////////////////////////////////////////////////////////////////
css_init(function(){
	const val = this.get_value_from_css('viewport-setting');
	if (!val) return;
	const viewport = document.getElementById('viewport');
	if (viewport) viewport.setAttribute('content', val);
});

////////////////////////////////////////////////////////////////////////////////
//●ui-iconの生成
////////////////////////////////////////////////////////////////////////////////
css_init(function(){
	let color_bin;
	{
		const css = this.get_value_from_css('ui-icon-autoload', 'background-color');
		if (!css) return;
		const col = css.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
		if (col) {
			color_bin = String.fromCharCode(
				parseInt('0x'+col[1]), parseInt('0x'+col[2]), parseInt('0x'+col[3])
			);
		} else {
			const rgb = css.match(/\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)\)/);
			if (!rgb) return;
			color_bin = String.fromCharCode(rgb[1], rgb[2], rgb[3]);
		}
	}

	// generate ui-icon.png（pub/assets/dist/ui-icon/ui-icon.png。2色のパレットのPNGで、0番の色をテーマの色に差し替える）
	let png = atob( 'iVBORw0KGgoAAAANSUhEUgAAAGAAAAAgAQMAAADXDu8XAAAABlBMVEUAAP/8/PzLviUMAAAAAnRSTlP/AOW3MEoAAADbSURBVHjafc4xbsQgEAVQrC0oXMwROAoHyVFSzEo5wF4JawuX6y5NFJBSuAwrN0SgmcxgS0mKDZWfvvl8w7+O+QMCdvqxrsmathImy3y93jbztTWMdbtNL7GaWtvze71fkl3GA8Vl2JPTW22+OEnkjl2eFJLktcAy6m+SJLjzMmqBJDN/CI7qC79yrMejkT9ZF/Q5j1c/RrCRGQlJkWBmwuYJOyZuWBx5QXYBC2Ygt8PlIdkzCIoPkIZwOtsdLg3NdzQMmBXQMXHRai0gnqVa4Puc+PNoH6X4d/U3pK0vLpvA9u4AAAAASUVORK5CYII=')

	// exchange png color
	{
		const PALATTE_OFFSET = 0x29;
		png = png.substr(0, PALATTE_OFFSET) + color_bin + png.substr(PALATTE_OFFSET+3);
	}

	// calc CRC32
	const GEN    = 0xEDB88320;
	const offset = 0x25;
	const length = 10;

	const data = png.substr(offset, length);
	let crc  = 0xffffffff;
	{
		let d;
		let bits = length<<3;
		for(let i=0,j=0; i<bits; i++) {
			if ((i & 7) == 0) d = data.charCodeAt(j++);
			crc ^= (d & 1);
			let x = crc & 1;
			crc >>>=1;
			d   >>>=1;
			if (x) crc ^= GEN;
		}
		crc = ~crc;
		crc = String.fromCharCode( (crc>>>24) & 0xff, (crc>>>16) & 0xff, (crc>>>8) & 0xff, crc & 0xff);
	}
	{
		const p = offset + length;
		png = png.substr(0, p) + crc + png.substr(p+4);
	}
	const style = this.ui_icon_style = this.ui_icon_style || this.append_style();
	style.textContent = '.ui-icon, .art-nav a:before, .art-nav a:after {'
			+ 'background-image: '
			+ 	'url("data:image/png;base64,' + btoa(png) + '")'
			+ '}';
});

//##############################################################################
// ■dom extend
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●textareaでのタブ入力
////////////////////////////////////////////////////////////////////////////////
init(function(){
	const tab_stop = new WeakSet();

	document.addEventListener('focusin', function(evt){
		if (evt.target.tagName === 'TEXTAREA') tab_stop.add(evt.target);
	});

	document.addEventListener('keydown', function(evt){
		const ta = evt.target;
		if (ta.tagName !== 'TEXTAREA' || ta.readOnly || ta.disabled) return;

		// ESC key
		if (evt.keyCode == 27) return tab_stop.add(ta);

		// フォーカス直後のTABは遷移させる
		if (tab_stop.has(ta)) {
			tab_stop.delete(ta);
			return;
		}
		if (evt.shiftKey || evt.keyCode != 9) return;

		evt.preventDefault();
		insert_to_textarea(ta, "\t");
	});
});

////////////////////////////////////////////////////////////////////////////////
//●表示の切り替え（js-switch）
////////////////////////////////////////////////////////////////////////////////
// <input type="checkbox" class="js-switch" data-target="セレクタ"> で、チェックしたら出す。
// data-save があれば、ブラウザーに覚える。asys.js を読んだページでは asys.js が行う
init(function(){
	if (with_asys) return;

	function update(dom, first) {
		const targets = document.querySelectorAll(dom.dataset.target);
		if (!targets.length) return;
		const save = dom.hasAttribute('data-save');
		const key  = dom.id || dom.name || dom.dataset.target;
		if (first && save && storage_get(key) != null) {
			dom.checked = !!parseInt(storage_get(key));
		}
		let show = dom.checked;
		if (dom.dataset.negative) show = !show;

		dom.classList.toggle('sw-show',  show);
		dom.classList.toggle('sw-hide', !show);
		targets.forEach(function(x){ x.style.display = show ? '' : 'none' });
		if (save) storage_set(key, show ? '1' : '0');
	}
	document.querySelectorAll('input.js-switch[type="checkbox"][data-target]').forEach(function(dom) {
		update(dom, true);
		dom.addEventListener('change', function(){ update(dom) });
	});
});

//##############################################################################
// ■スケルトン用ルーチン
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●サイドバーの引き出し（docs/仕様/引き出し.md）
////////////////////////////////////////////////////////////////////////////////
// ボタン（.sidebar-toggle、aria-controls=引き出しのid）で、引き出しを開け閉めする。
// どの幅で、どの要素を引き出しにするかはテーマのCSSが決め、引き出しになっている間は --drawer: 1 を付ける。
// html の has-drawer は、_frame.html の <head> で付ける（表示した後にサイドバーが消えて、ずれないように）
init(function(){
	const buttons = document.querySelectorAll('.sidebar-toggle');
	if (!buttons.length) return;
	const root = document.documentElement;
	const css  = function(el, name) { return getComputedStyle(el).getPropertyValue(name).trim(); };

	// テーマが --drawer-target を付けたときは、その要素を開く（引き出しにするのを、サイドバーの一部にするテーマ）
	function drawerOf(button) {
		const el = document.getElementById(button.getAttribute('aria-controls'));
		const target = el && css(el, '--drawer-target');
		return (target && document.getElementById(target)) || el;
	}

	// 引き出しとボタンの色をテーマが決めていなければ、本文の地の色とサイドバーの文字の色に合わせる（色の調整にも合う）
	if (css(root, '--drawer-bg') === '') {
		const first = Array.from(buttons).map(drawerOf).find(function(x){ return x });
		let bg = '';
		for (let el = first && first.parentElement; el && !bg; el = el.parentElement) {
			const c = getComputedStyle(el).backgroundColor;
			if (c && c !== 'transparent' && !/^rgba\(.*,\s*0\)$/.test(c)) bg = c;
		}
		if (bg)    root.style.setProperty('--drawer-bg', bg);
		if (first) root.style.setProperty('--drawer-fg', getComputedStyle(first).color);
	}

	const backdrop = document.createElement('div');
	backdrop.className = 'drawer-backdrop';
	backdrop.hidden = true;
	document.body.appendChild(backdrop);
	let current = null;	// 開いているボタン
	let current_drawer = null;

	function close(restoreFocus) {
		if (!current) return;
		const button = current;
		current_drawer.classList.remove('is-open');
		current = current_drawer = null;
		button.setAttribute('aria-expanded', 'false');
		root.classList.remove('drawer-open', 'drawer-keep-gutter');
		backdrop.hidden = true;
		if (restoreFocus) button.focus();
	}
	function open(button) {
		close(false);
		const drawer = drawerOf(button);
		if (!drawer) return;
		current = button;
		current_drawer = drawer;
		drawer.tabIndex = -1;	// 開いたときに、引き出しへフォーカスを移す
		drawer.classList.add('is-open');
		button.setAttribute('aria-expanded', 'true');
		// スクロールバーがあったときは、その幅を残す（base.css の drawer-keep-gutter）
		root.classList.toggle('drawer-keep-gutter', window.innerWidth > root.clientWidth);
		root.classList.add('drawer-open');
		backdrop.hidden = false;
		drawer.focus({ preventScroll: true });
	}

	buttons.forEach(function(button) {
		if (!document.getElementById(button.getAttribute('aria-controls'))) return;
		button.addEventListener('click', function() {
			if (current === button) close(true);
			else open(button);
		});
	});

	// 動きを付けるのは、閉じた位置が決まってから（読み込んだ直後や、幅を変えて引き出しになったときに、閉じる動きを出さない）
	function enableAnimation() {
		void document.body.offsetWidth;
		root.classList.add('drawer-animate');
	}
	enableAnimation();
	let resizeTimer = null;
	window.addEventListener('resize', function() {
		root.classList.remove('drawer-animate');
		clearTimeout(resizeTimer);
		resizeTimer = setTimeout(enableAnimation, 200);
		// 幅が変わって引き出しでなくなったら（横に並ぶサイドバーに戻ったら）閉じる
		if (current_drawer && css(current_drawer, '--drawer') !== '1') close(false);
	});

	backdrop.addEventListener('click', function() { close(true); });
	document.addEventListener('keydown', function(evt) {
		if (evt.key === 'Escape' && current) close(true);
	});
	// 引き出しのリンクで移ってから戻ったとき（bfcache）に、開いたままにしない
	window.addEventListener('pageshow', function(evt) { if (evt.persisted) close(false); });
});

////////////////////////////////////////////////////////////////////////////////
//●コメント欄の加工
////////////////////////////////////////////////////////////////////////////////
init(function(){
	const self = this;
	document.querySelectorAll('#com div.comment-text').forEach(function(dom) {
		////////////////////////////////////////////////////////////////
		// リンクに加工 ex) >>14 >>2
		////////////////////////////////////////////////////////////////
		let flag;
		let text = dom.innerHTML;
		text = text.replace(/&gt;&gt;(\d+)/g, function(all, num){
			flag=true;
			return '<a href="#c' + num + '">&gt;&gt;' + num + '</a>';
		});
		if (!flag) return;
		dom.innerHTML = text;

		////////////////////////////////////////////////////////////////
		// regist popup
		////////////////////////////////////////////////////////////////
		dom.querySelectorAll('a').forEach(function(a) {
			self.popup(a, function(a, div) {
				const num = (a.getAttribute('href') || '').replace(/[^\d]/g, '');
				const com = document.getElementById('c' + num);
				if (!com) return;
				div.id        = 'popup-com';
				div.innerHTML = com.innerHTML;
			});
		});
	});
});

////////////////////////////////////////////////////////////////////////////////
//●セキュリティコードの設定
////////////////////////////////////////////////////////////////////////////////
// コメントのスパム対策。決まりはdocs/コメントのスパム対策.mdの「投稿ボタンが押せるようになるまで」
init(function(){
	const form = document.getElementById('comment-form');
	if (!form) return;

	const apkey = document.getElementById('comment-form-apkey');
	let   pkey  = apkey && apkey.value || '';
	const ary   = (form.dataset.secure || '').split(',');
	if (!pkey.match(/^\d+$/)) return;
	pkey = parseInt(pkey) & 255;

	let sid = '';
	for(var i=0; i<ary.length-1; i++) {
		if (!ary[i].match(/^\d+$/)) return;
		sid += String.fromCharCode( ary[i] ^ pkey );
	}
	const sid_input = document.getElementById('comment-form-sid');

	// 記事を編集できる人（ブログ管理者と編集者）は待たせない（data-no-wait）
	if (form.dataset.noWait) {
		sid_input.value = sid;
		return;
	}

	// 投稿ボタンを disable に
	const btn = document.getElementById('post-comment');
	if (btn) btn.disabled = true;

	// 10key押されるか、10秒経ったら設定
	const tas = form.querySelectorAll('textarea');

	let hook;
	let timer;
	const enable_func = function() {
		clearTimeout( timer );
		tas.forEach(function(ta){ ta.removeEventListener('keydown', hook) });
		sid_input.value = sid;
		if (btn) btn.disabled = false;
	};

	let cnt=this.CommentEnableKeys;
	if (cnt) {
		hook = function() {
			cnt--;
			if (cnt) return;
			enable_func();
		}
		tas.forEach(function(ta){ ta.addEventListener('keydown', hook) });
	}

	timer = setTimeout(enable_func, this.CommentEnableTime);
});

////////////////////////////////////////////////////////////////////////////////
// ●検索条件の項目マーク
////////////////////////////////////////////////////////////////////////////////
adiary.init_top_search = function(id, flag) {
	const form = secure(id);
	if (!form) return;
	form.querySelectorAll("div.taglist span.tag, div.ctype span.ctype, div.yyyymm span.yyyymm").forEach(function(dom) {
		const del = document.createElement('span');
		del.className = 'ui-icon ui-icon-close';
		if (!flag) del.addEventListener('click', function(){
			dom.remove();
			form.submit();
		});
		dom.appendChild(del);
	});
	// 検索の対象（タイトル/全文）を切り替えたら、今の条件のまま検索し直す
	if (!flag) form.querySelectorAll('.search-type input[name="all"]').forEach(function(radio) {
		radio.addEventListener('change', function(){
			form.submit();
		});
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●検索画面の「タグで絞り込み」。子のあるタグのボタンで、並びの下の子の枠を開け閉めする
////////////////////////////////////////////////////////////////////////////////
// 同じ並び（階層）で開くのは1つ。ほかを開いたら、前に開いていたものは閉じる
adiary.init_narrow_tag = function(id) {
	const box = secure(id);
	if (!box) return;
	const set = function(btn, open) {
		const panel = document.getElementById(btn.getAttribute('aria-controls'));
		if (!panel) return;
		btn.setAttribute('aria-expanded', open ? 'true' : 'false');
		panel.classList.toggle('is-open', open);
	};
	box.querySelectorAll('button.narrow-tag-open').forEach(function(btn) {
		btn.addEventListener('click', function(){
			const open = btn.getAttribute('aria-expanded') !== 'true';
			if (open) btn.closest('.narrow-tag-row').querySelectorAll('button.narrow-tag-open[aria-expanded="true"]').forEach(function(x) {
				if (x !== btn) set(x, false);
			});
			set(btn, open);
		});
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●検索した語の強調
////////////////////////////////////////////////////////////////////////////////
adiary.word_highlight = function(id) {
	const list = secure(id);
	if (!list) return;
	const words = [];
	for(const dom of list.children) {
		const w = dom.textContent;
		if (w.length < 1) continue;
		words.push( w.toLowerCase() );
	}
	if (!words.length) return;

	const target = document.querySelectorAll("#articles article h2 .title, #articles article div.body div.body-main, #articles span.tags");
	let h_cnt = 0;
	rec_childnodes(target);

	// childnodesを再起関数で探索
	function rec_childnodes(_nodes) {
		// ノードはリアルタイムで書き換わるので、呼び出し時点の状態を保存しておく
		const nodes = Array.from(_nodes);

		// テキストノードの書き換えループ
		for(const node of nodes) {
			if (node.nodeType == Node.TEXT_NODE) {
				const text = node.nodeValue;
				if (text == undefined || text.match(/^[\s\n\r]*$/)) continue;
				do_highlight_string(node);
				h_cnt++; if (h_cnt>999) break;
				continue;
			}
			if (! node.hasChildNodes() ) continue;
			rec_childnodes( node.childNodes );	// 再起
		}
	}
	function do_highlight_string(node) {
		const par  = node.parentNode;
		let   str  = node.nodeValue;
		let   str2 = str.toLowerCase();
		let   find = false;
		while(1) {
			let p=str.length;
			let n=-1;
			for(let i=0; i<words.length; i++) {
				const x = str2.indexOf(words[i]);
				if (x<0 || p<=x) continue;
				p = x;
				n = i;
			}
			if (n<0) break;	// 何も見つからなかった
			// words[n]が位置pに見つかった
			const len  = words[n].length;
			const span = document.createElement('span');
			span.className = "highlight highlight" + n;
			span.appendChild( document.createTextNode( str.substr(p,len) ) );
			if (p) par.insertBefore( document.createTextNode( str.substr(0,p) ), node );
			par.insertBefore( span, node );

			find = true;
			str  = str.substr ( p + len );
			str2 = str2.substr( p + len );
		}
		if (!find) return ;
		// 残った文字列を追加して、nodeを消す
		if (str.length) par.insertBefore( document.createTextNode( str ), node );
		par.removeChild( node );
	}
}

//##############################################################################
// ■スケルトン内部使用ルーチン
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●ソーシャルボタンの加工
////////////////////////////////////////////////////////////////////////////////
// はてなブックマークの件数を読む（ほかのサービスは件数を出さない）。JSONPで読む
init(function(){
	let num = 0;
	document.querySelectorAll('.social-button.hatena-share').forEach(function(dom) {
		const url_orig = dom.dataset.url || '';
		if (!url_orig.match(/^https?:\/\//i)) return;
		const count = dom.querySelector(':scope > a.count');
		if (!count) return;

		// data-urlはencode_uricom済みなので、一度戻してから符号化する
		let url;
		try { url = encodeURIComponent( decodeURIComponent(url_orig) ); }
		catch(e) { url = encodeURIComponent( url_orig ); }

		count.textContent = '-';
		const callback = 'adiary_hatena_count_' + (num++);
		let script;
		window[callback] = function(c) {
			count.textContent = parseInt(c) || 0;
			delete window[callback];
			script.remove();
		};
		script = adiary.load_script('https://bookmark.hatenaapis.com/count/entry?url=' + url + '&callback=' + callback);
	});
});

////////////////////////////////////////////////////////////////////////////////
//●汎用の共有ボタン
////////////////////////////////////////////////////////////////////////////////
// OSの共有の画面を出し、出せなければ記事のURLをコピーする
init(function(){
	document.querySelectorAll('.social-button.web-share').forEach(function(dom) {
		const url_orig = dom.dataset.url || '';
		if (!url_orig.match(/^https?:\/\//i)) return;

		// data-urlはencode_uricom済みなので戻す
		let url;
		try { url = decodeURIComponent(url_orig); }
		catch(e) { url = url_orig; }
		const title = dom.dataset.title || document.title;

		const btn = dom.querySelector(':scope > a.share');
		if (!btn) return;
		btn.addEventListener('click', function(evt) {
			evt.preventDefault();
			if (navigator.share) {
				// 共有の画面を閉じたとき（AbortError）も失敗になるので、何もしない
				navigator.share({ title: title, url: url }).catch(function(){});
				return;
			}
			if (!navigator.clipboard) {	// httpのページなど
				window.prompt('記事のURL', url);
				return;
			}
			navigator.clipboard.writeText(url).then(function(){
				const text = btn.textContent;
				btn.textContent = 'コピーしました';
				setTimeout(function(){ btn.textContent = text; }, 2000);
			}, function(){
				window.prompt('記事のURL', url);
			});
		});
	});
});

////////////////////////////////////////////////////////////////////////////////
//●脚注と注釈のポップアップ
////////////////////////////////////////////////////////////////////////////////
// 本文の脚注（Markdownの[^id]）と注釈（((注釈))）の番号に、注の中身をその場で出す（Wikipediaの参照のポップアップと同じ）。
//   マウスで操作できる端末：番号にマウスを乗せると出す。押すと今までどおり注へ移動する
//   タッチの端末：番号を押すと、移動せずに出す。もう一度押すか、外を押すと閉じる
// 注の中身は、番号と同じ記事（<article>）の中から探す（一覧では、記事ごとに同じidが出るため）。
// 中身がページに無いとき（「続きを読む」で隠れているときなど）は、今までどおりのリンクにする
init(function(){
	const refs = document.querySelectorAll('sup[id^="fnref-"] > a[href*="#fn-"], span.footnote > a[href*="#fn-"]');
	if (!refs.length) return;

	const hover = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
	let popup;		// 出しているポップアップ
	let current;		// ポップアップを出している番号
	let hide_timer;

	// 注の中身を写す。戻るリンク（↩）と、注釈の「*1 : 」は除く
	function note_html(ref) {
		const hash = decodeURIComponent(ref.hash.substr(1));
		const scope = ref.closest('article') || document;
		let note = scope.querySelector('[id="' + hash.replace(/["\\]/g, '\\$&') + '"]');
		if (!note) return;
		// 注釈は、一覧の番号のリンク（<a id="fn-fn1">*1</a>）に id があるので、その段落ごと写す
		const p = note.closest('p.footnote');
		if (p) note = p;
		const box = note.cloneNode(true);
		box.removeAttribute('id');
		box.querySelectorAll('a[href*="#fnref-"]').forEach(function(a) { a.remove(); });
		if (box.matches('p.footnote')) {
			const num = box.querySelector('a');
			if (num) num.remove();
			if (box.firstChild && box.firstChild.nodeType == Node.TEXT_NODE)
				box.firstChild.nodeValue = box.firstChild.nodeValue.replace(/^\s*:\s*/, '');
		}
		box.querySelectorAll('[id]').forEach(function(x) { x.removeAttribute('id'); });
		return box.innerHTML;
	}

	function close() {
		clearTimeout(hide_timer);
		if (popup) popup.remove();
		popup   = null;
		current = null;
	}

	function open(ref, html) {
		close();
		current = ref;
		popup = document.createElement('div');
		popup.className = 'fn-popup';
		popup.setAttribute('role', 'note');
		popup.innerHTML = html;
		if (!hover) {
			// タッチの端末では、押しても移動しないので、注へ移動するリンクを付ける
			const p = document.createElement('p');
			p.className = 'fn-popup-jump';
			const a = document.createElement('a');
			a.href = ref.href;
			a.textContent = '注へ移動';
			a.addEventListener('click', close);
			p.appendChild(a);
			popup.appendChild(p);
		}
		document.body.appendChild(popup);

		// 番号の下に出す。下に入らなければ上に出す。左右は画面からはみ出さないようにする
		const r   = ref.getBoundingClientRect();
		const w   = popup.offsetWidth;
		const h   = popup.offsetHeight;
		const gap = 6;
		let left = r.left + r.width/2 - w/2;
		left = Math.max(8, Math.min(left, document.documentElement.clientWidth - w - 8));
		let top = r.bottom + gap;
		if (top + h > window.innerHeight && r.top - gap - h > 0) top = r.top - gap - h;
		popup.style.left = (left + window.scrollX) + 'px';
		popup.style.top  = (top  + window.scrollY) + 'px';

		if (hover) {
			popup.addEventListener('mouseenter', function(){ clearTimeout(hide_timer); });
			popup.addEventListener('mouseleave', hide_later);
		}
	}
	function hide_later() {
		clearTimeout(hide_timer);
		hide_timer = setTimeout(close, 300);
	}

	refs.forEach(function(ref) {
		const html = note_html(ref);
		if (html === undefined) return;
		ref.removeAttribute('title');	// 注釈のツールチップと二重に出さない
		if (hover) {
			ref.addEventListener('mouseenter', function(){
				clearTimeout(hide_timer);
				if (current !== ref) open(ref, html);
			});
			ref.addEventListener('mouseleave', hide_later);
			ref.addEventListener('focus', function(){ if (current !== ref) open(ref, html); });
			ref.addEventListener('blur',  hide_later);
		} else {
			ref.addEventListener('click', function(evt){
				evt.preventDefault();
				if (current === ref) return close();
				open(ref, html);
			});
		}
	});

	// 外を押すか、Escキーで閉じる
	document.addEventListener('click', function(evt){
		if (!popup || popup.contains(evt.target) || evt.target.closest('a') === current) return;
		close();
	});
	document.addEventListener('keydown', function(evt){
		if (evt.key === 'Escape') close();
	});
	window.addEventListener('resize', close);
});

////////////////////////////////////////////////////////////////////////////////
//●記事の情報の、参照元へのリンク
////////////////////////////////////////////////////////////////////////////////
// 参照元は、テーマの雛形か、参照元のモジュール（dea_backlinks）を置いたときだけ出るので、
// 飛ぶ先が無ければリンクを消す（_sub/art_info.html）
init(function(){
	if (document.getElementById('backlinks')) return;
	document.querySelectorAll('.art-jump .jump-backlinks').forEach(function(a) {
		const span = a.parentNode;
		a.remove();
		if (!span.querySelector('a')) span.remove();
	});
});

////////////////////////////////////////////////////////////////////////////////
//●NSFWの記事の年齢確認
////////////////////////////////////////////////////////////////////////////////
// 「表示する」を押したら、その年齢確認を重ねた先（記事、ブログ全体）だけぼかしを外す。
// 「今後確認しない」も付けていたらブラウザーに覚え（localStorage）、このページのNSFWのぼかしをすべて外す。
// ブログ全体の確認には「今後確認しない」が無く、ブラウザーを閉じるまで覚える（sessionStorage）。
// 覚えたブラウザーでは、_frame.htmlが本文を描く前にぼかしを外す。
// 「確認を元に戻す」を押したら忘れ、このページのNSFWをまたぼかす
init(function(){
	const root = document.documentElement;
	document.querySelectorAll('.nsfw-gate-ok').forEach(function(btn) {
		btn.addEventListener('click', function() {
			const gate = btn.closest('.nsfw-gate');
			const art  = btn.closest('.nsfw');
			if (art) art.classList.add('nsfw-open');

			const chk = gate && gate.querySelector('.nsfw-remember');
			const remember = chk && chk.checked;
			const site     = art && art.classList.contains('nsfw-site');
			if (!remember && !site) return;
			try {
				(remember ? localStorage : sessionStorage).setItem('adiary-nsfw-ok', '1');
			} catch(e) {}
			root.classList.add('nsfw-ok');
		});
	});
	document.querySelectorAll('.nsfw-forget').forEach(function(btn) {
		btn.addEventListener('click', function() {
			try { localStorage.removeItem('adiary-nsfw-ok'); } catch(e) {}
			try { sessionStorage.removeItem('adiary-nsfw-ok'); } catch(e) {}
			root.classList.remove('nsfw-ok');
			document.querySelectorAll('.nsfw.nsfw-open').forEach(function(art) {
				art.classList.remove('nsfw-open');
			});
			document.querySelectorAll('.nsfw-remember').forEach(function(chk) {
				chk.checked = false;
			});
		});
	});
});

////////////////////////////////////////////////////////////////////////////////
//●月別過去ログリストのリロード
////////////////////////////////////////////////////////////////////////////////
init(function(){
	const self   = this;
	const selbox = document.getElementById('month-list-select-box');
	if (!selbox) return;
	selbox.addEventListener('change', function(){
		if (!selbox.dataset.url) return;	// for security
		const val = selbox.value;
		if (val=='') return;
		if (self.Static)
			return window.location = self.myself + 'q/' + val + '.html';
		window.location = self.myself + '?d=' + val;
	});
	const cond = document.getElementById('yyyymm-cond');
	const cur  = cond && cond.dataset.yyyymm;
	if (!cur || !cur.match(/^\d+$/)) return;
	selbox.value = cur;
});

//##############################################################################
// ■other functions
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●特殊Queryの処理
////////////////////////////////////////////////////////////////////////////////
init(function(){
	if (!this.SpecialQuery) return;
	const myself   = this.myself;
	const sp_query = this.SpecialQuery;

	document.querySelectorAll('a').forEach(function(a) {
		let url = a.getAttribute('href');
		if (! url) return;
		if (url.indexOf(myself)!=0) return;
		if (url.match(/\?[\w\/]+$/)) return;		// 管理画面では解除する
		if (url.match(/\?(.+&)?_\w+=/)) return;		// すでに特殊Queryがある

		const ma =  url.match(/^(.*?)(\?.*?)?(#.*)?$/);
		if (!ma) return;
		url = ma[1] + (ma[2] ? ma[2] : '?') + sp_query + (ma[3] ? ma[3] : '');
		a.setAttribute('href', url);
	});
});

////////////////////////////////////////////////////////////////////////////////
//●<script-defer> の実行
////////////////////////////////////////////////////////////////////////////////
// テンプレートの中のスクリプト。初期化の後に動かす。asys.js を読んだページでは asys.js が行う
init(function(){
	if (with_asys) return;
	document.querySelectorAll('script-defer').forEach(function(dom) {
		const script = document.createElement('script');
		script.textContent = dom.innerHTML;
		dom.innerHTML = '';
		dom.appendChild(script);
	});
});

//##############################################################################
// ■init
//##############################################################################
// defer で読み込むので、ほかの defer のスクリプトを読み終えてから動かす（asys.js の init と同じ時）
function run_inits() {
	for(const func of inits) {
		try {
			func.call(adiary);
		} catch(e) {
			console.error(e);
		}
	}
}
if (document.readyState === 'loading')
	document.addEventListener('DOMContentLoaded', run_inits);
else
	run_inits();

//##############################################################################
})();
