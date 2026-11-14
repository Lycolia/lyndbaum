//##############################################################################
// admin.js
//	管理画面でだけ使う処理。asys.js と adiary.js の後に読み込む
//	※公開画面のフレーム（_frame）でも、システムモード（デザイン編集など）のときと、
//	  ログイン中（記事のページのコメントの管理など）は読み込む
//##############################################################################
//[TAB=8]
'use strict';
{
// 公開画面の処理（adiary.js）。asys.js を読んだページでは、adiary は asys.js（$$）になる
const adiary_public = window.adiary_public;

// asys.js の初期化の後に動かす
$$.ready(function(){
//##############################################################################
// ■initalize
//##############################################################################
(function(){
	this.DialogWidth       = -1;	// auto
	this.DialogMinWidth    = 480;

	// load adiary vars
	const data = this.asys_vars;
	const ary  = ['ScriptDir', 'PubdistDir', 'SpecialQuery', 'Static'];
	for(var i in ary) {
		this[ary[i]] = data[ary[i]];
	}

	// Smartphone mode
	this.SP = adiary_public.SP;
	if (this.SP) {
		this.DialogWidth    = 320;
		this.DialogMinWidth =   0;
	}

	// load message
	this.load_msg('[data-secure].adiary-msgs');

}).call(adiary);

////////////////////////////////////////////////////////////////////////////////
// ●公開画面の処理（adiary.js）を adiary.〜 で呼べるようにする
////////////////////////////////////////////////////////////////////////////////
// テンプレートの <script-defer> と、デザインのテーマ選択（プレビューの css_init）と、
// 画面のJS（secure）から呼ぶ
for(const name of ['css_init', 'get_value_from_css', 'init_top_search', 'init_narrow_tag', 'word_highlight', 'secure']) {
	$$[name] = function() {
		return adiary_public[name].apply(adiary_public, arguments);
	};
}

//##############################################################################
// ■dom extend
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●詳細情報ダイアログの表示
////////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	let prev;
	const self=this;
	document.body.addEventListener('click', function(evt){
		const obj = evt.target;
		if (!obj.matches || !obj.closest('.js-info[data-info], .js-info[data-url]')) return;

		if (obj == prev) return;	// 連続クリック防止
		prev = obj;

		// 値は、そのときの属性から読む（theme-custom.jsがdata-urlを書き換えるため）。
		// 今までと同じく、押した要素（evt.target）から読む
		const div  = document.createElement('div');
		const div2 = document.createElement('div');	// 直接divにクラスを設定すると表示が崩れる

		div.setAttribute('title', obj.getAttribute("data-title") || "Infomataion" );
		const cls = obj.getAttribute("data-class");
		if (cls) div2.className = cls;
		div.appendChild(div2);
		if (obj.getAttribute('data-info')) {
			div2.innerHTML = self.tag_esc_br( obj.getAttribute("data-info") );
			self.dialog(div, { width: self.DialogWidth, close: close_func });
			return;
		}
		// 今までの.load()と同じく、読めなくても開く
		const url = obj.getAttribute("data-url");
		fetch(url).then(function(res){
			return res.ok ? res.text() : '';
		}).catch(function(){
			return '';
		}).then(function(html){
			div2.innerHTML = html;
			div2.textContent = div2.textContent.replace(/\n*$/, "\n\n");
			self.dialog(div, { width: self.DialogWidth, height: 320, close: close_func });
		});
	});
	function close_func() {
		prev = null;
	}
});

////////////////////////////////////////////////////////////////////////////////
//●画像・コメントのポップアップ
////////////////////////////////////////////////////////////////////////////////
// メディア管理のファイル名（media.js）、コメントの一覧（comlist.html）
$$.init( function(){
	const self = this;
	this.popup_on('.js-popup-img', {
		show: function(obj, div) {
			const img = document.createElement('img');
			img.setAttribute('src', obj.getAttribute('data-img-url'));
			div.innerHTML = '';
			div.setAttribute('id', 'popup-image');
			div.appendChild( img );
		}
	});
	document.querySelectorAll('.js-popup-img').forEach(function(x){ x.removeAttribute('title') });	// remove title attr popup

	this.popup_on('.js-popup-com', {
		show: function(obj, div){
			const num = obj.getAttribute('data-target');
			if (num == '' || num == 0) return div.innerHTML = '';

			const com = self.secure('#c' + num);
			if (!com) return div.innerHTML = '';

			div.setAttribute('id', 'popup-com');
			div.innerHTML = com.innerHTML;
		}
	});
});

////////////////////////////////////////////////////////////////////////////////
//●一覧の表は、本文に収まらないときだけ1件ずつ並べる（admin.css の .list-card）
////////////////////////////////////////////////////////////////////////////////
// 列の幅は名前やタグの長さで変わるので、画面の幅ではなく、表の幅と置き場所の幅を比べて決める
$$.init( function(){
	const tables = document.querySelectorAll('table.list-table');
	if (!tables.length) return;

	function fit() {
		for(const table of tables) {
			const box = table.parentElement;
			const css = getComputedStyle(box);
			const width = box.clientWidth - parseFloat(css.paddingLeft) - parseFloat(css.paddingRight);
			// 表のときの幅を測る（表は width:100% なので、収まるなら置き場所の幅になる）
			table.classList.remove('list-card');
			if (table.offsetWidth > width + 0.5) table.classList.add('list-card');
		}
	}
	fit();
	// 置き場所の幅は画面の幅で変わる（ナビの位置も画面の幅で変わる）。表の幅は、フォントを読み終えると変わる
	let timer;
	window.addEventListener('resize', function(){
		cancelAnimationFrame(timer);
		timer = requestAnimationFrame(fit);
	});
	window.addEventListener('load', fit);
	if (document.fonts) document.fonts.ready.then(fit);
});

//##############################################################################
// ■UI
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●色選択ボックスを表示。 ※input[type=text] のリサイズより先に行うこと
////////////////////////////////////////////////////////////////////////////////
// 文字の欄（input.color-picker）の前に、ブラウザーの色の窓（input[type=color].colorbox）を置く。
//	・色の窓で選んでいる間は、文字の欄に値を入れて「color-input」のイベントを起こす
//	・決めたときは、文字の欄に値を入れて change を起こす
//	・文字の欄に色を入れたら、色の窓も合わせる（#rgb、#rrggbb のときだけ）
// color_value() は theme-custom.js も使う
const color_boxed = new WeakSet();	// 色の窓を付けた欄（dom_init は、同じ部分にもう一度呼ばれることがある）
$$.color_value = function(val) {
	const ma = String(val || '').match(/^#([\dA-Fa-f]{3}|[\dA-Fa-f]{6})$/);
	if (!ma) return;
	let x = ma[1];
	if (x.length == 3) x = x[0]+x[0] + x[1]+x[1] + x[2]+x[2];
	return '#' + x.toLowerCase();
};
$$.dom_init( function(R){
	const self = this;
	this.find_all(R, 'input.color-picker').forEach(function(inp){
		if (color_boxed.has(inp)) return;
		color_boxed.add(inp);

		const box = document.createElement('input');
		box.setAttribute('type', 'color');
		box.className = 'colorbox';
		box.tabIndex  = -1;
		inp.before(box);

		function from_text() {
			const v = self.color_value(inp.value);
			if (v) box.value = v;
		}
		from_text();
		inp.addEventListener('input',  from_text);
		inp.addEventListener('change', from_text);

		box.addEventListener('input', function(){
			inp.value = box.value;
			inp.dispatchEvent(new Event('color-input', { bubbles: true }));
		});
		box.addEventListener('change', function(){
			inp.value = box.value;
			inp.dispatchEvent(new Event('change', { bubbles: true }));
		});
	});
});

//##############################################################################
// ■スケルトン用ルーチン
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// ●タグ一覧のロード
////////////////////////////////////////////////////////////////////////////////
// id は選択子か要素。読み込んで option を足した後に、change を起こす
function select_of(id) {
	return typeof(id) === 'string' ? document.querySelector(id) : id;
}
// 今までの$.getJSONと同じく、読めなくても何も出さない（返すPromiseには、失敗の処理を付けておく）
function load_json(url, func) {
	const p = fetch(url).then(function(res){
		if (!res.ok) throw new Error(res.status + ' ' + res.statusText);
		return res.json();
	}).then(func);
	p.catch(function(){});
	return p;
}
function append_option(sel, value, html) {
	const opt = document.createElement('option');
	opt.setAttribute('value', value);
	opt.innerHTML = html;
	sel.appendChild(opt);
	return opt;
}
$$.load_tags_list = function(id, callback) {
	const sel = select_of(id);	// セレクトボックス
	if (!sel) return;
	const _default = sel.dataset.default || '';

	return load_json( sel.dataset.url, function(data){
		if (callback) callback(data);
		var r_func = function(ary, head, tab) {
			for(var i=0; i<ary.length; i++) {
				var name= ary[i].title;
				var val = head + name;
				//padding-left はFx以外で効かないので、全角の空白で字下げする
				var opt = append_option(sel, val, '&emsp;'.repeat(tab) + val);
				if ( val == _default ) opt.selected = true;
				if (ary[i].children)
					r_func( ary[i].children, head+name+'::', tab+1 );
			}
		};
		r_func(data, '', 0);
		fire_change(sel);
	});
}
function fire_change(dom) {
	dom.dispatchEvent(new Event('change', { bubbles: true }));
}

////////////////////////////////////////////////////////////////////////////////
// ●固定ページの一覧のロード
////////////////////////////////////////////////////////////////////////////////
// Promise を返す（option を足して change した後に解決する）
$$.load_contents_list = function(id) {
	const sel = select_of(id);
	if (!sel) return Promise.reject(new Error('select not found'));
	return load_json( sel.dataset.url, function(data){
		var _default  = sel.dataset.default;
		var this_pkey = sel.dataset.thisPkey;

		var r_func = function(ary, tab) {
			for(var i=0; i<ary.length; i++) {
				var pkey  = ary[i].key;
				if (pkey == this_pkey) continue;
				var title = ary[i].title;
				if (title.length > 20)
					title = title.substr(0,20) + '...';

				//padding-left はFx以外で効かないので、全角の空白で字下げする
				var opt = append_option(sel, pkey, '&emsp;'.repeat(tab) + title);
				if (ary[i].link_key !== undefined)
					opt.setAttribute('data-link_key', ary[i].link_key);	// edit.js が dataset.link_key で読む
				if ( pkey == _default ) opt.selected = true;
				if (ary[i].children)
					r_func( ary[i].children, tab+1 );
			}
		};
		r_func(data, 0);
		fire_change(sel);
		return data;
	});
}

//##############################################################################
// ■その他
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// ●さつきタグ記号のエスケープ
////////////////////////////////////////////////////////////////////////////////
$$.esc_satsuki_tag = function(str) {
	return str.replace(/([:\[\]])/g, function(w,m){ return "\\" + m; });
}
$$.unesc_satsuki_tag = function(str) {
	return str.replace(/\\([:\[\]])/g, "$1");
}

////////////////////////////////////////////////////////////////////////////////
// ●セッションを保持して随時データをロードする
////////////////////////////////////////////////////////////////////////////////
// ボタンを押すと、セッションを作り、処理を送る。処理の間は、ログ（?etc/load_session）を読み続けて出す
//	adiary.session(ボタン, opt)	… ボタンは選択子、要素、要素の並び
//	opt.myself		送る先（既定はadiary.myself）
//	opt.load_log(evt)	ログを出す要素を返す（既定は、ボタンのdata-log-targetか、#session-log）
//	opt.load_formdata(btn)	送る中身（FormDataか、URLエンコードした文字列）。既定はnew FormData(opt.form)
//	opt.interval		ログを読む間隔（既定は、ログの要素のdata-intervalか、300ms）
//	opt.dataType		返事の形（'text'か'json'。既定は'text'）
//	opt.init(evt)、opt.success(data)、opt.error(xhr, status, msg)、opt.complete()
//	opt.progress(e)		アップロードの進み具合（XMLHttpRequestのuploadのprogress）
$$.session = function(btns, opt){
  const self=this;
  if (typeof(btns) === 'string') btns = document.querySelectorAll(btns);
  else if (btns instanceof Element) btns = [ btns ];
  Array.from(btns).forEach(function(b){ b.addEventListener('click', function(evt){
	var btn    = evt.currentTarget;
	var myself = opt.myself || self.myself;
	var log    = document.querySelector(btn.getAttribute('data-log-target') || '#session-log');

	var load_session = myself + '?etc/load_session';
	var interval = opt.interval || (log && Number(log.getAttribute('data-interval'))) || 300;
	var snum;

	if (opt.load_log) log = opt.load_log(evt);
	self.show_delay(log);
	if (opt.init) opt.init(evt);

	// セッション初期化
	const body = new URLSearchParams();
	body.append('action', 'etc/init_session');
	fetch(load_session, { method: 'POST', body: body }).then(function(res){
		if (!res.ok) throw new Error(res.status + ' ' + res.statusText);
		return res.text();
	}).then(function(data) {
		var reg = data.match(/snum=(\d+)/);
		if (reg) {
			snum = reg[1];
			ajax_session();
			return;
		}
		console.warn(data);
	}).catch(function(){});		// 今までの$.postと同じく、送れなかったときは何もしない

	// Ajaxセッション開始
	function ajax_session(){
		log_start();
		var fd;
		if (opt.load_formdata) fd = opt.load_formdata(btn);
				else   fd = new FormData( opt.form );
		if (typeof(fd) == 'string') fd += '&snum=' + snum;
				else	fd.append('snum', snum);

		var xhr = new XMLHttpRequest();
		xhr.open('POST', myself + '?etc/ajax_dummy');
		if (typeof(fd) == 'string')	// 今までの$.ajaxと同じ
			xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
		if (opt.progress) xhr.upload.addEventListener('progress', opt.progress);
		var error = function(status, msg) {
			const e_msg = '[' + self.name + '.session()] Ajax fail: ' + msg;
			console.warn(e_msg);
			log_stop(function(){
				log.textContent = log.textContent + "\n" + e_msg + "\n";
				log.scrollTop = log.scrollHeight;
				if (opt.error) opt.error(xhr, status, msg);
			});
		};
		// 今までの$.ajaxと同じく、success か error の後に complete を呼ぶ
		xhr.addEventListener('load', function(){
			if (200 <= xhr.status && xhr.status < 300 || xhr.status === 304) {
				var data = xhr.responseText;
				var ok   = true;
				if (opt.dataType === 'json') {
					try { data = JSON.parse(data) }
					catch(e) { ok = false; error('parsererror', e); }
				}
				if (ok) log_stop(function(){
					if (opt.success) opt.success(data);
				});
			} else	error('error', xhr.statusText);
			if (opt.complete) opt.complete();
		});
		xhr.addEventListener('error', function(){
			error('error', '');
			if (opt.complete) opt.complete();
		});
		xhr.send(fd);
	}

	/// ログ表示タイマー
	var log_timer;
	function log_start() {
		btn.disabled = true;
		log_timer = setInterval(log_load, interval);
	}
	function log_stop(func) {
		if (log_timer) clearInterval(log_timer);
		log_timer = 0;
		log_load(func);
		btn.disabled = false;
	}
	// 今までの.load()と同じく、innerHTMLに入れる。読めなくても func は呼ぶ
	function log_load(func) {
		var url = load_session + '&snum=' + snum;
		fetch(url).then(function(res){
			if (res.ok) return res.text().then(function(text){ log.innerHTML = text });
		}).catch(function(){}).then(function(){
			log.scrollTop = log.scrollHeight;
			if (typeof(func) === 'function') func();
		});
	}
  })});
};

//##############################################################################
// ■動画のサムネイル（docs/仕様/動画のサムネイル.md）
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●動画のサムネイルを作って送る
////////////////////////////////////////////////////////////////////////////////
// サーバーではコマンドを動かさず、ブラウザーで動画の1コマを切り出してPNGにする。
// 長い辺960pxのPNGを media/upload_video_thumbnail に送る。記事用とメディア管理の一覧用のJPEGは、サーバーがこれから作る
//	opt.url    : 動画のURL
//	opt.folder : メディア管理のフォルダ（posts/2026/）
//	opt.name   : 動画のファイル名
//	ret        : Promise。再生できない形式などで作れなければ reject
//
const VIDEO_POSTER_MAX = 960;	// 記事での既定の表示（480px）の2倍
const VIDEO_LOAD_TIMEOUT = 30000;

$$.make_video_thumbnail = function(opt) {
	let video;
	return load_video_frame(opt.url).then(function(v){
		video = v;
		return video_to_png(v, VIDEO_POSTER_MAX);
	}).then(function(blob){
		const fd = new FormData();
		fd.append('action', 'media/upload_video_thumbnail');
		fd.append('folder', opt.folder);
		fd.append('file',   opt.name);
		fd.append('poster', blob, 'poster.png');
		return fetch($$.myself + '?etc/ajax_dummy', { method: 'POST', body: fd, credentials: 'same-origin' });
	}).then(function(res){
		return res.json();
	}).then(function(data){
		if (data.ret !== 0) throw new Error('upload_video_thumbnail ret=' + data.ret);
	}).finally(function(){
		// 読み込みを止める
		if (video) { video.removeAttribute('src'); video.load(); }
	});
};

// 1秒の位置（1秒より短い動画は長さの半分）まで送り、そのコマを出せる状態にする
function load_video_frame(url) {
	return new Promise(function(resolve, reject){
		const video = document.createElement('video');
		video.muted   = true;
		video.preload = 'auto';
		video.playsInline = true;

		const timer = setTimeout(function(){ fail('timeout') }, VIDEO_LOAD_TIMEOUT);
		function fail(msg) {
			clearTimeout(timer);
			video.removeAttribute('src');
			video.load();
			reject(new Error(msg + ': ' + url));
		}
		video.addEventListener('error', function(){ fail('load error') }, { once: true });
		video.addEventListener('loadedmetadata', function(){
			const d = video.duration;
			video.currentTime = (isFinite(d) && d < 1) ? d/2 : 1;
		}, { once: true });
		video.addEventListener('seeked', function(){
			clearTimeout(timer);
			if (!video.videoWidth || !video.videoHeight) return fail('no video track');
			resolve(video);
		}, { once: true });
		video.src = url;
	});
}

// 長い辺を max 以下にしたPNG（JPEGにするのはサーバー。2回圧縮しないように）
function video_to_png(video, max) {
	let w = video.videoWidth;
	let h = video.videoHeight;
	if (max < w || max < h) {
		const r = max / Math.max(w, h);
		w = Math.max(1, Math.round(w*r));
		h = Math.max(1, Math.round(h*r));
	}
	const canvas = document.createElement('canvas');
	canvas.width  = w;
	canvas.height = h;
	canvas.getContext('2d').drawImage(video, 0, 0, w, h);
	return new Promise(function(resolve, reject){
		canvas.toBlob(function(blob){
			blob ? resolve(blob) : reject(new Error('toBlob'));
		}, 'image/png');
	});
}

////////////////////////////////////////////////////////////////////////////////
//●動画のサムネイルをまとめて作る
////////////////////////////////////////////////////////////////////////////////
// files : [ { folder:'posts/2026/', name:'clip.mp4' }, ... ]
// base  : メディア管理のURL（/pub/attach/）
// progress(i, file, err) : 1つ終わるたびに呼ぶ（err は失敗したとき）
// ret   : Promise。失敗した数で resolve する（1つ失敗しても続ける）
//
$$.make_video_thumbnails = function(files, base, progress) {
	let fail = 0;
	let p = Promise.resolve();
	files.forEach(function(file, i){
		p = p.then(function(){
			const url = base + (file.folder + file.name).split('/').map(encodeURIComponent).join('/');
			return $$.make_video_thumbnail({ url: url, folder: file.folder, name: file.name })
				.then(function(){ if (progress) progress(i, file) })
				.catch(function(err){ fail++; if (progress) progress(i, file, err) });
		});
	});
	return p.then(function(){ return fail });
};

////////////////////////////////////////////////////////////////////////////////
//●アップデート処理の画面：サムネイルの無い動画のサムネイルを作る
////////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	const box = document.getElementById('video-thumbnail');
	if (!box) return;
	const btn   = box.querySelector('button.make');
	const msg   = box.querySelector('.status');
	const files = Array.from( box.querySelectorAll('li') ).map(function(li){
		return { folder: li.getAttribute('data-folder'), name: li.getAttribute('data-name'), li: li };
	});

	function start() {
		if (btn) btn.disabled = true;
		$$.make_video_thumbnails(files, box.getAttribute('data-url'), function(i, file, err){
			file.li.classList.add(err ? 'error' : 'done');
			if (msg) msg.textContent = (i+1) + ' / ' + files.length;
		}).then(function(fail){
			const text = box.getAttribute(fail ? 'data-msg-fail' : 'data-msg-done') || '';
			if (msg) msg.textContent = text.replace('%n', fail);
		});
	}
	if (btn) btn.addEventListener('click', start);
	if (box.getAttribute('data-auto')) start();
});

//##############################################################################
// init
//##############################################################################
$$.init();

//##############################################################################
});
}
