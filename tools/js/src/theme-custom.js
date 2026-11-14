//##############################################################################
// adiaryテーマカスタマイズ用JavaScript
//							(C)2015 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';
////////////////////////////////////////////////////////////////////////////////
// ●初期設定
////////////////////////////////////////////////////////////////////////////////
adiary.ready(function(){
	var body = document.getElementById('body');
	var iframe = document.getElementById('iframe');
	var if_css;
	var readme = document.getElementById('readme-button');
	var submit_btn = document.getElementById('submit-btn');

	var sel = document.getElementById('theme-select');
	var theme_query='';

	var theme_dir = sel.dataset.theme_dir;

	function create(tag) {
		return document.createElement(tag);
	}
	// 欄に持たせる値（テーマ初期値、現在の設定値など）
	const vals = new WeakMap();
	function store(obj, key, val) {
		let h = vals.get(obj);
		if (!h) vals.set(obj, h = {});
		if (arguments.length > 2) h[key] = val;
		return h[key];
	}

////////////////////////////////////////////////////////////////////////////////
// ●iframeの自動リサイズ
////////////////////////////////////////////////////////////////////////////////
	// jQueryの $(body).height()、$(iframe).position().top と同じ値を求める
	function body_height() {
		const cs = getComputedStyle(body);
		let h = parseFloat(cs.height) || 0;
		if (cs.boxSizing === 'border-box')
			for(const s of ['Top', 'Bottom'])
				h -= (parseFloat(cs['padding' + s]) || 0) + (parseFloat(cs['border' + s + 'Width']) || 0);
		return h;
	}
	function iframe_top() {
		// 親（offsetParent）の枠の内側からの位置。端数も出す（offsetTop は整数になる）
		const op = iframe.offsetParent || document.documentElement;
		const pr = op.getBoundingClientRect();
		const pt = pr.top + (parseFloat(getComputedStyle(op).borderTopWidth) || 0);
		return iframe.getBoundingClientRect().top - pt - (parseFloat(getComputedStyle(iframe).marginTop) || 0);
	}
	function iframe_resize() {
		var h = body_height() - iframe_top();
		const dbg = document.getElementById('debug-msg');
		if (dbg) dbg.innerHTML = body_height() + ' / ' + iframe_top();
		iframe.style.height = h + 'px';
	}
	iframe_resize();
	window.addEventListener('resize', iframe_resize);

////////////////////////////////////////////////////////////////////////////////
// ●テーマ変更時の処理
////////////////////////////////////////////////////////////////////////////////
{
var timer;
var current_theme;
function theme_change(){
	var theme = sel.value;
	if (timer || current_theme == theme) return;
	current_theme = theme;

	theme_query = '&_theme=' + theme;
	iframe.setAttribute('src', adiary.myself + '?' + theme_query );
	var opt = sel.selectedOptions[0];
	if (opt && opt.dataset.readme) {
		readme.setAttribute('data-url', adiary.myself + '?design/theme_readme&name=' + theme);
		readme.disabled = false;
	} else {
		readme.setAttribute('data-url', '');
		readme.disabled = true;
	}
	// カスタマイズ機能の初期化
	init_custmize(theme);
}
sel.addEventListener('change', theme_change);
theme_change();
// ↑↓キーでめくる
sel.addEventListener('keyup', function(evt){
	if (evt.keyCode != 38 && evt.keyCode != 40) return;
	if (timer) clearTimeout(timer);
	timer = setTimeout( function(){
		timer = null;
		theme_change();
	}, 300 );
});
// GCで標準でめくる動作（changeイベント発生）を止める
sel.addEventListener('keydown', function(evt){
	if (evt.keyCode != 38 && evt.keyCode != 40) return;
	if (!timer) timer = setTimeout( function(){}, 100 );	// dummy
});

}
////////////////////////////////////////////////////////////////////////////////
// ●iframe内ロード（CSS欄追加。リンク書き換え）
////////////////////////////////////////////////////////////////////////////////
iframe.addEventListener('load', function(){
	const doc = iframe.contentDocument;
	if (!doc) return;
	// 選択中テーマがちゃんとロードされているか確認
	const theme_css = doc.getElementById('theme-css');
	var ftheme = theme_css && theme_css.getAttribute('href');
	if (!ftheme) return;
	ftheme = ftheme.replace(/^.*\/([\w\-]+\/[\w\-]+)\/[\w\-]+\.css(?:\?.*)?$/, "$1");
	if (ftheme != current_theme) return;

	if_css = doc.createElement('style');
	if_css.setAttribute('type', 'text/css');
	doc.head.appendChild(if_css);

	if (!theme_query) return;
	doc.querySelectorAll('a').forEach(function(obj) {
		var url = obj.getAttribute('href');
		if (! url) return;
		if (url.indexOf(adiary.myself)!=0) return;
		if (url.match(/\?(.+&)?_\w+=/)) return;	// すでに特殊Queryがある

		// デザイン画面では解除
		if (url.match(/\?design\//)) {
			obj.setAttribute('target', '_top');
			return;
		}

		var ma =  url.match(/^(.*?)(\?.*?)?(#.*)?$/);
		if (!ma) return;
		url = ma[1] + (ma[2] ? ma[2] : '?') + theme_query + (ma[3] ? ma[3] : '');
		obj.setAttribute('href', url);
	});

	if (css_text) {
		doc.querySelectorAll('#theme-custom-css').forEach(function(x){ x.remove() });
		update_css();
	}
});
//##############################################################################
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// ●カスタマイズ機能
////////////////////////////////////////////////////////////////////////////////
	var custom_form  = document.getElementById('custom-form');
	var color_bar    = document.getElementById('custom-color-bar');
	var custom_opts  = document.getElementById('custom-options');
	var custom_cols  = document.getElementById('custom-colors-base');
	var custom_detail= document.getElementById('custom-colors-detail');

	var input_cols  = [];
	var select_opts = [];
	var rel_col;
	var rel_pol;

	var cols;
	var opts;
	var css_text;

	function show(dom, flag) {
		dom.style.display = flag ? '' : 'none';
		if (flag && getComputedStyle(dom).display === 'none') dom.style.display = 'block';
	}

////////////////////////////////////////////////////////////////////////////////
// ●カスタマイズ情報のロード
////////////////////////////////////////////////////////////////////////////////
function init_custmize(name) {
  cols = undefined;
  opts = undefined;
  css_text = '';
  submit_btn.disabled = true;
  // 読めないときと、JSONでないときは、カスタマイズ無し（今までの $.ajax の error と同じ）
  fetch(adiary.myself + '?design/theme_colors&name=' + name).then(function(res){
	if (!res.ok) throw res.status;
	return res.json();
  }).then(function(data){
	if (!data || data.error || !data._css_text)
		return custom_form_empty();
	// 値保存
	css_text = data._css_text;
	delete data['_css_text'];
	var data2 = data._options;
	delete data['_options'];
	document.getElementById('custom-flag').value = '1';

	// フォーム初期化
	init_custom_form(data, data2);
	submit_btn.disabled = false;
  }, function(){
	custom_form_empty();
  });
}
function custom_form_empty() {
	show(custom_form, false);
	custom_opts.innerHTML   = '';
	custom_cols.innerHTML   = '';
	custom_detail.innerHTML = '';
	input_cols  = [];
	select_opts = [];
	iframe_resize();
	document.getElementById('custom-flag').value = '';
	submit_btn.disabled = false;
}

////////////////////////////////////////////////////////////////////////////////
// ●カスタマイズフォーム設定
////////////////////////////////////////////////////////////////////////////////
function init_custom_form(data, data2) {
	cols = [];

	// データの取り出しと並べ替え
	var priority = ['base', 'main', 'art', 'wiki', 'footnote', 'border'];
	function get_priority(name) {
		if (name.indexOf( 'fix' ) == 0) return 1000;
		for(var i=0; i<priority.length; i++)
			if (name.indexOf( priority[i] ) == 0) return i;
		return 999;
	}
	var err='';
	for(var k in data) {
		if (k.substr(0,5) == '-err-') {
			err += '<div>' + data[k] + '</div>';
			continue;
		}
		// rgbaを変更
		var ma = data[k].match(/rgba\((\d+),(\d+),(\d+)/);	// rgba(255,255,255, 0.7)
		if (ma) {
			var val = '#';
			for(var i=1; i<4; i++)
				val += ('0' + (parseInt(ma[i])).toString(16)).substr(-2);
			data[k] = val;
			// console.log(val);
		}

		if (k.substr(-4) == '-cst') continue;
		if (k.substr(-4) == '-rel') continue;
		cols.push({name: k, val: data[k], priority: get_priority(k) });
	}
	if (err.length) adiary.show_error({html: err});
	cols = cols.sort(function(a, b) {
		if (a.priority < b.priority) return -1;
		if (a.priority > b.priority) return  1;
	        return (a.name < b.name) ? -1 : 1;
	});

	// フォームの生成
	custom_opts.innerHTML   = '';
	custom_cols.innerHTML   = '';
	custom_detail.innerHTML = '';
	input_cols = [];
	rel_col = [];
	rel_pol = [];
	for(var i=0; i<cols.length; i++) {
		var name = cols[i].name;
		var val  = cols[i].val;
		var cval = data[name+'-cst'] || val;	// 初期値
		var rel  = data[name+'-rel'];		// 他に連動
		var msg  = name2msg(name);

		var span = create('span');
		span.className = 'color-box';
		span.textContent = msg;
		var inp = create('input');
		inp.className = 'color-picker no-enter-submit';
		inp.setAttribute('type',  'text');
		inp.setAttribute('id',    'inp-' + name);
		inp.setAttribute('name',  'c_' + name);
		inp.setAttribute('value', cval);
		store(inp, 'original', val);	// テーマ初期値
		store(inp, 'default_', cval);	// 現在の設定値（保存用）
		store(inp, 'default',  cval);	// 現在の設定値
		inp.addEventListener('change', update_css);
		(function(){
			var n = name;		// クロージャ
			// 色の窓で選んでいる間（admin.js）
			inp.addEventListener('color-input', function() {
				relation_colors(n);
				update_css();
			});
		})();
		span.appendChild(inp);
		input_cols.push(inp);
		if (rel) rel_col[name] = rel;

		// 要素を追加
		var div = rel ? custom_detail : custom_cols;
		if (name.substr(0,3) == 'fix'
		 && name != 'fixbg' && name != 'fixmain' && name != 'fixartbg' && name != 'fixfont')
			div = custom_detail;
		div.appendChild(span);
	}

	// color picker init
	adiary.dom_init( custom_form );

	// オプション選択生成
	opts = [];
	select_opts = [];
	if (data2) {
		for(var k in data2) {
			if (k.substr(-4) == '-cst') continue;
			opts.push({name: k, val: data2[k + '-cst'], list: data2[k] });
		}
		opts = opts.sort(function(a, b) {
		        return (a.name < b.name) ? -1 : 1;
		});

		for(var i=0; i<opts.length; i++) {
			var name = opts[i].name;
			if (name.match(/-\w+$/)) continue;

			var osel = create('select');
			osel.setAttribute('name', name);
			var title = data2[name + '-title'] || 'option';
			var o0 = create('option');
			o0.setAttribute('value', '');
			o0.textContent = name2msg(title);
			osel.appendChild(o0);
			osel.addEventListener('change', update_css);
			var list = opts[i].list;
			var val  = opts[i].val || '';
			store(osel, 'default',  val);
			store(osel, 'original', data2[name + '-default'] || '');
			var h = {};
			for(var j=0; j<list.length; j++) {
				if (h[list[j]]) continue;	// 重複チェック
				h[list[j]]=1;

				var n = name2msg( list[j] );	// 翻訳
				var o = create('option');
				o.setAttribute('value', list[j]);
				o.textContent = n;
				if (list[j] == val) o.selected = true;
				osel.appendChild(o);
			}
			custom_opts.appendChild( osel );
			select_opts.push( osel );
		}
	}
	show(color_bar, cols.length >= 1);
	show(custom_form, true);
	iframe_resize();

	// すべてロードされる前に送信されることがある。
	var flag = create('input');
	flag.setAttribute('type',  'hidden');
	flag.setAttribute('name',  'custom_flag');
	flag.setAttribute('value', 1);
	custom_form.appendChild(flag);

	// 色式デバッグ用（テーマ開発者向け）
	relation_colors('', 1);
}

////////////////////////////////////////////////////////////////////////////////
// ●値連動処理
////////////////////////////////////////////////////////////////////////////////
function relation_colors(name, test) {
	for(var k in rel_col) {
		var col = rel_col[k];
		var v;
		if (col.substr(0,5) == 'auto:')
			v = automatic(k, col.substr(5));
		else {
			var src = document.getElementById('inp-' + col);
			v = src ? src.value : undefined;
		}
		// console.log(k + ' = ' + v + ' = ' + col );
		if (!v) {
			adiary.show_error('#css-exp-error', {s: rel_col[k]});
			continue;
		}
		var obj = document.getElementById('inp-' + k);
		if (obj) set_color(obj, v);
	}
}

////////////////////////////////////////////////////////////////////////////////
// ●カスタマイズフォーム設定
////////////////////////////////////////////////////////////////////////////////
var CSS_ReInit;
setInterval(function(){
	if (!CSS_ReInit) return;
	CSS_ReInit = false;
	iframe.contentWindow.adiary.css_init();
},300);

function update_css() {
	var col = {};
	input_cols.forEach(function(obj){
		var val = obj.value;
		if (val.match(/#[0-9A-Fa-f]{6}/))
			col[ obj.getAttribute('name').substr(2) ] = val;
	});
	var opt = {};
	select_opts.forEach(function(obj){
		opt[ obj.getAttribute('name') ] = obj.value;
	});
	var lines = css_text.split("\n");
	var in_opt;
	var opt_sel;
	for(var i=0; i<lines.length; i++) {
		var x = lines[i];
		// 画像ファイル
		var ma = x.match(/(.*?)url\s*\(\s*(['"])([^'"]+)\2\s*\)(.*)/i);
		if (ma) {
			var file = ma[3];
			file = file.replace('./', '');
			if (file.match(/^[\w-]+(?:\.[\w-]+)*$/))
				x = ma[1] + "url('" + theme_dir + current_theme + '/' + file + "')" + ma[4];
			lines[i] = x;
		}
		// オプション
		var ma = in_opt || x.match(/\$(option\d*)=(.+)/);
		if (ma) {
			if (!in_opt) {
				in_opt  = true;
				opt_sel = (opt[ ma[1] ] == ma[2]);
				lines[i]='';
			} else if (ma = x.match(/(.*?)\s*\*\//)) {
				in_opt = false;
				x = ma[1];
				ma = x.match(/^(.*[;}])/);
				if (ma) x=ma[1];
				   else x='';
				lines[i]=x;
			}
			if (!opt_sel) lines[i]='';
			continue;
		}

		// 色カスタム
		var ma = x.match(/\$c=(\w+)/);
		if (!ma) continue;
		lines[i] = x.replace(/#[0-9A-Fa-f]+/,     col[ ma[1] ])
		            .replace(/rgba\(\d+,\d+,\d+/, RGBtoRGBA( col[ ma[1] ] ));
	}
	var new_css = lines.join("\n");
	if (if_css) if_css.textContent = new_css;

	// CSSによる設定反映
	// iframe.contentWindow.adiary.css_init();
	CSS_ReInit = true;
}

function RGBtoRGBA(rgb) {
	var ma = rgb.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
	if (!ma) return "rgba(0,0,0";

	var r = parseInt('0x' + ma[1]);
	var g = parseInt('0x' + ma[2]);
	var b = parseInt('0x' + ma[3]);
	return 'rgba(' + r + ',' + g + ',' + b;
}

////////////////////////////////////////////////////////////////////////////////
// ●リセット
////////////////////////////////////////////////////////////////////////////////
document.getElementById('btn-reset').addEventListener('click', function() {
	input_cols.forEach(function(obj){
		var col = store(obj, 'default_');
		store(obj, 'default', col);
		set_color(obj, col);
	});
	select_opts.forEach(function(obj){
		obj.value = store(obj, 'default');
	});
	form_reset();
	update_css();
});

////////////////////////////////////////////////////////////////////////////////
// ●テーマ初期値リセット
////////////////////////////////////////////////////////////////////////////////
document.getElementById('btn-super-reset').addEventListener('click', function() {
	input_cols.forEach(function(obj){
		var col = store(obj, 'original');
		store(obj, 'default', col);
		set_color(obj, col);
	});
	select_opts.forEach(function(obj){
		obj.value = store(obj, 'original');
	});
	form_reset();
	update_css();
});


////////////////////////////////////////////////////////////////////////////////
// ●色を設定
////////////////////////////////////////////////////////////////////////////////
// 文字の欄と、前の色の窓（admin.js）に入れる。イベントは起こさない
function set_color(obj, rgb) {
	obj.value = rgb;
	var prev = obj.previousElementSibling;
	if (prev && prev.classList.contains('colorbox')) {
		const v = adiary.color_value(rgb);
		if (v) prev.value = v;
	}
}

////////////////////////////////////////////////////////////////////////////////
// ●色一括変更機能
////////////////////////////////////////////////////////////////////////////////
var h_slider = document.getElementById('h-slider');
var s_slider = document.getElementById('s-slider');
var v_slider = document.getElementById('v-slider');
function change_hsv() {
	if (!if_css) return;
	var h = Number( h_slider.value );
	var s = Number( s_slider.value );
	var v = Number( v_slider.value );

	var cols = input_cols;
	for(var i=0; i<cols.length; i++) {
		var obj = cols[i];
		var name=obj.getAttribute('name');
		if (name.indexOf('c_fix') == 0) continue;

		var hsv = RGBtoHSV( store(obj, 'default') );
		if (!hsv) return;
		// 色変換
		hsv.h += h;
		hsv.s *= (s/160);
		hsv.v *= (v/256);
		var rgb = HSVtoRGB( hsv );
		set_color(obj, rgb);
	}
	update_css();
}
[h_slider, s_slider, v_slider].forEach(function(x){
	x.addEventListener('input', change_hsv);
});
form_reset();

function form_reset() {
	h_slider.value = 0;
	s_slider.value = 160;
	v_slider.value = 256;
}

////////////////////////////////////////////////////////////////////////////////
// ●RGBtoHSV
////////////////////////////////////////////////////////////////////////////////
function RGBtoHSV(str) {
	var ma = str.match(/#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
	if (!ma) return ;

	var r = parseInt('0x' + ma[1]);
	var g = parseInt('0x' + ma[2]);
	var b = parseInt('0x' + ma[3]);

	var v  =  0.29900*r + 0.58700*g + 0.114*b;	// =Y
	var cb = -0.16874*r - 0.33126*g + 0.500*b;
	var cr =  0.50000*r - 0.41869*g - 0.081*b;

	var h = 180 * Math.atan2(cr, cb) / Math.PI;
	var s = Math.sqrt(cb*cb + cr*cr);
	return { h: h, s: s, v: v };
}

////////////////////////////////////////////////////////////////////////////////
// ●HSVtoRGB
////////////////////////////////////////////////////////////////////////////////
function HSVtoRGB( hsv ) {
	var h = hsv.h;
	while(h>180) h-=360;
	var rad = Math.PI * h / 180;
	var cb  = hsv.s * Math.cos( rad );
	var cr  = hsv.s * Math.sin( rad );
	var r  = Math.round(hsv.v            + 1.402*cr);
	var g  = Math.round(hsv.v - 0.344*cb - 0.714*cr);
	var b  = Math.round(hsv.v + 1.772*cb           );

	// safety
	if (r<0) r=0;
	if (g<0) g=0;
	if (b<0) b=0;
	if (255<r) r=255;
	if (255<g) g=255;
	if (255<b) b=255;

	// 文字列変換
	r = (r<16 ? '0' : '') + r.toString(16);
	g = (g<16 ? '0' : '') + g.toString(16);
	b = (b<16 ? '0' : '') + b.toString(16);
	return '#' + r + g + b;
}

////////////////////////////////////////////////////////////////////////////////
// ●色名の翻訳
////////////////////////////////////////////////////////////////////////////////
	var n2msg = {};
{
	// 色名の翻訳テキスト
	var ary = document.getElementById('attr-msg').innerHTML.split("\n");
	for(var i=0; i<ary.length; i++) {
		var line = ary[i];
		var ma = line.match(/(.*?)\s*=\s*([^\s]*)/);
		if (ma) n2msg[ma[1]] = ma[2];
	}
}
function name2msg(name) {
	for(var n in n2msg) {
		name = name.replace(n + '-', n2msg[n]);
		name = name.replace(n      , n2msg[n]);
	}
	return name;
}

////////////////////////////////////////////////////////////////////////////////
// ●値の自動連動
////////////////////////////////////////////////////////////////////////////////
function automatic(des_name, src_name) {
	var des = document.getElementById('inp-' + des_name);
	var src = document.getElementById('inp-' + src_name);
	if (!des || !src) return;
	var c_des = store(des, 'original');
	var c_src = store(src, 'original');
	var c_cur = src.value;
	if (!c_des || !c_src || !c_cur) return;
	if (c_src == c_cur) return c_des;

	// HSV空間での差分
	var h_des = RGBtoHSV( c_des );
	var h_src = RGBtoHSV( c_src );
	var diff = [];
	diff.h = h_des.h - h_src.h;
	diff.s = h_des.s - h_src.s;
	diff.v = h_des.v - h_src.v;
/*	// 比では黒をうまく扱えない
	diff.s = h_des.s / (h_src.s || 0.0000001);	//
	diff.v = h_des.v / (h_src.v || 0.0000001);	// 0除算防止
*/

	// 今の色に変化を適用
	var hsv = RGBtoHSV( c_cur );
	// console.log(hsv.h, hsv.s, hsv.v);
	hsv.h = hsv.h + diff.h;
	hsv.s = hsv.s + diff.s;
	hsv.v = hsv.v + diff.v;
	// console.log(des_name,"-->",hsv.h, hsv.s, hsv.v);

	return HSVtoRGB( hsv );
}


//##############################################################################
});
