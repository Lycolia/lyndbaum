//##############################################################################
// 記事編集画面用JavaScript
//							(C)2014 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';
//### global variables #######################################################
var insert_image;	// global function for album.js

$(function(){
//##############################################################################
const $tagsel = $secure('#tag-select');
const $upsel  = $secure('#upnode-select');
const $edit   = $('#editarea');
const CSRF_key = $('#csrf-key').val();

// タグ一覧 [{ name: "親::子", qt: 使用数 }, ...]
const all_tags = [];
adiary.load_tags_list($tagsel, function(data){
	const r_func = function(ary, head) {
		for(var i=0; i<ary.length; i++) {
			const name = head + ary[i].title;
			all_tags.push({ name: name, lc: name.toLowerCase(), qt: ary[i].qt || 0 });
			if (ary[i].children) r_func( ary[i].children, name + '::' );
		}
	};
	r_func(data, '');
});
adiary.load_contents_list($upsel);

//##############################################################################
// ■下書きを開く
//##############################################################################
{
	var $draft = $('#select-draft');
	$('#open-draft').click(function(){
		var pkey = $draft.val();
		window.location = adiary.myself2 + '0' + pkey + '?edit';
	});
	$('#open-template').click(function(){
		var pkey = $draft.val();
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
	const $tagdel = $('<span>').addClass('ui-icon ui-icon-close');
	$tagdel.click(function(evt){
		var obj = $(evt.target);
		obj.parent().remove();
	});
	$("#edit-tags span.tag").append( $tagdel.clone(true) );

	//----------------------------------------------------------------------
	// ●タグの追加
	//----------------------------------------------------------------------
	function tag_append(text) {
		if (text=="") return;

		var $tags = $('#tags');
		var ch = $tags.children();
		for(var i=0; i<ch.length; i++) {
			if ($(ch[i]).text() == text) return;
		}
		// append
		var $tag = $('<span>').addClass('tag').html( adiary.tag_esc_amp(text) );
		var $inp = $('<input>').attr({
			type: 'hidden',
			name: 'tag_ary',
			value: text
		});
		$tag.append( $inp, $tagdel.clone(true) );
		$tags.append( $tag );
	}

	//--------------------------------------------------------------------------------
	// ●タグ追加ダイアログの表示
	//--------------------------------------------------------------------------------
	const $addtag  = $secure('#edit-add-tag');
	const $tagform = $secure('#tag-select-form').detach();
	const $inp     = $tagform.find('#input-new-tag');
	const $cands   = $tagform.find('#tag-candidates');
	const max_cands = 20;
	var $div;

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
		$cands.empty();
		const text  = $inp.val().trim();
		const words = text.toLowerCase().split(/\s+/).filter(function(w){ return w != '' });
		if (!words.length) return;

		const added = {};
		$('#tags input[name="tag_ary"]').each(function(i, obj){ added[obj.value] = true; });

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
			const $li = $('<li>').attr('data-tag', hits[i].name);
			$li.append( $('<span>').text(hits[i].name) );
			$li.append( $('<span>').addClass('qt').text(hits[i].qt) );
			$cands.append($li);
		}
		// 一致するタグがなければ新規タグとして追加
		const exists = all_tags.some(function(t){ return t.name == text });
		if (!exists && !added[text] && text.indexOf(',') < 0) {
			const msg = $('#new-tag-create').text().replace('%t', text);
			$cands.append( $('<li>').addClass('new-tag').attr('data-tag', text).text(msg) );
		}
		$cands.children().first().addClass('selected');
	}

	function move_selected(dir) {
		const $li  = $cands.children();
		if (!$li.length) return;
		const cur  = $li.index( $li.filter('.selected') );
		const next = (cur + dir + $li.length) % $li.length;
		$li.removeClass('selected');
		const $next = $li.eq(next).addClass('selected');
		$next[0].scrollIntoView({ block: 'nearest' });
	}

	// 追加したらダイアログは閉じずに次の入力へ
	function append_and_continue(tag) {
		if (tag == '' || tag.indexOf(',') >= 0) return;
		tag_append( tag );
		$inp.val('');
		update_candidates();
		$inp.focus();
	}

	function append_selected() {
		const $sel = $cands.children('.selected');
		if ($sel.length) return append_and_continue( $sel.attr('data-tag') );
		append_and_continue( $inp.val().trim() );
	}

	$inp.on('input', update_candidates);
	$inp.on('keydown', function(evt){
		// IME変換中のキー操作は無視
		if (evt.originalEvent.isComposing || evt.keyCode == 229) return;
		if (evt.keyCode == 38) { move_selected(-1); return false; }	// ↑
		if (evt.keyCode == 40) { move_selected( 1); return false; }	// ↓
		if (evt.keyCode != 13) return;
		append_selected();
		return false;
	});
	$cands.on('click', 'li', function(evt){
		append_and_continue( $(evt.currentTarget).attr('data-tag') );
	});

	$addtag.click( function(){
		$div = $('<div>').append( $tagform );

		// ボタンの設定
		var buttons = {};
		buttons[ $('#new-tag-append').text() ] = append_selected;
		buttons[ $('#new-tag-close').text() ] = function(){
			$div.adiaryDialog( 'close' );
		};
		$div.adiaryDialog({
			modal:	true,
			width:	Math.min(420, $(window).width() - 20),
			minHeight: 200,
			title:   $addtag.data('title'),
			buttons: buttons,
			open: function(){
				$inp.focus();
			},
			beforeClose: function(){
				$tagsel.val('');
				$inp.val('');
				$cands.empty();
				$tagform.detach();
			}
		});
	});

	//--------------------------------------------------------------------------------
	// ●タグ選択フォームの処理
	//--------------------------------------------------------------------------------
	$tagsel.change(function(){
		if ($(':selected', $tagsel).data('new')) return;
		tag_append( $tagsel.val() );
		$tagsel.val('');
		update_candidates();
	});
}

//##############################################################################
// ■サムネイル（OGP画像）の選択
//##############################################################################
// name="ogp" の入力欄が実体。空なら記事の最初の画像（サーバー側で自動選択）
{
	const $picker = $('#thumbnail-picker');
	const $ogp    = $('#ogp-input');
	const imgdir  = $('#image-dir').text();		// 画像ディレクトリ（相対）
	const img_url = adiary.Basepath + imgdir;
	const img_ext = /\.(?:jpe?g|png|gif|webp|apng|bmp|tiff?|ico)$/i;

	// [image:S:folder/:file:caption] 記法と、画像ディレクトリ内を指すURLを出現順に拾う
	const dir_re = imgdir.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const img_re = new RegExp('\\[image:[^:\\]]*:([^:\\]]*/):([^:\\]]+)|' + dir_re + '([^\\s"\'<>()\\]]+)', 'g');

	// 画像ディレクトリからの相対パスの一覧を返す（サムネイルは元画像に戻す）
	function find_images(text) {
		const list = [];
		img_re.lastIndex = 0;
		let m;
		while((m = img_re.exec(text))) {
			let path = (m[3] !== undefined) ? m[3] : m[1] + m[2];
			path = path.replace(/(^|\/)\.thumbnail\/(.+)\.jpg$/, '$1$2');
			if (img_ext.test(path) && list.indexOf(path) < 0) list.push(path);
		}
		return list;
	}

	// 入力欄の値を画像パスに正規化（記法で入力された場合にも対応）
	function current_value() {
		const val = $ogp.val().trim();
		if (val.indexOf(':') < 0) return val;
		return find_images(val)[0] || val;
	}

	function thumb_url(path) {
		const x = path.lastIndexOf('/');
		const enc = function(s){ return s.split('/').map(encodeURIComponent).join('/') };
		return img_url + enc(path.substr(0, x+1) + '.thumbnail/' + path.substr(x+1) + '.jpg');
	}
	function full_url(path) {
		return img_url + path.split('/').map(encodeURIComponent).join('/');
	}

	function make_item(path, label, value, selected) {
		const $li = $('<li>').attr('data-value', value).attr('title', label || path);
		if (selected) $li.addClass('selected');
		if (path) {
			const $img = $('<img>').attr({ src: thumb_url(path), alt: '', loading: 'lazy' });
			$img.one('error', function(){ $img.attr('src', full_url(path)) });
			$li.append($img);
		}
		if (label) $li.append( $('<span>').addClass('label').text(label) );
		return $li;
	}

	let images = [];
	function render() {
		const cur = current_value();
		$picker.empty();

		// 自動（記事の最初の画像）
		const auto_label = $('#thumbnail-auto').text();
		const $auto = make_item(images[0], auto_label, '', cur == '');
		$auto.attr('title', auto_label + ' : ' + (images.length ? $('#thumbnail-auto-help').text() : $('#thumbnail-none').text()));
		$picker.append($auto);

		images.forEach(function(path){
			$picker.append( make_item(path, '', path, cur == path) );
		});
		// 記事にない画像が指定されている
		if (cur != '' && images.indexOf(cur) < 0) {
			$picker.append( make_item(cur.indexOf(':') < 0 ? cur : '', $('#thumbnail-direct-label').text(), cur, true) );
		}
	}

	$picker.on('click', 'li', function(evt){
		$ogp.val( $(evt.currentTarget).attr('data-value') );
		render();
	});
	$ogp.on('input', render);

	// 記事本文の変更を反映（アルバムからの挿入等はinputイベントが来ないので定期確認）
	let last_text;
	function rescan() {
		const text = $edit.val();
		if (text === last_text) return;
		last_text = text;
		const list = find_images(text);
		if (list.join("\n") === images.join("\n")) return;
		images = list;
		render();
	}
	rescan();
	render();
	setInterval(rescan, 1500);

	// 保存済みの値が記事の最初の画像と同じなら「自動」扱いにする
	if (images.length && current_value() == images[0]) {
		$ogp.val('');
		render();
	}
}

//##############################################################################
// ■更新履歴
//##############################################################################
{
	const $btn    = $secure('#edit-revision');
	const $dialog = $secure('#revision-dialog').detach();
	const $list   = $dialog.find('#revision-list');
	const $title  = $dialog.find('#revision-title');
	const $body   = $dialog.find('#revision-body');
	const max_cells = 4000000;	// 差分計算の上限（行数の積）
	let cur_rev;			// 表示中の版

	function ajax_revision(data, callback) {
		data.action = 'ajax_revision';
		data.csrf_check_key = CSRF_key;
		$.ajax({
			type: 'POST',
			url:  adiary.myself + '?etc/ajax_dummy',
			dataType: 'json',
			data: data,
			success: callback,
			error: function(){ callback(null) }
		});
	}

	function format_tm(tm) {
		const d = new Date(tm * 1000);
		const z = function(n){ return (n < 10 ? '0' : '') + n };
		return d.getFullYear() + '/' + z(d.getMonth()+1) + '/' + z(d.getDate())
			+ ' ' + z(d.getHours()) + ':' + z(d.getMinutes());
	}

	//--------------------------------------------------------------------------
	// ●行単位の差分（a → b）。大きすぎる場合は null
	//--------------------------------------------------------------------------
	function line_diff(a, b) {
		// 前後の共通部分は比較しない
		let s = 0;
		while(s < a.length && s < b.length && a[s] === b[s]) s++;
		let ea = a.length, eb = b.length;
		while(ea > s && eb > s && a[ea-1] === b[eb-1]) { ea--; eb--; }
		const A = a.slice(s, ea), B = b.slice(s, eb);
		const n = A.length, m = B.length, w = m + 1;
		if (n * m > max_cells) return null;

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
	function render_diff(diff) {
		const ctx = 2;
		const show = new Array(diff.length).fill(false);
		diff.forEach(function(d, i){
			if (d[0] == ' ') return;
			for(let k=Math.max(0, i-ctx); k<=Math.min(diff.length-1, i+ctx); k++) show[k] = true;
		});
		$body.empty();
		let skipped = false;
		diff.forEach(function(d, i){
			if (!show[i]) { skipped = true; return; }
			if (skipped) { $body.append( $('<span>').addClass('rev-skip').text("…") ); skipped = false; }
			const cls = d[0] == '-' ? 'rev-del' : d[0] == '+' ? 'rev-add' : 'rev-ctx';
			$body.append( $('<span>').addClass(cls).text(d[0] + ' ' + d[1]) );
		});
		if (skipped) $body.append( $('<span>').addClass('rev-skip').text("…") );
	}

	function show_revision() {
		$title.empty();
		$body.empty().removeClass('rev-full');
		if (!cur_rev) {
			$body.text( $('#rev-select').text() );
			return;
		}
		$title.html( cur_rev.title );

		const mode = $dialog.find('input[name="rev_mode"]:checked').val();
		const text = cur_rev.text;
		if (mode == 'diff') {
			const now  = $edit.val().replace(/\r\n?/g, "\n");
			if (now === text) { $body.text( $('#rev-same').text() ); return; }
			const diff = line_diff(text.split("\n"), now.split("\n"));
			if (diff) return render_diff(diff);
			$title.append( $('<div>').addClass('rev-note').text( $('#rev-too-large').text() ) );
		}
		$body.addClass('rev-full').text(text);
	}
	$dialog.find('input[name="rev_mode"]').on('change', show_revision);

	//--------------------------------------------------------------------------
	// ●一覧
	//--------------------------------------------------------------------------
	$list.on('click', 'li[data-pkey]', function(evt){
		const $li = $(evt.currentTarget);
		$list.children().removeClass('selected');
		$li.addClass('selected');
		ajax_revision({ rev: $li.attr('data-pkey') }, function(data){
			if (!data) return;
			data.text = data.text.replace(/\r\n?/g, "\n");
			cur_rev = data;
			show_revision();
		});
	});

	function load_list() {
		$list.empty();
		cur_rev = undefined;
		show_revision();
		ajax_revision({ pkey: $('#edit-pkey').val() }, function(data){
			if (!data || !data.length) {
				$list.append( $('<li>').addClass('rev-empty').text( $('#rev-empty').text() ) );
				return;
			}
			const chars = $('#rev-chars').text();
			data.forEach(function(r){
				const $li = $('<li>').attr('data-pkey', r.pkey);
				$li.append( $('<span>').addClass('rev-tm').text( format_tm(r.update_tm || r.tm) ) );
				$li.append( $('<span>').addClass('rev-len').text( chars.replace('%n', r.length.toLocaleString()) ) );
				$li.append( $('<div>').addClass('rev-title').html( r.title ) );
				$list.append($li);
			});
		});
	}

	//--------------------------------------------------------------------------
	// ●ダイアログ
	//--------------------------------------------------------------------------
	$btn.click(function(){
		const $div = $('<div>').append($dialog);
		const buttons = {};
		buttons[ $('#rev-load').text() ] = function(){
			if (!cur_rev) return;
			const msg = $('#rev-confirm').text().replace('%t', format_tm(cur_rev.update_tm || cur_rev.tm));
			adiary.confirm(msg, function(ok){
				if (!ok) return;
				$edit.val(cur_rev.text).trigger('input');
				$div.adiaryDialog('close');
			});
		};
		buttons[ $('#new-tag-close').text() ] = function(){
			$div.adiaryDialog('close');
		};
		$div.adiaryDialog({
			modal:	true,
			width:	Math.min(960, $(window).width() - 20),
			minHeight: 300,
			title:	$btn.data('title'),
			buttons: buttons,
			beforeClose: function(){ $dialog.detach(); }
		});
		load_list();
	});
}

//##############################################################################
// ■公開状態の変更
//##############################################################################
{
	var $echk = $('#enable-chk');
	var $dchk = $('#draft-chk');
	$echk.change( echk_change );
	$dchk.change( echk_change );
	echk_change();

	function echk_change() {
		if ($dchk.prop('checked')) {	// 下書き
			$('.save-btn-title').text( $dchk.data('on') );
			return;
		}
		if ($echk.prop('checked'))
			$('.save-btn-title').text( $echk.data('on') );
		else
			$('.save-btn-title').text( $echk.data('off') );
	}
}

//##############################################################################
// ■upnodeの変更 / link_keyの設定
//##############################################################################
{
	const $upsel = $('#upnode-select');
	const $lkey  = $('#link-key');

	$upsel.change(function(){
		if (! $lkey.data('suggest')) return;	// 機能がoff
		var val = $lkey.val();
		if (val != '' && val != $lkey.data('set')) return;

		var $opt = $upsel.children(':selected');
		if (!$opt.length) return;

		var set = $opt.data('link_key');
		if (set == undefined) return;
		if (set.substr(-1) != '/') set += '/';
		$lkey.val( set );
		$lkey.data('set', set);
	});
}

//##############################################################################
// ■編集ロック機能
//##############################################################################
{
//##############################################################################
function edit(pkey) {
	this.pkey     = pkey;
	this.sid      = '';
	this.interval = parseInt( $('#edit-lock-interval').text() );
	this.timer    = null;
	this.editing  = false;

	if (!pkey || this.interval<10) this.interval = 0;
	this.init();
	this.start();
};

//------------------------------------------------------------------------------
// ●初期化
//------------------------------------------------------------------------------
edit.prototype.init = function() {
	let self = this;

	// sid生成
	let d = new Date();
	if (window.location.hash) {
		this.sid = window.location.hash.substr(1).replace('%20', ' ');
	} else {
		this.sid = d.getFullYear()
		+ '/' + ('00'+(d.getMonth()+1)).substr(-2)
		+ '/' + ('00' + d.getDate()   ).substr(-2)
		+ ' ' + ('00' + d.getHours()  ).substr(-2)
		+ ':' + ('00' + d.getMinutes()).substr(-2)
		+ ':' + ('00' + d.getSeconds()).substr(-2);
		if (this.interval)
			window.location.hash = this.sid;
	}

	// ロックの強制確認ボタン
	$('#force-lock-check').click(function(){
		self.stop_timer();
		self.lock();
		self.start_timer();
	});
}

//------------------------------------------------------------------------------
// ●編集開始
//------------------------------------------------------------------------------
edit.prototype.start = function() {
	if (!this.interval) return this.enable();

	// 他にロックをかけている人は居ないかチェック
	let self = this;
	this.lock(function(data) {
		// 他の編集中の人が居る
		if (data && data.length) self.open_dialog(data);
	});
}

//------------------------------------------------------------------------------
// ●ロックをかける
//------------------------------------------------------------------------------
edit.prototype.lock = function(callback) {
	let self = this;
	this.ajax_lock({
		force:    self.editing || 0,
		callback: function(h) {
			if (h.return != 0) return;	 // internal error
			self.view_lockers(h.data);

			let data = h.data;
			if (!self.editing && (!data || !data.length)) {
				self.enable();
				self.start_timer();
			}
			if (callback) return callback(data);
		}
	})
}

//------------------------------------------------------------------------------
// ●編集中の確認タイマーと手動確認
//------------------------------------------------------------------------------
edit.prototype.start_timer = function(callback) {
	if (this.timer || !this.interval) return;

	let self = this;
	this.timer = setInterval(function(){
		self.lock()
	}, this.interval*1000);
}

edit.prototype.stop_timer = function() {
	if (!this.timer) return;
	clearInterval(this.timer);
	this.timer = null;
}

//------------------------------------------------------------------------------
// ●編集するか確認
//------------------------------------------------------------------------------
edit.prototype.open_dialog = function(data) {
	let self = this;

	// 編集するか確認
	let html = '<ul>'
	for(var i in data) {
		html += '<li>' + data[i].id + ' (' + data[i].sid + ')' + '</li>';
	}
	html+='</ul>';
	adiary.confirm({
		id: '#edit-confirm',
		hash: { u: html }
	}, function(flag){
		if (flag) {
			self.enable();
			self.lock();
			self.start_timer();
			return;
		}

		self.disable();
		self.start_timer();
	});
}

//------------------------------------------------------------------------------
// ●編集できる状態にする
//------------------------------------------------------------------------------
edit.prototype.enable = function() {
	this.editing = true;

	$('#edit').find('form, button:not(.no-disable), input, select').prop('disabled', false);
	$('#edit').find('textarea').prop('readonly', false);
	$('#edit').find('.fileup').prop('disabled', false);

	// ページを離れるときにunlock
	if (this.interval) {
		let self = this;
		$(window).on('unload', function(){
			self.ajax_unlock();
		});
	}
}

//------------------------------------------------------------------------------
// ●編集できない状態にする
//------------------------------------------------------------------------------
edit.prototype.disable = function() {
	this.editing = false;

	$('#edit').find('form, button:not(.no-disable), input, select').prop('disabled', true);
	$('#edit').find('textarea').prop('readonly', true);
	$('#edit').find('.fileup').prop('disabled', true);
}

//------------------------------------------------------------------------------
// ●ロック状態を表示する
//------------------------------------------------------------------------------
const $lock_notice = $('#edit-lock-notice');
const $lockers_ul  = $('#edit-lockers');
edit.prototype.view_lockers = function(data) {
	$lockers_ul.empty();

	if (data && data.length)
		$lock_notice.showDelay();
	else {
		$lock_notice.hideDelay();
	}
	// 編集中の人々を表示
	for(var i in data) {
		var li = $('<li>').text(data[i].id + ' (' + data[i].sid + ')');
		$lockers_ul.append(li);
	}
	var d = new Date();
	$('#check-time').text(
		('00' + d.getHours()  ).substr(-2)
	+ ':' + ('00' + d.getMinutes()).substr(-2)
	+ ':' + ('00' + d.getSeconds()).substr(-2)
	);
}

//------------------------------------------------------------------------------
// ●ロックAjax処理
//------------------------------------------------------------------------------
edit.prototype.ajax_unlock = function(opt) {
	if (!opt) opt={};
	opt.unlock = 1;
	opt.async  = false;
	return this.ajax_lock(opt);
}
edit.prototype.ajax_lock = function(opt) {
	opt.action = opt.action || 'ajax_lock';

	var param = {
		type: 'POST',
		url: adiary.myself + '?etc/ajax_dummy',
		dataType: 'json',
		data: {
			action: opt.action,
			csrf_check_key: CSRF_key,
			pkey:   opt.pkey || this.pkey,
			sid:    opt.sid  || this.sid,
			unlock: opt.unlock ? 1 : 0,
			force:  opt.force  ? 1 : 0
		}
	};
	if (opt.async !== undefined) param.async = opt.async;

	let d = param.data;
	console.log((new Date()).toLocaleTimeString(), opt.unlock ? 'ajax_unlock' : d.action, d.pkey, d.sid, "force=" + d.force);

	if (opt.callback) param.success = opt.callback;
	$.ajax( param );
}
//##############################################################################
	const e = new edit( $('#edit-pkey').val() );
}

//##############################################################################
// ■ファイルアップロード機能
//##############################################################################
var $upform   = $('#upload-form').detach();
var $file_btn = $upform.find('#file-btn');
var $file_div = $upform.find('#file-btn-div');
var $fileup   = $secure('#edit-file-upload');
//------------------------------------------------------------------------------
// ●アップロードダイアログ
//------------------------------------------------------------------------------
$fileup.click(function(){
	update_files_view([]);
	open_upload_dialog();
});
function open_upload_dialog(files) {
	var div = $('<div>').append( $upform );
	var cnt = 0;

	if (files) {
		$file_div.hide();
		update_files_view(files);
	} else {
		$file_div.show();
	}

	// 設定済サムネイルサイズをロードさせるためのidの細工
	var thsize = $upform.find('select.thumbnail-size');
	if (thsize.length==1) thsize.attr('id', 'thumbnail-size');

	// ボタンの設定
	var buttons = {};
	var ok_func = buttons['Upload'] = function(){
		if (!files && !$file_btn.val()) return;	// no selected

		div.parent().find('.ui-button').prop("disabled", true);

		ajax_upload( $upform[0], files, {
			callback: function(data, folder){
				upload_files_insert(data, {
					folder:		folder,
					thumbnail:	$('#paste-thumbnail').val() == '0' ? false : true,
					caption:	$('#paste-caption').val(),
					exif:		$('#paste-to-exif').prop('checked'),
					class:		$('#paste-class').val()
				});
			},
			complete: function(){
				$upform.detach();
				div.adiaryDialog( 'close' );
				div.remove();
			}
		});

		$file_btn.val('');
	};
	buttons[ adiary.msg('cancel') ] = function(){
		$upform.detach();
		div.adiaryDialog( 'close' );
		div.remove();
	};

	div.adiaryDialog({
		modal: true,
		width:  adiary.DialogWidth,
		// minHeight: 200,
		title:   $fileup.data('title'),
		buttons: buttons
	});
}
//------------------------------------------------------------------------------
// ●選択ファイル一覧表示 / ファイル選択後の処理
//------------------------------------------------------------------------------
function update_files_view(files) {
	var $div = $upform.find('#dnd-files');
	$div.empty();
	for(var i=0; i<files.length; i++) {
		if (!files[i]) continue;
		var fs  = adiary.size_format(files[i].size);
		var div = $('<div>').text(
			files[i].name + ' (' + fs + ')'
		);
		$div.append(div);
	}
}

$file_btn.on('change', function() {
	var files = $file_btn[0].files;
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
			thumbnail: opt.thumbnail
		});
	}

	insert_image({
		caption: opt.caption,
		class:   opt.class,
		files: files
	});
}

//------------------------------------------------------------------------------
// ●アップロード処理
//------------------------------------------------------------------------------
function ajax_upload( form_dom, files, option ) {
	var date = $('#edit-date').val().toString() || '';
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
	var folder = $fileup.data('folder');
	if (folder == '') folder='adiary/%y/';
	folder = folder.replace('%y', year).replace('%m', mon).replace(/^\/+/, '');

	// FormData生成
	var fd = new FormData( form_dom );
	if (!$file_btn.val()) fd.delete('_file_btn');
	fd.append('csrf_check_key', $('#csrf-key').val());
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
	var $prog  = $('#progress');
	var $label = $prog.find('.label').text('');
	$prog.show();
	$prog.adiaryProgressbar({
		value: 0,
		change: function(value) {
			$label.text( value + "%" );
		},
		complete: function() {
			$label.text( "Upload complete!" );
		}
	});

	// submit処理
	$.ajax(adiary.myself + '?etc/ajax_dummy', {
		method: 'POST',
		contentType: false,
		processData: false,
		data: fd,
		dataType: 'json',
		error: function(xhr) {
			console.log('[ajax_upload()] http post fail');
			adiary.show_error('#msg-upload-error');
		},
		success: function(data) {
			console.log('[ajax_upload()] http post success');
			if (option.callback) option.callback(data, folder);
		},
		complete: function(xhr, text) {
			$prog.hide();
			if (option.complete) option.complete(xhr, text);
		},
		xhr: function() {
			var XHR = $.ajaxSettings.xhr();
			XHR.upload.addEventListener('progress', function(e){
				var par = Math.floor(e.loaded*100/e.total + 0.5);
				$prog.adiaryProgressbar({ value: par });
			});
			return XHR;
		}
	});
}
//------------------------------------------------------------------------------
// ●ドラッグ＆ドロップ
//------------------------------------------------------------------------------
$edit.on('dragover', function(evt) {
	return false;
});
$edit.on("drop", function(evt) {
	evt.stopPropagation();
	evt.preventDefault();

	if ($edit.prop('readonly')) return;
	if (!evt.originalEvent.dataTransfer) return;

	var files = evt.originalEvent.dataTransfer.files;
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
	let date = $('#edit-date').val().toString() || '';
	let year;
	let month;
	if (date.match(/^\d\d\d\d[\-\/]\d\d/)) {
		year = date.substr(0,4);
		month  = date.substr(5,2);
	} else {
		let d = new Date();
		year = d.getFullYear();
		month  = (101 + d.getMonth()).toString().substr(1);
	};
	const folder = `adiary/${year}/${month}/`;

	const fd = new FormData();

	fd.append('paste', 1); // 謎パラメタ
	fd.append('size', 320); // TODO: サムネサイズ：どっかで既定値を設定したい
	fd.append('csrf_check_key', undefined); // 使われていないゴミ
	fd.append('action', 'etc/ajax_upload');
	fd.append('folder', folder);
	fd.append('file_ary', file);

	// submit処理
	$.ajax(`${adiary.myself}?etc/ajax_dummy`, {
		method: 'POST',
		contentType: false,
		processData: false,
		data: fd,
		dataType: 'json',
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
	/** @type {HTMLTextAreaElement} */
    const txt = document.getElementById('editarea');
	txt.onpaste = (e) => {
		if (e.clipboardData.files.length) {
			const pasteFile = e.clipboardData.files[0];
			const ext = pasteFile.name.match(/\.([^\.]+)$/)[1];
			const dt = new Date();
			const timestamp = `${dt.getFullYear()}-${dt.getMonth() + 1}-${dt.getDate()}_${dt.getHours()}-${dt.getMinutes()}-${dt.getSeconds()}-${dt.getMilliseconds()}`
			const file = new File([pasteFile], `paste-image-${timestamp}.${ext}`, { type: pasteFile.type });
			uploadFile(file, (data, folder) => {
				upload_files_insert(data, {
					folder:		folder, // TODO: 突っ込むフォルダ：どっかで既定値を設定したい
					thumbnail:	true, // TODO: サムネ：どっかで既定値を設定したい
					caption:	'',
					exif:		false, // TODO: 回り込み指定：どっかで既定値を設定したい
					class:		'' // TODO: 回り込み指定：どっかで既定値を設定したい
				});
			});
		} else {
			// 何もしない
		}
	}
};

});

