//##############################################################################
// admin.js
//	管理画面でだけ使う処理。asys.js（jQuery）と adiary.js の後に読み込む
//	※公開画面のフレーム（_frame）でも、システムモード（デザイン編集など）のときと、
//	  ログイン中（記事のページのコメントの管理など）は読み込む
//##############################################################################
//[TAB=8]
'use strict';
{
// 公開画面の処理（adiary.js）。asys.js を読んだページでは、adiary は asys.js（$$）になる
const adiary_public = window.adiary_public;

//##############################################################################
// ■ダイアログのドラッグ（asys.js の $.fn.adiaryDraggable を置き換える）
//##############################################################################
// asys.js の版は、ダイアログの中のすべての mouseup で preventDefault する。
// そのため、ダイアログの中の数値入力の矢印を押して離しても、値が増え（減り）続ける
// （Chromeでは、離したときの既定の動作で繰り返しを止めるため）。
// asys.min.js は元のソースがリポジトリに無いので、ここで mouseup の preventDefault だけを除いた版にする。
// ダイアログは asys.js の初期化（DOMContentLoaded）より後に開くので、ここで置き換えれば足りる
$.fn.adiaryDraggable = function(opt) {
	let sx;
	let sy;
	let $obj;
	this.addClass('aui-draggable');

	this.on('mousedown', function(evt){
		$('iframe').css('pointer-events', 'none');
		const $tar = $(evt.target);
		$obj = $tar.hasClass('aui-draggable') ? $tar : $tar.parentsOne('.aui-draggable');

		if (opt) {
			const $o = $tar;
			if ($tar != $obj) $o.add($tar.parentsUntil('.aui-draggable'));
			if (opt.cancel &&  $o.filter(opt.cancel).length) return;
			if (opt.handle && !$o.filter(opt.handle).length) return;
		}
		const p = $obj.offset();
		sx = p.left - evt.pageX;
		sy = p.top  - evt.pageY;
		document.addEventListener('mousemove', move);
		evt.preventDefault();
		return;
	});

	this.on('mouseup', function(evt){
		$('iframe').css('pointer-events', 'auto');
		document.removeEventListener('mousemove', move);
	});

	function move(evt) {
		const x = sx + evt.pageX;
		const y = sy + evt.pageY;
		$obj.css({
			position:	'absolute',
			left:		x + 'px',
			top:		y + 'px'
		});
		evt.preventDefault();
	}
};

$(function(){
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
// テンプレートの <script-defer> と、デザインのテーマ選択（プレビューの css_init）から呼ぶ
for(const name of ['css_init', 'get_value_from_css', 'init_top_search', 'init_narrow_tag', 'word_highlight']) {
	$$[name] = function() {
		return adiary_public[name].apply(adiary_public, arguments);
	};
}

//##############################################################################
// ■extend jQuery
//##############################################################################
(function() {
	const init_orig = $.fn.init;
	$.fn.init = function(sel,cont) {
		if (typeof sel === "string" && sel.match(/<.*?[\W]on\w+\s*=/i))
			throw 'Security error by ' + $$.name + '.js : ' + sel;
		return  new init_orig(sel,cont);
	};
})();

////////////////////////////////////////////////////////////////////////////////
// Emulate jquery.cookie for dynatree
////////////////////////////////////////////////////////////////////////////////
(function(_ls) {
	const ls = _ls;
	$.cookie = function(key, val) {
		if (val === undefined) return ls.get(key);
		ls.set(key, val);
	}
	$.removeCookie = function(key) {
		ls.removeItem(key);
	}
})($$.Storage);

//##############################################################################
// ■dom extend
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●詳細情報ダイアログの表示
////////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	let prev;
	const self=this;
	this.$body.on('click', '.js-info[data-info], .js-info[data-url]', function(evt){

		if (evt.target == prev) return;	// 連続クリック防止
		prev = evt.target;

		const $obj = $(evt.target);
		const $div = $('<div>');
		const $div2= $('<div>');	// 直接 div にクラスを設定すると表示が崩れる

		$div.attr('title', $obj.data("title") || "Infomataion" );
		$div2.addClass($obj.data("class"));
		$div.empty();
		$div.append($div2);
		if ($obj.data('info')) {
			const text = self.tag_esc_br( $obj.data("info") );
			$div2.html( text );
			$div.adiaryDialog({ width: self.DialogWidth, close: close_func });
			return;
		}
		var url = $obj.data("url");
		$div2.load( url, function(){
			$div2.text( $div2.text().replace(/\n*$/, "\n\n") );
			$div.adiaryDialog({ width: self.DialogWidth, height: 320, close: close_func });
		});
	});
	function close_func() {
		prev = null;
	}
});

////////////////////////////////////////////////////////////////////////////////
//●画像・コメントのポップアップ
////////////////////////////////////////////////////////////////////////////////
$$.init( function(){
	const self = this;
	const func = function(evt){ self.popup(evt) }

	this.$body.on('mouseover', '.js-popup-img', {
		func: function($obj, $div) {
			const $img = $('<img>');
			$img.attr('src', $obj.data('img-url'));
			$div.empty();
			$div.attr('id', 'popup-image');
			$div.append( img );
		}
	}, func);
	$('.js-popup-img').removeAttr('title');	// remove title attr popup

	this.$body.on('mouseover', '.js-popup-com', {
		func: function($obj, $div){
			var num = $obj.data('target');
			if (num == '' || num == 0) return $div.empty();

			var $com = $secure('#c' + num);
			if (!$com.length) return $div.empty();

			$div.attr('id', 'popup-com');
			$div.html( $com.html() );
		}
	}, func);
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
$$._load_picker = false;
$$.dom_init( function($R){
	const $cp = $R.findx('input.color-picker');
	if (!$cp.length) return;

	$cp.each(function(i,dom){
		const $obj = $(dom);
		const $box = $('<span>').addClass('colorbox');
		$obj.before($box);
		const color = $obj.val();
		if (color.match(/^#[\dA-Fa-f]{6}$/))
			$box.css('background-color', color);
	});

	// color pickerのロード
	var dir = this.ScriptDir + 'colorpicker/';
	this.prepend_css(dir + 'css/colorpicker.css');
	this.load_script(dir + "colorpicker.js", function(){

		$cp.each(function(idx,dom){
			var $obj = $(dom);
			$obj.ColorPicker({
				onSubmit: function(hsb, hex, rgb, _el) {
					var $el = $(_el);
					$el.val('#' + hex);
					$el.ColorPickerHide();
					var $prev = $el.prev();
					if (! $prev.hasClass('colorbox')) return;
					$prev.css('background-color', '#' + hex);
					$obj.change();
				},
				onChange: function(hsb, hex, rgb) {
					var $prev = $obj.prev();
					if (! $prev.hasClass('colorbox')) return;
					$prev.css('background-color', '#' + hex);
					var func = $obj.data('onChange');
					if (func) func(hsb, hex, rgb);
				}
			});
			$obj.ColorPickerSetColor( $obj.val() );
		});
		$cp.on('keyup', function(evt){
			$(evt.target).ColorPickerSetColor(evt.target.value);
		});
		$cp.on('keydown', function(evt){
			if (evt.keyCode != 27) return;
			$(evt.target).ColorPickerHide();
		});

		// if loaded jQuery UI, color picker draggable
		$R.rootfind('.colorpicker').adiaryDraggable({
			cancel: ".colorpicker_color, .colorpicker_hue, .colorpicker_submit, input, span"
		})
	});
});

////////////////////////////////////////////////////////////////////////////////
//●【スマホ】DnDエミュレーション登録
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	$R.findx('.treebox').dndEmulation();
});

//##############################################################################
// ■スケルトン用ルーチン
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// ●タグ一覧のロード
////////////////////////////////////////////////////////////////////////////////
$$.load_tags_list = function(id, callback) {
	const $sel     = $(id);		// セレクトボックス
	const _default = $sel.data('default') || '';

	$.getJSON( $sel.data('url'), function(data){
		if (callback) callback(data);
		var r_func = function(ary, head, tab) {
			for(var i=0; i<ary.length; i++) {
				var name= ary[i].title;
				var val = head + name;
				var opt = $('<option>').attr('value', val);
				//opt.css('padding-left', tab*8);	// Fx以外で効かないので以下で代用
				opt.html('&emsp;'.repeat(tab) + val );
				if ( val == _default ) opt.prop('selected', true);
				$sel.append(opt);
				if (ary[i].children)
					r_func( ary[i].children, head+name+'::', tab+1 );
			}
		};
		r_func(data, '', 0);
		$sel.change();
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●コンテンツ一覧のロード
////////////////////////////////////////////////////////////////////////////////
// 読み込みの jqXHR を返す（option を足して change した後に done、always が呼ばれる）
$$.load_contents_list = function(id) {
	var obj = $(id);
	return $.getJSON( obj.data('url'), function(data){
		var _default  = obj.data('default');
		var this_pkey = obj.data('this-pkey');

		var r_func = function(ary, tab) {
			for(var i=0; i<ary.length; i++) {
				var pkey  = ary[i].key;
				if (pkey == this_pkey) continue;
				var title = ary[i].title;
				if (title.length > 20)
					title = title.substr(0,20) + '...';

				var opt = $('<option>').attr('value', pkey);
				//opt.css('padding-left', tab*8);	// Fx以外で効かないので以下で代用
				opt.html('&emsp;'.repeat(tab) + title );
				opt.data('link_key', ary[i].link_key);
				if ( pkey == _default ) opt.prop('selected', true);
				obj.append(opt);
				if (ary[i].children)
					r_func( ary[i].children, tab+1 );
			}
		};
		r_func(data, 0);
		obj.change();
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
$$.session = function(btn, opt){
  const self=this;
  $(btn).click( function(evt){
	var $btn = $(evt.target);
	var myself = opt.myself || self.myself;
	var $log   = opt.$log   || $btn.rootfind($btn.data('log-target') || '#session-log');

	var load_session = myself + '?etc/load_session';
	var interval = opt.interval || $log.data('interval') || 300;
	var snum;

	if (opt.load_log) $log = opt.load_log(evt);
	$log.showDelay();
	if (opt.init) opt.init(evt);

	// セッション初期化
	$.post( load_session, {
			action: 'etc/init_session'
		}, function(data) {
			var reg = data.match(/snum=(\d+)/);
			if (reg) {
				snum = reg[1];
				ajax_session();
				return;
			}
			console.warn(error);
		}, 'text'
	);

	// Ajaxセッション開始
	function ajax_session(){
		log_start();
		var fd;
		if (opt.load_formdata) fd = opt.load_formdata($btn);
				else   fd = new FormData( opt.form );
		var ctype;
		if (typeof(fd) == 'string') fd += '&snum=' + snum;
		else {
			fd.append('snum', snum);
			ctype = false;
		}
		$.ajax(myself + '?etc/ajax_dummy', {
			method: 'POST',
			contentType: ctype,
			processData: false,
			data: fd,
			dataType: opt.dataType || 'text',
			error: function(jqXHR, status, msg) {
				const e_msg = '[' + $$.name + '.session()] Ajax fail: ' + msg;
				console.warn(e_msg);
				log_stop(function(){
					$log.text($log.text() + "\n" + e_msg + "\n");
					$log.scrollTop( $log.prop('scrollHeight') );
					if (opt.error) opt.error(jqXHR, status, msg);
				});
			},
			success: function(data) {
				log_stop(function(){
					if (opt.success) opt.success(data);
				});
			},
			complete:	opt.complete,
			xhr:		opt.xhr
		});
	}

	/// ログ表示タイマー
	var log_timer;
	function log_start( snum ) {
		$btn.prop('disabled', true);
		$log.data('snum', snum);
		log_timer = setInterval(log_load, interval);
	}
	function log_stop(func) {
		if (log_timer) clearInterval(log_timer);
		log_timer = 0;
		log_load(func);
		$btn.prop('disabled', false);
	}
	function log_load(func) {
		var url = load_session + '&snum=' + snum;
		$log.load(url, function(data){
			$log.scrollTop( $log.prop('scrollHeight') );
			if (func) func();
		});
	}
  });
};

////////////////////////////////////////////////////////////////////////////////
// CSS append
////////////////////////////////////////////////////////////////////////////////
$$.prepend_css = function(file) {
	const $link = $("<link>")
	$link.attr({
		rel: "stylesheet",
		href: file
	});
	this.$head.prepend($link);
	return $link;
}

//##############################################################################
// ■動画のサムネイル（docs/仕様/動画のサムネイル.md）
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
//●動画のサムネイルを作って送る
////////////////////////////////////////////////////////////////////////////////
// サーバーではコマンドを動かさず、ブラウザーで動画の1コマを切り出してPNGにする。
// 長い辺960pxのPNGを media/upload_video_thumbnail に送る。記事用と画像アルバム用のJPEGは、サーバーがこれから作る
//	opt.url    : 動画のURL
//	opt.folder : 画像アルバムのフォルダ（posts/2026/）
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
// base  : 画像アルバムのURL（/pub/attachments/）
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
	const $box = $('#video-thumbnail');
	if (!$box.length) return;
	const $btn  = $box.find('button.make');
	const $msg  = $box.find('.status');
	const files = $box.find('li').map(function(i, dom){
		const $li = $(dom);
		// data() は数字だけの名前を数値にするので attr() で読む
		return { folder: $li.attr('data-folder'), name: $li.attr('data-name'), $li: $li };
	}).get();

	function start() {
		$btn.prop('disabled', true);
		$$.make_video_thumbnails(files, $box.data('url'), function(i, file, err){
			file.$li.addClass(err ? 'error' : 'done');
			$msg.text((i+1) + ' / ' + files.length);
		}).then(function(fail){
			$msg.text( $box.data(fail ? 'msg-fail' : 'msg-done').replace('%n', fail) );
		});
	}
	$btn.on('click', start);
	if ($box.data('auto')) start();
});

//##############################################################################
// init
//##############################################################################
$$.init();

//##############################################################################
});
}
