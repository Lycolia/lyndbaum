//##############################################################################
// アルバム用JavaScript
//							(C)2014 nabe@abk
//##############################################################################
//[TAB=8]  require tree.js
//
//tree.json
//	name	フォルダ名	ex) yyy/
//	key	フォルダパス	ex) xxx/yyy/
//	date	UTC
//	count	全ファイル数（サブフォルダ含む）
//
//view.json
//	name	ファイル名
//	size	ファイルサイズ
//	date	UTC
//	isImg	画像ファイルか？true/false
//
'use strict';

adiary.ready(function(){
	function $id(id) { return document.getElementById(id) }
	var tree = $id('album-folder-tree');
	var view = $id('album-folder-view');
	var selfiles   = $id('selected-files');
	if (!tree || !view) return;
	var allow_edit = jq_data(view, 'edit');
	var dtree;

	// 表示設定
	var all_select = $id('all-select');
	var view_type  = $id('view-type');
	var sort_type  = $id('sort-type');
	var sort_rev   = $id('sort-rev');
	var folder_icon= $id('folder-icon-change');
	var name_filter= $id('name-filter');
	var is_thumbview;

	// ツリー関連
	var path = text_of('image-path');
	var cur_files;
	var cur_folder;		// ex) '/' 'newfolder/' 'aaa/bbb/ccc/' 'path/to/'
	var cur_node;
	var cur_folder_rel;	// cur_folder == '/'のとき空文字

	// ファイルアップロード関連
	var upform   = adiary.secure('#upload-form');
	var message  = $id('upload-messages');
	var upfolder = $id('upload-folder');
	var file_btn = $id('file-btn');

	// Drag&Drop関連
	var dnd_body = $id('body');

	var isMac = /Mac/.test(navigator.platform);

	// フラグ管理
	var key_event_stop;
	var uploading;

	// 画像やファイル名の要素に持たせる値（今までのjQueryの.data()）
	//	{ title: ファイル名, isimg, viewable, href }
	var fdata = new WeakMap();

////////////////////////////////////////////////////////////////////////////////
// ●jQueryの代わり
////////////////////////////////////////////////////////////////////////////////
function text_of(id) {
	var dom = $id(id);
	return dom ? dom.textContent : '';
}
function on(dom, type, func) {
	if (dom) dom.addEventListener(type, func);
}
function create(tag, cls) {
	var dom = document.createElement(tag);
	if (cls) dom.className = cls;
	return dom;
}
// jQueryの.data()と同じく、data-*の値を数値などに直す
function jq_data(dom, name) {
	var v = dom.getAttribute('data-' + name);
	if (v === null) return undefined;
	if (v === 'true')  return true;
	if (v === 'false') return false;
	if (v === 'null')  return null;
	if (v === +v + '') return +v;
	if (/^(?:\{[\w\W]*\}|\[[\w\W]*\])$/.test(v)) {
		try { return JSON.parse(v) } catch(e) { }
	}
	return v;
}
// jQueryの.blur()と同じく、focusが無くてもblurの処理を呼ぶ
function blur(inp) {
	if (document.activeElement === inp) inp.blur();
		else inp.dispatchEvent( new FocusEvent('blur') );
}
// jQueryの.toggle(bool)
function toggle(dom, flag) {
	if (!dom) return;
	if (flag) adiary.show(dom);
	     else adiary.hide(dom);
}
// 選択中の要素（画像、ファイル名の行）
function selected_items() {
	return Array.from( view.querySelectorAll('.selected') );
}
function set_visibility(items, val) {
	items.forEach(function(x){ if (x.parentNode) x.parentNode.style.visibility = val });
}

////////////////////////////////////////////////////////////////////////////////
// ●初期化処理
////////////////////////////////////////////////////////////////////////////////
var set = {
	autoFocus: false,
	persist: true,
	cookieId: 'album:' + adiary.myself,
	minExpandLevel: 2,
	imagePath: text_of('icon-path'),

	url: tree.dataset.url,
	onPostInit: function(isReloading, isError) {
		if (isError) {
			error_msg('#msg-load-error');
			return;
		}

		// ロードしたデータの加工
		var rootNode = this.getRoot();
		rootNode.visit(function(node){
			var data = node.data;
			data.name     = adiary.tag_decode(data.name || '');
			data.key      = adiary.tag_decode(data.key);
			data.title    = get_title(data);
			data.expand   = true;
			data.isFolder = true;
		});
		var rnodes = rootNode.getChildren();
		if (!rnodes) return;	// エラー回避
		var root = rnodes[1];
		root.data.fix = true;

		// ゴミ箱の設定
		if (rnodes[2].data.name === '.trashbox/') {
			var data = rnodes[2].data;
			data.name  = text_of('msg-trashbox');
			data.title = get_title(data);
			data.name  = '.trashbox/';
			data.fix   = true;
			data.icon  = 'trashbox.png';
		}

		// 開くフォルダの指定（?media/&folder=xxx/。記事作成画面のアイキャッチ画像から）
		var open_key = !isReloading && new URLSearchParams(location.search).get('folder');
		var open_node = open_key && this.getNodeByKey(open_key);
		if (open_node) open_node.activateSilently();

		// 選択中のノード
		var sel = this.getActiveNode();
		if (!sel) {
			root.activate();
			sel = root;
		}

		// レンダリング
		rootNode.render();
		open_folder(sel, isReloading);
	},
	onActivate: function(node) {
		open_folder(node);
	},
	// ノードの編集
	onClick: function(node, event) {
		if( event.shiftKey ) edit_node(node);
		return true;
	},
	onDblClick: function(node, event) {
		edit_node(node);
		return false;
	},
	onKeydown: function(node, event) {
		switch( event.which ) {
			case 113: // [F2]
				edit_node(node);
				return false;
			case 13: // [enter]
				if( isMac ) edit_node(node);
				return false;
		}
	},

	//--------------------------------------------------
	// Drag & Drop
	//--------------------------------------------------
	dnd: {
		onDragStart: function(node) {
			if (node.data.fix) return false;
			return true;	// Return false to cancel dragging of node.
		},
		autoExpandMS: 400,
		preventVoidMoves: true, // Prevent dropping nodes 'before self', etc.
		onDragEnter: function(node, srcNode) {
			return true;
		},
		onDragOver: function(node, srcNode, hitMode) {
			if (hitMode==='before' || hitMode==='after') return false;
			if(node.isDescendantOf(srcNode)) return false;
			if(node.data.isroot) return false;
			if (!srcNode) return true;

			// 現在のディレクトリ内への移動
			var src_par = srcNode.getParent();
			if (src_par && src_par.data.key === node.data.key) return false;

			return true;
		},
		onDrop: drop_to_tree
	}
}
if(! allow_edit) {	// 編集権限なし
	delete set['onClick'];
	delete set['onDblClick'];
	delete set['onKeydown'];
	delete set['dnd'];
}
dtree = new AdiaryTree(tree, set);

function get_title(data) {
	return adiary.tag_esc(data.name) + (data.count==0 ? '' : ' (' + data.count + ')');
}

//##############################################################################
// ■フォルダツリー関連
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// ●フォルダ名の編集
////////////////////////////////////////////////////////////////////////////////
function edit_node( node ) {
	if (node.data.fix) return;	// rootとゴミ箱

	var ctree = node.tree;
	ctree.disable();			// ツリーのクリックとキーを止める
	var name = node.data.name;
	name = name.substr(0, name.length-1);	// 201201/ to 201201

	// ノードの選択中表示を解除する
	var span = node.span;
	span.classList.remove('dynatree-active');

	// タイトルを<input>要素に置き換える
	var inp = document.createElement('input');
	inp.setAttribute('type',  'text');
	inp.setAttribute('value', name);
	inp.className = 'folder-edit-inp no-resize';
	// aタグ内にinputを入れると不可思議な動作をするので、
	// 変わりのspan boxを作り置き換える。
	var item = span.querySelector( ".dynatree-title" );	// aタグ
	var box = document.createElement('span');
	box.className = item.getAttribute('class');
	box.appendChild( inp );
	item.replaceWith( box );

	// Focus <input> and bind keyboard handler
	inp.focus();
	inp.addEventListener('keydown', function(evt){
		switch( evt.which ) {
			case 27: // [esc]
				blur(inp);
				break;
			case 13: // [enter]
				rename_folder(inp, node, inp.value);
				break;
			case 46: // delete
				evt.stopPropagation();	// stop delete folder
				break;
		}
	});
	//----------------------------------------
	// ○ツリーのクリック
	//----------------------------------------
	var tree_click = function(evt){
		if (inp == evt.target) return;
		blur(inp);
	};
	tree.addEventListener('click', tree_click);

	//----------------------------------------
	// ○フォーカスが離れた（編集終了）
	//----------------------------------------
	inp.addEventListener('blur', function(evt){
		box.remove();
		tree.removeEventListener('click', tree_click);
		node.setTitle( node.data.title );
		ctree.enable();
		node.data.rename = false;
		node.focus();
		if (evt && evt.which == 13 && node.data.key != cur_node.data.key)
			node.activate();
	});
}

//------------------------------------------------
// ○リネームの実行
//------------------------------------------------
function rename_folder(obj, node, name) {
	if (name.substr(-1) != '/') name += '/';
	if (name == '' || node.data.name === name) {
		blur(obj);	// 変更なし
		return;
	};
	node.data.rename = true;

	ajax_submit({
		action: 'rename_folder',
		data: {
			folder: node.getParent().data.key,
			old:    node.data.name,
			name:   name
		},
		success: function(data) {
			if (data.ret !== 0) {
				blur(obj);
				// blur()してから呼び出さないとキー入力がbindされない
				error_msg('#msg-fail-rename-folder');
				return;
			}
			node.data.name  = name;
			node.data.title = get_title( node.data );
			set_keydata(node.getParent().data.key, node);

			if (cur_node.data.key === node.data.key) set_current_folder(node);
			node.data.rename = false;
			blur(obj);
		},
		error: function() {
			node.data.rename = false;
			blur(obj);
			error_msg('#msg-fail-rename-folder');
		}
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●リロードボタン
////////////////////////////////////////////////////////////////////////////////
function tree_reload() {
	dtree.reload();
}

on($id('album-reload'), 'click', function(){
	ajax_submit({
		action: 'refresh',
		success: function(data) {
			if (data.ret !== 0) return error_msg('#msg-fail-reload');
			tree_reload();
		},
		error: function() {
			error_msg('#msg-fail-reload');
		}
	});
});

////////////////////////////////////////////////////////////////////////////////
// ●フォルダ作成ボタン
////////////////////////////////////////////////////////////////////////////////
on($id('album-new-folder'), 'click', function(){
	var node = cur_node;
	var ary  = node.getChildren();
	var name = "new-folder";
	if (ary) {
		// フォルダ名の重複防止
		var h = {};
		for(var i=0; i<ary.length; i++) {
			var dir = ary[i].data.name;
			dir = dir.substr(0, dir.length-1);
			h[dir] = true;
		}
		if (h[name]) {
			// new-folder.2 .3 .4 ...
			for(var i=2; i<1000; i++) {
				var n = name + '.' + i;
				if (h[n]) continue;
				name = n;
				break;
			}
		}
	}
	// フォルダの作成
	ajax_submit({
		action: 'create_folder',
		data: {
			folder: cur_folder,
			name:   name
		},
		success: function(data) {
			if (data.ret !== 0) return error_msg('#msg-fail-create');
			name += '/';
			tree.querySelectorAll('.folder-edit-inp').forEach(blur);	// addChild前に

			var create = node.addChild({
			        isFolder: true,
				title: name,
				name:  name,
				key: cur_folder + name,
				count: 0
			});

			// 名前変更モード
			node.expand();	// 重複expandを2回するとエラーになる
			edit_node(create);
		},
		error: function() {
			error_msg('#msg-fail-create');
		}
	});
});

////////////////////////////////////////////////////////////////////////////////
// ●ゴミ箱を空にする
////////////////////////////////////////////////////////////////////////////////
function clear_trash() {
	// 確認メッセージ
	adiary.confirm('#msg-confirm-trash', function(flag) {
		if (!flag) return;
		delete_folder('.trashbox/');
	});
}
on($id('album-clear-trashbox'), 'click', clear_trash);

////////////////////////////////////////////////////////////////////////////////
// ●フォルダの削除
////////////////////////////////////////////////////////////////////////////////
function delete_folder(folder) {
	var msg = (folder == '.trashbox/') ? '#msg-fail-clear-trash' : '#msg-fail-delete-folder';
	ajax_submit({
		action: 'delete_folder',
		data: {
			folder: folder
		},
		success: function(data) {
			if (data.ret !== 0) error_msg(msg);
			tree_reload();
		},
		error: function() {
			error_msg(msg);
			tree_reload();
		}
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●フォルダの移動
////////////////////////////////////////////////////////////////////////////////
function drop_to_tree(node, srcNode, hitMode) {
	// フォルダの中へのドロップのみ有効
	if (hitMode !== "over") return false;

	// ファイルのドロップ？
	if (!srcNode) return drop_files_to_tree(node, srcNode, hitMode);

	// フォルダの移動
	move_folder(node, srcNode);
}

function move_folder(node, srcNode) {
	node = (typeof(node) == 'string') ? dtree.getNodeByKey(node) : node;

	var from = srcNode.getParent().data.key;
	var to   = node.data.key;
	if (to.indexOf(cur_folder) == 0) return false;	// 自分自身やその子へは移動できない
	if (from == to) return false;			// 今あるフォルダと同じ場所へは移動できない

	ajax_submit({
		action: 'move_files',
		data: {
			from: from,
			to:   to,
			file_ary: [ chop_slash(srcNode.data.name) ]
		},
		success: function(data) {
			if (data.ret !== 0) error_msg('#msg-fail-mv-folder', {files: data.files});
			srcNode.move(node, 'over');
			tree_reload();
		},
		error: function() {
			error_msg('#msg-fail-mv-folder');
		}
	});
	return true;
}

////////////////////////////////////////////////////////////////////////////////
// ●ファイルの移動
////////////////////////////////////////////////////////////////////////////////
function drop_files_to_tree(node, srcNode, hitMode) {
	// 移動処理
	if (! move_files(node.data.key)) return false;

	// 元アイコンは非表示のままにする
	visible_on_stop = false;
	return true;
}

function move_files(to_folder) {
	if (to_folder === cur_folder) return false;

	var files = load_selected_files();
	if (!files) return false;

	ajax_submit({
		action: 'move_files',
		data: {
			from: cur_folder,
			to:   to_folder,
			file_ary: files
		},
		success: function(data) {
			for(var i in data.files) {
				data.files[i] = data.files[i].replace(/\.#[\d\-]+/g, '');
			}
			if (data.ret !== 0) error_msg('#msg-fail-mv-files', {files: data.files});
			tree_reload();
		},
		error: function() {
			error_msg('#msg-fail-mv-files');
			// ファイルを再表示
			set_visibility(selected_items(), 'visible');
		}
	});
	return true;
}

////////////////////////////////////////////////////////////////////////////////
// ●ファイルの削除
////////////////////////////////////////////////////////////////////////////////
function delete_files() {
	var files = load_selected_files();
	if (!files) return false;

	ajax_submit({
		action: 'delete_files',
		data: {
			folder: cur_folder,
			file_ary: files
		},
		success: function(data) {
			for(var i in data.files) {
				data.files[i] = data.files[i].replace(/\.#[\d\-]+/g, '');
			}
			if (data.ret !== 0) error_msg('#msg-fail-delete-files', {files: data.files});
			tree_reload();
		},
		error: function() {
			error_msg('#msg-fail-delete-files');
			// ファイルを再表示
			set_visibility(selected_items(), 'visible');
		}
	});
	return true;
}

////////////////////////////////////////////////////////////////////////////////
// ●選択ファイルの一覧の更新
////////////////////////////////////////////////////////////////////////////////
var li_names = new WeakMap();	// 一覧のliのファイル名（今までのli.data('name')）
function update_selected_files() {
	var imgs = selected_items();
	if (!imgs.length) all_select.checked = false;
	if (imgs.length && imgs.length == cur_files.length) all_select.checked = true;

	selfiles.innerHTML = '';
	for(var i=0; i<imgs.length; i++) {
		var name = fdata.get(imgs[i]).title;
		var li = document.createElement('li');
		li.textContent = name;
		li_names.set(li, name);
		li.addEventListener('dblclick', function(evt){ edit_file_name(evt.currentTarget); });
		selfiles.appendChild(li);
	}
	var bool = (imgs.length == 0);
	document.querySelectorAll('#paste-form [data-select]').forEach(function(x){ x.disabled = bool });
	var eye = $id('set-eyecatch');
	if (eye) eye.disabled = !(imgs.length == 1 && fdata.get(imgs[0]).isimg);
}

//------------------------------------------------------------------------------
// ファイル名の編集
//------------------------------------------------------------------------------
function edit_file_name(li) {
	key_event_stop = true;

	var inp = document.createElement('input');
	inp.setAttribute('type',  'text');
	inp.setAttribute('value', li_names.get(li));
	inp.className = 'w100p';
	li.innerHTML = '';
	li.appendChild( inp );

	inp.focus();
	inp.select();
	inp.addEventListener('keydown', function(evt){
		switch( evt.which ) {
			case 27: // [esc]
				blur(inp);
				break;
			case 13: // [enter]
				if (li_names.get(li) == inp.value) {
					blur(inp);
					break;
				}
				rename_file(inp, li, inp.value);
				break;
		}
	});
	//----------------------------------------
	// ○フォーカスが離れた（編集終了）
	//----------------------------------------
	inp.addEventListener('blur', function(evt){
		key_event_stop = false;
		li.textContent = li_names.get(li);
	});

}

//------------------------------------------------------------------------------
// ファイル名の変更
//------------------------------------------------------------------------------
function rename_file(obj, li, new_name) {
	ajax_submit({
		action: 'rename_file',
		data: {
			folder: cur_folder,
			old:    li_names.get(li),
			name:   new_name
		},
		success: function(data) {
			if (data.ret !== 0) return error_msg('#msg-fail-rename-file');
			var old = li_names.get(li);
			li_names.set(li, new_name);
			blur(obj);

			// ファイル名の変更を記録する
			for(var i in cur_files) {
				if (cur_files[i].name != old) continue;
				cur_files[i].name = new_name;
				break;
			}

			// 選択済情報を保持する
			var lis = selfiles.querySelectorAll('li');
			var files = {};
			for(var i=0; i<lis.length; i++) {
				files[ li_names.get(lis[i]) ] = true;
			}
			update_view(true, files);
		},
		error: function() {
			error_msg('#msg-fail-rename-file');
			blur(obj);
		}
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●サブルーチン
////////////////////////////////////////////////////////////////////////////////
// tree操作時のエラー表示
function error_msg(id, h) {
	if (h && h.files)
		h.f = '<ul class="small"><li>' + h.files.join("</li><li>") + '</li></ul>';
	adiary.show_error({id:id, hash:h});
}

// 末尾の/を除去
function chop_slash(str) {
	if (str.substr(-1) != '/') return str;
	return str.substr(0, str.length-1);
}

// keyの設定
function set_keydata(folder, node) {
	folder = folder + node.data.name;
	var cur = (node.data.key === cur_node.data.key);
	node.data.key = folder;
	if (cur) set_current_folder(node);

	var list = node.getChildren();
	if (!list) return;

	for(var i=0; i<list.length; i++)
		set_keydata(folder, list[i]);
};

//##############################################################################
// ■メインビュー関連
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// ●フォルダを開く
////////////////////////////////////////////////////////////////////////////////
function open_folder(node, isReloading) {
	if (!isReloading && !uploading) {
		adiary.hide(message);
		all_select.checked = false;
	}
	if (node.data.rename) return;	// リネーム中は何もしない

	ajax_submit({
  		data: {	folder: node.data.key },
		action: 'load_image_files',
		success: function(data) {
			// 数値→文字列（数字だけのファイル名対策）
			for(var i in data) {
				if (typeof(data[i].name) == "string") continue;
				data[i].name = data[i].name.toString();
			}
			// データsave
			cur_files = data;
			set_current_folder(node);
			// jpegあり？
			var jpeg;
			for(var i in cur_files) {
				var file = cur_files[i].name;
				if (! file.match(/\.jpe?g$/i)) continue;
				jpeg = true;
				break;
			}
			var exif = $id('select-exifjpeg');
			if (exif) exif.disabled = !jpeg;
			if (data.length==0)	// ファイルがひとつもない
				all_select.checked = false;

			// viewの更新
			update_view();
		},
		error: function() {
			$id('current-folder').textContent = '(load failed!)';
			error_msg('#msg-load-error');
			cur_files = [];
			set_current_folder(node);
			update_view();
		}
	});
}

function set_current_folder(node) {
	cur_folder = node.data.key;
	cur_node   = node;
	upfolder.value = cur_folder;
	cur_folder_rel = (cur_folder == '/') ? '' : cur_folder;

	var icon = $id('folder-icon');
	icon.innerHTML = '';
	icon.classList.remove('dynatree-icon');

	var title = node.data.key;
	if (title.substr(0,9) == '.trashbox') {
		title = text_of('msg-trashbox') + title.substr(9);
		var img = document.createElement('img');
		img.setAttribute('src', text_of('icon-path') + 'trashbox.png');
		icon.appendChild( img );
	} else {
		icon.classList.add('dynatree-icon');
	}
	$id('current-folder').textContent = title;
}

////////////////////////////////////////////////////////////////////////////////
// ●ajaxデータ送信
////////////////////////////////////////////////////////////////////////////////
// 今までの$.ajax（traditional: true）と同じく、配列は同じ名前で並べて送る
function ajax_submit(opt) {
	var data = opt.data || {};
	data.action = $id('action-base').value + opt.action;

	var body = new URLSearchParams();
	for(var k in data) {
		var v = data[k];
		if (Array.isArray(v))
			v.forEach(function(x){ body.append(k, x == null ? '' : x) });
		else	body.append(k, v == null ? '' : v);
	}

	folder_icon.className = 'dynatree-statusnode-wait';	// Loding.gif
	fetch(adiary.myself + '?etc/ajax_dummy', {
		method: 'POST',
		body:   body
	}).then(function(res){
		return res.text().then(function(text){ return { res: res, text: text } });
	}).then(function(r){
		var ok = r.res.ok;
		var ret;
		if (ok && (opt.type || 'json') === 'json') {
			try { ret = JSON.parse(r.text) } catch(e) { ok = false }
		} else ret = r.text;
		finish(ok, ret, r.text);
	}, function(e){
		finish(false, null, '');
	});
	function finish(ok, ret, text) {
		if (ok) {
			if (opt.success) opt.success(ret);
		} else {
			if (opt.error) opt.error({ responseText: text });
		}
		folder_icon.className = 'dynatree-ico-ef';
	}
	return true;
}

////////////////////////////////////////////////////////////////////////////////
// ●全選択
////////////////////////////////////////////////////////////////////////////////
on(all_select, 'change', function(){ all_select_change() });

// 名前で絞り込んでいれば、出ているものだけ
function shown_items() {
	var ary = [];
	for(var a of view.children) {
		if (a.tagName !== 'A' || a.classList.contains('filtered-out')) continue;
		for(var x of a.children)
			if (is_thumbview ? x.tagName === 'IMG' : x.classList.contains('fileline')) ary.push(x);
	}
	return ary;
}
function all_select_change(init) {
	var stat = all_select.checked;
	var imgs = shown_items();
	for(var i=0; i<imgs.length; i++) {
		var obj = imgs[i];
		if (stat) {
			obj.classList.add('selected');
			continue;
		}
		if (!init) obj.classList.remove('selected');
	}
	update_selected_files();
}

////////////////////////////////////////////////////////////////////////////////
// ●表示形式変更
////////////////////////////////////////////////////////////////////////////////
on(view_type, 'change', view_change);
on(sort_type, 'change', view_change);
on(sort_rev,  'change', view_change);
function view_change() {
	// 選択済情報を保持する
	var imgs = selected_items();
	var files = {};
	for(var i=0; i<imgs.length; i++) {
		files[ fdata.get(imgs[i]).title ] = true;
	}
	update_view(false, files);
}

////////////////////////////////////////////////////////////////////////////////
// ●名前で絞り込み
////////////////////////////////////////////////////////////////////////////////
// 名前に語を含むファイルだけを出す（大文字と小文字は区別しない）。Lyndbaum 0のメディアと同じ
// 当たらないファイルは隠すだけで、選んでいれば選んだままにする。語はフォルダを移っても残す
// 範囲選択、全選択、画像ビューアーは、出ているファイルだけを対象にする。ゴミ箱では絞り込まない
on(name_filter, 'input', apply_filter);

function apply_filter() {
	var trash = cur_folder && cur_folder.substr(0,9) == '.trashbox';
	toggle(name_filter, !trash);
	var word  = trash ? '' : name_filter.value.trim().toLowerCase();
	var shown = 0;
	for(var link of view.children) {
		if (link.tagName !== 'A') continue;
		var obj  = link.firstElementChild;
		var d    = obj && fdata.get(obj) || {};
		var hit  = word == '' || String(d.title).toLowerCase().indexOf(word) >= 0;
		link.classList.toggle('filtered-out', !hit);
		// 画像ビューアーは開くときにdata-lythumbのリンクを集めるので、隠したものは外す
		if (hit && d.viewable)
			link.setAttribute('data-lythumb', 'roadtrip');
		else
			link.removeAttribute('data-lythumb');
		if (hit) shown++;
	}
	for(var x of view.children)
		if (x.classList.contains('file-not-found')) toggle(x, shown == 0);
	$id('current-count').textContent = trash ? '' : '(' + shown + '件)';
}


////////////////////////////////////////////////////////////////////////////////
// ●ビューのアップデート
////////////////////////////////////////////////////////////////////////////////
function update_view(flag, selected) {
	var thumbq = '';
	if (flag) {
		// サムネイルの強制更新
		thumbq = '?' + Date.now();
	}

	// 選択済みファイルのハッシュ
	selected = selected ? selected : {};

	// ソート処理。既定は日付の降順（skel/media/_main.html）。
	// 同じ値（同じ秒に上げたファイルなど）は名前順にして、開くたびに並びが変わらないようにする
	{
		var type = sort_type.value;
		var rev  = sort_rev.value != 0 ? -1 : 1;
		cur_files.sort(function(a,b) {
			if (a[type] != b[type]) return (a[type] < b[type] ? -1 : 1) * rev;
			if (a.name  != b.name ) return (a.name  < b.name  ? -1 : 1) * rev;
			return 0;
		});
	}

	view.innerHTML = '';
	var fspath = path + cur_folder_rel;
	if (view_type.value != 'name')
	  for(var i in cur_files) {
		// サムネイルビュー
		is_thumbview = true;
		view.classList.remove('name-view');
		view.classList.add('thumb-view');
		var file = cur_files[i];
		var viewable = file.isImg || is_video_file(file.name);	// 画像ビューアーで開ける（画像と動画）
		var link = document.createElement('a');
		link.setAttribute('href', encode_link( fspath + file.name ));
		if (viewable) {
			link.setAttribute('data-lythumb', 'roadtrip');
			link.setAttribute('data-caption', file.name);
		}
		var img = document.createElement('img');
		img.setAttribute('src', encode_link( fspath + '.thumbnail/' + thumbnail_name(file) ) + thumbq);
		img.setAttribute('data-title', file.name);
		img.setAttribute('data-isimg', file.isImg ? 1 : 0);
		fdata.set(img, { title: file.name, isimg: file.isImg, viewable: viewable });
		if (allow_edit) {
			img.addEventListener('click',    img_click);
			img.addEventListener('dblclick', img_dblclick);
		} else {
			img.addEventListener('click', img_dblclick);
		}

		if (selected[file.name]) img.classList.add('selected');
		link.appendChild(img);
		view.appendChild(link);

		// for Drag&Drop
		img_draggable(img, 0.7);
		if (allow_edit) dbltap(img);	// ダブルタップ
	} else {
	  for(var i in cur_files) {
		// ファイル名ビュー
		is_thumbview = false;
		view.classList.remove('thumb-view');
		view.classList.add('name-view');
		var file = cur_files[i];
		var viewable = file.isImg || is_video_file(file.name);	// 画像ビューアーで開ける（画像と動画）
		var link = document.createElement('a');
		link.setAttribute('href', encode_link( fspath + file.name ));
		if (viewable) {
			link.setAttribute('data-lythumb', 'roadtrip');
			link.setAttribute('data-caption', file.name);
		}
		var span = create('span', 'fileline');
		fdata.set(span, {
			title: file.name,
			isimg: file.isImg ? 1 : 0,
			viewable: viewable,
			href:  link.getAttribute('href')	// for CTRL + click
		});
		// ファイル名（admin.jsのポップアップが、data-img-urlの画像を出す）
		var fname = create('span', 'js-popup-img');
		fname.textContent = file.name;
		fname.setAttribute('data-img-url', encode_link( fspath + '.thumbnail/' + thumbnail_name(file) ) + thumbq);
		var fn = create('span', 'filename');
		fn.appendChild( fname );
		span.appendChild( fn );
		// 日付
		var date = new Date( file.date*1000 );
		var tms  = date.toLocaleString().replace(/\b(\d[\/: ])/g, "0$1");
		var fd = create('span', 'filedate');
		fd.textContent = tms;
		span.appendChild( fd );
		// サイズ
		var fs = create('span', 'filesize');
		fs.textContent = adiary.size_format(file.size);
		span.appendChild( fs );

		// 追加
		if (allow_edit) {
			span.addEventListener('click',    img_click);
			span.addEventListener('dblclick', img_dblclick);
		} else {
			span.addEventListener('click', img_dblclick);
		}

		if (selected[file.name]) span.classList.add('selected');
		link.appendChild(span);
		view.appendChild(link);

		// for Drag&Drop
		img_draggable(span, 0.95);
		if (allow_edit) dbltap(span);	// ダブルタップ
	  }
	}
	// file not found.（名前で絞り込んで1つも出ないときも出す。apply_filterで切り替える）
	{
		var div = create('div', 'file-not-found');
		div.textContent = '(File not found)';
		view.appendChild( div );
	}
	apply_filter();

	// 押した要素（ファイル名ビューでは、中のspanを押しても行にする）
	function item_of(evt) {
		var obj = evt.target;
		if (!is_thumbview && !obj.classList.contains('fileline')) obj = obj.closest('.fileline');
		return obj;
	}
	// ダブルタップ（今までのmydbltapと同じく、ダブルクリックと同じ処理を呼ぶ）
	function dbltap(dom) {
		AdiaryTree.dbltap(dom, function(evt){
			img_dblclick({ type: 'mydbltap', target: evt.target });
		});
	}

	//--------------------------------------------------
	// 画像のクリック
	//--------------------------------------------------
	var dbl_click;
	var stop_prop;
	var prev_sel;
	function img_click(evt) {
		var obj = item_of(evt);
		if (dbl_click) {
			dbl_click = false;
			return;
		}

		if (evt.ctrlKey) {
			if (evt.shiftKey) return true;	// ブラウザデフォルト

			// downloadさせる
			evt.stopPropagation();
			evt.preventDefault()
			var file = fdata.get(obj).href || obj.parentNode.getAttribute('href');
			var dl = document.createElement('a');
			dl.setAttribute('href', file);
			dl.setAttribute('download', fdata.get(obj).title);
			var e = document.createEvent('MouseEvent');
			e.initEvent("click", true, false);
			dl.dispatchEvent( e );
			return;
		}

		// 選択処理
		evt.stopPropagation();
		evt.preventDefault()
		if (prev_sel && evt.shiftKey && prev_sel != obj) {
			var ary = [];
			// 名前で絞り込んでいれば、出ているものだけ（apply_filter）
			// 前方、後方の範囲選択
			['previousElementSibling', 'nextElementSibling'].forEach(function(dir){
				var objs = [];
				for(var x = prev_sel.parentNode[dir]; x; x = x[dir]) {
					if (x.classList.contains('filtered-out')) continue;
					for(var c of x.children) objs.push(c);
				}
				var find = objs.indexOf(obj);
				for(var i=0; i<=find; i++) ary.push(objs[i]);
			});

			// 選択・非選択操作
			var add = prev_sel.classList.contains('selected');
			for(var i=0; i<ary.length; i++) ary[i].classList.toggle('selected', add);
		} else {
			prev_sel = obj;
			obj.classList.toggle('selected');
		}
		update_selected_files();
	}

	//--------------------------------------------------
	// 画像のダブルクリック
	//--------------------------------------------------
	function img_dblclick(evt) {
		var obj = item_of(evt);
		if (!fdata.get(obj).viewable) return;
		if (evt.type == 'click') return;
		dbl_click = true;
		obj.click();
	}

	// 選択ファイル情報更新
	update_selected_files();
}

////////////////////////////////////////////////////////////////////////////////
// ●画像ファイルのドラッグ（今までのjQuery UIのdraggableと同じ動き）
////////////////////////////////////////////////////////////////////////////////
// 押して200ms以上たってから動かすと始まる（delay）。選んでいる画像をまとめてつかみ、
// ツリーのフォルダに落とすと移動する。落とせないときは、元の所へ戻る（revert）
var visible_on_stop;
var DragDelay      = 200;	// msec
var RevertDuration = 500;	// msec
var TouchDnDTime   = 100;	// msec（スマホ。指を置いてから、これより前に動かすとスクロール）
var ScrollSensitivity = 20;	// jQuery UIのdraggableの既定と同じ
var ScrollSpeed       = 20;
var drag;			// ドラッグの間の状態
var reverting   = new WeakSet();	// 戻る動きの間の要素（その間は、つかめない）
var click_after = null;		// ドラッグの後に止めるクリックの要素

function offset_of(el) {	// jQueryの.offset()
	if (!el.getClientRects().length) return { top: 0, left: 0 };
	var r = el.getBoundingClientRect();
	return { top: r.top + window.pageYOffset, left: r.left + window.pageXOffset };
}
function is_root(el) {
	return /(html|body)/i.test(el.tagName) || el === document;
}
function scroll_parent(el, includeHidden) {	// jQuery UIの.scrollParent()
	var cs  = getComputedStyle(el);
	var pos = cs.position;
	var excludeStatic = pos === 'absolute';
	var reg = includeHidden ? /(auto|scroll|hidden)/ : /(auto|scroll)/;
	if (pos !== 'fixed')
		for(var p = el.parentElement; p; p = p.parentElement) {
			var c = getComputedStyle(p);
			if (excludeStatic && c.position === 'static') continue;
			if (reg.test(c.overflow + c.overflowY + c.overflowX)) return p;
		}
	return document;
}
function scroll_top(el)  { return el === document ? window.pageYOffset : el.scrollTop  }
function scroll_left(el) { return el === document ? window.pageXOffset : el.scrollLeft }

//------------------------------------------------------------------------------
// ドラッグ中の要素（今までのhelper）
//------------------------------------------------------------------------------
function make_helper(down) {
	// 開始要素が選択されてない時、選択する
	var obj = down;
	if (!is_thumbview && !obj.classList.contains('fileline')) obj = obj.closest('.fileline');
	if (!obj.classList.contains('selected')) {
		obj.classList.add('selected');
		update_selected_files();
	};
	// 選択中の画像すべて
	var div = document.createElement('div');
	if (is_thumbview) {
		// アイコンビューのとき
		var imgs = selected_items().map(function(x){ return x.cloneNode(true) });
		imgs.forEach(function(x){
			x.classList.remove('selected');
			if (!x.getAttribute('class')) x.removeAttribute('class');
			// 一覧のマスの指定（幅100%など）を受けるので、大きさと並べ方をここで決める
			x.style.width   = '60px';
			x.style.height  = '60px';
			x.style.display = 'inline-block';
		});
		div.style.maxWidth = '320px';
		imgs.forEach(function(x){
			x.style.padding    = '1px';
			x.style.border     = 'none';
			x.style.visibility = 'visible';
			div.appendChild(x);
		});
	} else {
		// ファイル名ビューのとき
		var files = selected_items();
		for(var i=0; i<files.length; i++) {
			var span = document.createElement('span');
			span.textContent = fdata.get(files[i]).title;
			div.appendChild( span );
		}
		div.setAttribute('id', 'album-dnd-name-view');
		div.style.visibility = 'visible';
	}
	return div;
}

//------------------------------------------------------------------------------
// 要素をつかめるようにする
//------------------------------------------------------------------------------
function img_draggable(el, opacity) {
	el.addEventListener('mousedown', function(evt){
		if (evt.button !== 0) return;
		if (!down(el, evt, evt.pageX, evt.pageY, opacity)) return;
		evt.preventDefault();
		var mv = function(e){
			if (!drag) return;
			// ボタンを離したのにmouseupが来ていないとき（ウィンドウの外で離したなど）
			if (drag.moved && !e.which) {
				if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) drag.ignoreWhich = true;
				else if (!drag.ignoreWhich) return up(e);
			}
			if (e.which || e.button) drag.moved = true;
			move(e.pageX, e.pageY, e.target);
			if (drag && drag.started) e.preventDefault();
		};
		var up = function(e){
			document.removeEventListener('mousemove', mv);
			document.removeEventListener('mouseup',   up);
			finish(e.target, e.pageX, e.pageY, e.which === 1);
		};
		document.addEventListener('mousemove', mv);
		document.addEventListener('mouseup',   up);
	});
	// ドラッグの後のクリックは、押した所と離した所が同じときだけ止める（jQuery UIと同じ）。
	// img_clickの後に登録するので、img_clickは呼ばれる
	el.addEventListener('click', function(evt){
		if (!click_after || click_after !== evt.target) return;
		click_after = null;
		evt.stopImmediatePropagation();
		evt.preventDefault();
		evt.stopPropagation();
	});
}
// スマホ：指を置いて少し待ってから動かすとドラッグ（今までのasysのdndEmulationと同じ）。
// すぐに動かしたときはスクロール
(function(){
	var timer;
	var flag;
	var target;
	view.addEventListener('touchstart', function(evt){
		var t  = evt.touches[0];
		target = evt.target;
		flag   = false;
		var el = target.closest && target.closest('#album-folder-view img, #album-folder-view span.fileline');
		if (!drag && el && view.contains(el)) {
			down(el, evt, t.pageX, t.pageY, is_thumbview ? 0.7 : 0.95);
		}
		timer = setTimeout(function(){
			timer = null;
			flag  = true;
		}, TouchDnDTime);
	}, { passive: true });
	view.addEventListener('touchmove', function(evt){
		if (!flag) {
			if (timer) clearTimeout(timer);
			timer = null;
			return;
		}
		if (!drag) return;
		var t  = evt.changedTouches[0];
		var el = document.elementFromPoint(t.clientX, t.clientY);
		drag.moved = true;
		move(t.pageX, t.pageY, el);
		// 今までのタッチの置き換え（dndEmulation）は、1回のtouchmoveでmousemoveを何回も起こしていたので、
		// 指がノードに乗った最初のtouchmoveで、ノードに入る・上にいるが両方起きていた。それに合わせる
		if (drag && drag.ext) drag.ext.move(el, t.pageX, t.pageY);
		if (evt.cancelable) evt.preventDefault();
	}, { passive: false });
	view.addEventListener('touchend', function(evt){
		if (timer) clearTimeout(timer);
		timer = null;
		if (!drag) return;
		var t = evt.changedTouches[0];
		// 今までと同じく、離した所は指を置いた要素（touchのtarget）にする
		finish(target, t.pageX, t.pageY, true);
	});
	view.addEventListener('touchcancel', function(evt){
		if (timer) clearTimeout(timer);
		timer = null;
		if (!drag) return;
		finish(target, drag.x0, drag.y0, false);
	});
})();

// 押したとき（jQuery UIの_mouseDown、_mouseCapture）
function down(el, evt, x, y, opacity) {
	if (drag || reverting.has(el)) return false;
	if (evt.target.closest && evt.target.closest('input, textarea, button, select, option')) return false;
	// 押した所の外にfocusがあれば外す
	var ae = document.activeElement;
	if (ae && ae !== document.body && !ae.contains(evt.target)) ae.blur();
	if (click_after === evt.target) click_after = null;

	drag = { el: el, target: evt.target, x0: x, y0: y, opacity: opacity, delay: false, started: false };
	drag.timer = setTimeout(function(){ if (drag) drag.delay = true }, DragDelay);
	return true;
}

// 動かしたとき
function move(x, y, target) {
	if (!drag) return;
	var d = drag;
	if (!d.started) {
		if (Math.max(Math.abs(d.x0 - x), Math.abs(d.y0 - y)) < 1 || !d.delay) return;
		start();
		if (!drag) return;
	}
	// 写しの位置
	var pos = position(x, y);
	// 端に来たらスクロール（jQuery UIのscroll）
	auto_scroll(x, y);
	// ツリーのフォルダの上
	if (d.ext) d.ext.move(target, x, y);
	d.helper.style.left = pos.left + 'px';
	d.helper.style.top  = pos.top  + 'px';
}

// 写しの位置（jQuery UIの_generatePosition）
function position(x, y) {
	var d = drag;
	var root = is_root(d.scrollParent);
	if (!root || !d.scroll) d.scroll = { top: scroll_top(d.scrollParent), left: scroll_left(d.scrollParent) };
	return {
		top:  y - d.click.top  - d.parent.top  + (root ? 0 : d.scroll.top),
		left: x - d.click.left - d.parent.left + (root ? 0 : d.scroll.left)
	};
}
function auto_scroll(x, y) {
	var d  = drag;
	var sp = d.scrollParentNotHidden;
	if (sp !== document && sp.tagName !== 'HTML') {
		var o = d.overflowOffset;
		if ((o.top + sp.offsetHeight) - y < ScrollSensitivity)	sp.scrollTop = sp.scrollTop + ScrollSpeed;
		else if (y - o.top < ScrollSensitivity)			sp.scrollTop = sp.scrollTop - ScrollSpeed;
		if ((o.left + sp.offsetWidth) - x < ScrollSensitivity)	sp.scrollLeft = sp.scrollLeft + ScrollSpeed;
		else if (x - o.left < ScrollSensitivity)		sp.scrollLeft = sp.scrollLeft - ScrollSpeed;
	} else {
		var sy = window.pageYOffset;
		if (y - sy < ScrollSensitivity)				window.scrollTo(window.pageXOffset, sy - ScrollSpeed);
		else if (window.innerHeight - (y - sy) < ScrollSensitivity) window.scrollTo(window.pageXOffset, sy + ScrollSpeed);
		var sx = window.pageXOffset;
		if (x - sx < ScrollSensitivity)				window.scrollTo(sx - ScrollSpeed, window.pageYOffset);
		else if (window.innerWidth - (x - sx) < ScrollSensitivity) window.scrollTo(sx + ScrollSpeed, window.pageYOffset);
	}
}

// ドラッグを始める（jQuery UIの_mouseStart）
function start() {
	var d  = drag;
	var el = d.el;
	var h  = make_helper(d.target);
	// 今までと同じく、つかんだ要素の親（<a>）に置く
	el.parentNode.appendChild(h);
	if (!/(fixed|absolute)/.test(getComputedStyle(h).position)) h.style.position = 'absolute';
	h.classList.add('ui-draggable-dragging');
	d.helper  = h;
	d.started = true;

	// 位置の計算に使う値（つかんだ要素の左上を基にし、マウスの右下5pxに出す。cursorAt）
	var cs = getComputedStyle(el);
	var margins = { left: parseInt(cs.marginLeft) || 0, top: parseInt(cs.marginTop) || 0 };
	d.scrollParent = scroll_parent(h, true);
	var op = h.offsetParent;
	while(op && getComputedStyle(op).position === 'static') op = op.offsetParent;
	op = op || document.documentElement;
	var po = offset_of(op);
	if (d.scrollParent !== document && d.scrollParent.contains(op) && d.scrollParent !== op) {
		po.left += d.scrollParent.scrollLeft;
		po.top  += d.scrollParent.scrollTop;
	}
	if (is_root(op)) po = { top: 0, left: 0 };
	var ocs = getComputedStyle(op);
	d.parent = { top: po.top + (parseInt(ocs.borderTopWidth) || 0), left: po.left + (parseInt(ocs.borderLeftWidth) || 0) };
	var abs = offset_of(el);
	d.click = { left: d.x0 - (abs.left - margins.left), top: d.y0 - (abs.top - margins.top) };
	d.original = position(d.x0, d.y0);
	d.click = { left: -5 + margins.left, top: -5 + margins.top };

	// opacity、z-index（今までのjQuery UIのdraggableの設定。cursorは既定のauto）
	d.cursor = getComputedStyle(document.body).cursor;
	document.body.style.cursor = 'auto';
	h.style.opacity = d.opacity;
	h.style.zIndex  = 100;
	d.scrollParentNotHidden = scroll_parent(h, false);
	if (d.scrollParentNotHidden !== document && d.scrollParentNotHidden.tagName !== 'HTML')
		d.overflowOffset = offset_of(d.scrollParentNotHidden);

	// ツリーに落とせるようにする
	if (dtree && set.dnd) d.ext = dtree.externalDrag(h);

	// 選んだ画像を隠す（写しは、visibility:visibleで出す）
	set_visibility(selected_items(), 'hidden');
	visible_on_stop = true;

	// 写しを、押した所の右下に置く
	var pos = position(d.x0, d.y0);
	h.style.left = pos.left + 'px';
	h.style.top  = pos.top  + 'px';
}

// 離したとき（jQuery UIの_mouseUp、_mouseStop）
function finish(up_target, x, y, dropped) {
	var d = drag;
	if (!d) return;
	drag = null;
	clearTimeout(d.timer);
	if (!d.started) return;

	// 押した所と同じ所で離したときは、その後のクリックを止める
	if (up_target === d.target) click_after = up_target;

	// ツリーの上で離したか（今までのdroppableの判定。ツリーの要素の上か）
	var on_tree = false;
	if (d.ext && getComputedStyle(tree).display !== 'none') {
		var o = offset_of(tree);
		on_tree = (o.top <= y && y < o.top + tree.offsetHeight && o.left <= x && x < o.left + tree.offsetWidth);
	}
	// 戻すか（今までのrevertの判定）
	var revert = !on_tree || d.helper.classList.contains('dynatree-drop-reject');

	var stop = function(){
		document.body.style.cursor = d.cursor;
		if (d.ext) d.ext.stop(dropped);
		if (visible_on_stop) set_visibility(selected_items(), 'visible');
		d.helper.classList.remove('ui-draggable-dragging');
		d.helper.remove();
		reverting.delete(d.el);
	};
	if (!revert) return stop();

	// 元の所へ戻る（jQueryのanimateと同じくswing）
	reverting.add(d.el);
	var h  = d.helper;
	var cs = getComputedStyle(h);
	var from = { left: parseFloat(cs.left) || 0, top: parseFloat(cs.top) || 0 };
	var to   = d.original;
	var t0   = Date.now();
	var tick = function(){
		var p = Math.min(1, (Date.now() - t0) / RevertDuration);
		var e = 0.5 - Math.cos(p * Math.PI) / 2;
		h.style.left = (from.left + (to.left - from.left) * e) + 'px';
		h.style.top  = (from.top  + (to.top  - from.top ) * e) + 'px';
		if (p < 1) return requestAnimationFrame(tick);
		stop();
	};
	requestAnimationFrame(tick);
}

////////////////////////////////////////////////////////////////////////////////
// ●記事に貼り付け
////////////////////////////////////////////////////////////////////////////////
var paste_form = adiary.secure('#paste-form');
on(paste_form, 'submit', function(evt){
	// エラー時送信しない為
	if ($id('paste-txt').value == '') {
		evt.preventDefault();
		evt.stopPropagation();
	}
});

on($id('paste-thumbnail'), 'click', paste_button);
on($id('paste-original' ), 'click', paste_button);
on($id('paste-text'     ), 'click', paste_button);

function paste_button(evt) {
	evt.preventDefault();
	evt.stopPropagation();
	var sel = selected_items();
	if (!sel.length) return;

	var btn   = evt.currentTarget;
	var thumb = jq_data(btn, 'thumbnail') ? true : false;
	var text  = jq_data(btn, 'text') ? true : false;	// 画像へのテキストリンク
	var exif  = $id('paste-to-exif').checked;

	var ary=[];
	for(var i=0; i<sel.length; i++) {
		var d    = fdata.get(sel[i]);
		var name = d.title.toString();	// 数字のみのファイル名対策
		var reg  = name.match(/\.(\w+)$/);
		var ext  = reg ? reg[1] : '';
		ary.push({
			folder: cur_folder,
			file:	name,
			ext:	ext,
			isimg:	d.isimg ? true : false,
			exif:	d.isimg && exif ? true : false,
			thumbnail: thumb,
			text:	text
		});
	}
	var data = {
		caption: $id('paste-caption').value,
		class:   $id('paste-class').value,
		files: ary
	};
	if (window.opener) {
		// 子ウィンドウとして開かれていたら
		window.opener.insert_image(data);
		window.close();
		return;
	}
	$id('paste-txt').value = JSON.stringify(data);
	paste_form.requestSubmit();
}

////////////////////////////////////////////////////////////////////////////////
// ●アイキャッチ画像に設定（記事作成画面から開いたとき）
////////////////////////////////////////////////////////////////////////////////
on($id('set-eyecatch'), 'click', function(evt){
	evt.preventDefault();
	evt.stopPropagation();
	var sel = selected_items();
	if (sel.length != 1 || !window.opener || !window.opener.set_eyecatch) return;

	var name = fdata.get(sel[0]).title.toString();	// 数字のみのファイル名対策
	window.opener.set_eyecatch(cur_folder_rel + name);
	window.close();
});

////////////////////////////////////////////////////////////////////////////////
// ●その他の操作（セレクトボックス）
////////////////////////////////////////////////////////////////////////////////
on($id('album-actions'), 'change', function(evt){
	var obj = evt.target;
	var val = obj.value;
	if (!val) return;
	obj.value = '';

	if (val == 'remake-thumbnail')   remake_thumbnail(evt);
	if (val == 'remove-exifjpeg')    remove_exifjpeg(evt);
	if (val == 'select-exifjpeg')    select_exifjpeg(evt);
	if (val == 'album-move-files')   album_move_files(evt);
	if (val == 'album-delete-files') album_delete_files(evt);
	if (val == 'make-video-thumbnail') make_selected_video_thumbnails(evt);
});

////////////////////////////////////////////////////////////////////////////////
// ●動画のサムネイルを作る（docs/仕様/動画のサムネイル.md）
////////////////////////////////////////////////////////////////////////////////
function make_selected_video_thumbnails(){
	var files = load_selected_files();
	if (!files) return;
	make_video_thumbnails(cur_folder, files);
}

// サムネイルのファイル名（.thumbnail/の中）。サーバーがファイル一覧で返す（AVIFかJPEG）
function thumbnail_name(file) {
	return file.thumb || (file.name + '.jpg');
}
// サムネイルを作れて、画像ビューアーで再生できる動画か（サーバーのis_videoと同じ）
function is_video_file(name) {
	return /\.(?:mp4|m4v|webm|ogv)$/i.test(name);
}

// folderのvideos（ファイル名）の中の動画のサムネイルを、ブラウザーで作って送る
function make_video_thumbnails(folder, videos) {
	folder = (folder == '/') ? '' : folder.replace(/^\/+/, '');
	var files = videos.filter( is_video_file ).map(function(name){
		return { folder: folder, name: name };
	});
	if (!files.length) return;

	var msg = create('div', 'message');
	message.appendChild( msg );
	adiary.show_delay(message);
	adiary.make_video_thumbnails(files, path, function(i){
		msg.textContent = text_of('msg-making-video-thumbnail') + ' ' + (i+1) + ' / ' + files.length;
	}).then(function(fail){
		if (fail) {
			msg.classList.add('error');
			msg.textContent = text_of('msg-fail-video-thumbnail').replace('%n', fail);
		} else {
			msg.textContent = text_of('msg-made-video-thumbnail');
		}
		update_view(true);	// サムネイルを読み直す
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●サムネイルの再生成
////////////////////////////////////////////////////////////////////////////////
function remake_thumbnail(){
	album_dialog($id('remake-thumbnail-dialog'), do_remake_thumbnail);
}

function do_remake_thumbnail(){
	var files = load_selected_files();
	if (!files) return false;

	ajax_submit({
		action: 'remake_thumbnail',
		data: {
			folder: cur_folder,
			file_ary: files,
			del_exif: 0
		},
		success: function(data) {
			if (data.ret !== 0) {
				// ファイル名が不正など
				error_msg('#msg-fail-remake');
				return;
			}
			// view更新
			update_view(true);
		},
		error: function() {
			// 通常起きない
			error_msg('#msg-fail-remake');
		}
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●exifファイルの検索
////////////////////////////////////////////////////////////////////////////////
function select_exifjpeg(){
	ajax_submit({
		action: 'load_exif_files',
		data: { folder: cur_folder },
		success: function(data) {
			if (!data in Array)   return error_msg('#msg-load-exif-error');
			if (data.length == 0) return adiary.show_dialog('#msg-exif-notfound');

			// exifファイルを選択
			var files = {};
			for(var i in data) {
				files[ data[i] ] = true;
			}
			update_view(false, files);
		},
		error: function() {
			error_msg('#msg-load-exif-error');
		}
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●Exifの削除
////////////////////////////////////////////////////////////////////////////////
function remove_exifjpeg(){
	var files = load_selected_files();
	if (!files) return false;

	ajax_submit({
		action: 'remove_exifjpeg',
		data: {
			folder: cur_folder,
			file_ary: files
		},
		success: function(data) {
			if (data.ret !== 0) {
				error_msg('#msg-remove-exif-error');
				return;
			}
			selected_items().forEach(function(x){ x.classList.remove('selected') });
			update_selected_files();
		},
		error: function() {
			// 通常起きない
			error_msg('#msg-remove-exif-error');
		}
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●選択中ファイル一覧の取得
////////////////////////////////////////////////////////////////////////////////
function load_selected_files() {
	var sel = selected_items();
	if (!sel.length) return false;

	var files = [];
	for(var i=0; i<sel.length; i++) {
		files.push( fdata.get(sel[i]).title );
	}
	return files;
}

////////////////////////////////////////////////////////////////////////////////
// ●フォルダやファイルの削除
////////////////////////////////////////////////////////////////////////////////
function album_delete_files() {
	var trash = (cur_folder.substr(0,10) == '.trashbox/');
	var mode  = trash ? 'delete' : 'trash';

	adiary.confirm('#msg-confirm-'+mode+'-files', function(flag) {
		if (!flag) return;
		if (trash) {
			delete_files();
		} else {
			// ゴミ箱へ移動
			move_files('.trashbox/');
		}
	})
}
// ダイアログが出ているか（今までの$('div.ui-dialog').is(':visible')）
function dialog_visible() {
	return Array.from( document.querySelectorAll('div.ui-dialog') ).some(function(x){
		return x.offsetWidth || x.offsetHeight || x.getClientRects().length;
	});
}
document.addEventListener('keydown', function(evt) {
	if (key_event_stop) return;
	if (dialog_visible()) return;
	if (evt.keyCode != 46) return;

	var trash = (cur_folder.substr(0,10) == '.trashbox/');
	var mode  = trash ? 'delete' : 'trash';
	var files = load_selected_files();

	// ファイルの削除
	if (files.length) return album_delete_files()

	// ゴミ箱を空に？フォルダの削除
	if (cur_folder == '.trashbox/') return clear_trash();

	// フォルダの削除
	if (cur_folder != '/') adiary.confirm('#msg-confirm-'+mode+'-folder', function(flag) {
		if (!flag) return;
		if (trash) {
			delete_folder(cur_folder);
		} else {
			// ゴミ箱へ移動
			move_folder('.trashbox/', cur_node);
		}
	});
});

////////////////////////////////////////////////////////////////////////////////
// ●ファイルの移動
////////////////////////////////////////////////////////////////////////////////
function album_move_files() {
	folder_select_dialog( move_files );
}

//##############################################################################
// ■ファイルアップロード関連
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// ●ドラッグ＆ドロップ
////////////////////////////////////////////////////////////////////////////////
on(dnd_body, 'dragover', function(evt) {
	evt.preventDefault();
	evt.stopPropagation();
});
on(dnd_body, 'drop', function(evt) {
	if (!evt.dataTransfer) return;

	evt.stopPropagation();
	evt.preventDefault();
	var dnd_files = evt.dataTransfer.files;
	if (!dnd_files) return;
	if (uploading) return;

	var files = [];
	for(var i=0; i<dnd_files.length; i++)
		files.push( dnd_files[i] );

	// アップロード
	update_files_view(files)
	ajax_upload(files);
});

function update_files_view(files) {
	var div = $id('dnd-files');
	div.innerHTML = '';
	for(var i=0; i<files.length; i++) {
		if (!files[i]) continue;
		var fs  = adiary.size_format(files[i].size);
		var x   = document.createElement('div');
		x.textContent = files[i].name + ' (' + fs + ')';
		div.appendChild(x);
	}
}

////////////////////////////////////////////////////////////////////////////////
// ●<input type=file>が変更された
////////////////////////////////////////////////////////////////////////////////
on(file_btn, 'click', function (evt) {
	if (!uploading) return;
	evt.preventDefault();
	evt.stopPropagation();
});
on(file_btn, 'change', function (evt) {
	if (!file_btn.value) return;

	var files = file_btn.files;
	update_files_view(files)
	ajax_upload(files);

	// 選択クリア
	file_btn.value = '';
});

////////////////////////////////////////////////////////////////////////////////
// ●ファイルアップロード後の処理
////////////////////////////////////////////////////////////////////////////////
function upload_post_process(text) {
	update_files_view([]);		// アップファイル一覧消去

	var ary = text.split(/[\r\n]/);
	var ret = ary.shift();
	var reg = ret.match(/^ret=(\d*)/);
	// アップロードした動画（video=名前。名前はHTMLのエスケープ済み）
	var videos = [];
	ary = ary.filter(function(line){
		var m = line.match(/^video=(.+)$/);
		if (m) {
			var tmp = document.createElement('div');
			tmp.innerHTML = m[1];
			videos.push( tmp.textContent );
		}
		return !m;
	});
	if (reg) {
		ret = reg[0];
		message.innerHTML = ary.join("\n");
	} else {
		message.innerHTML = '<div class="message error">upload error : ' + adiary.tag_esc(ret) + '</div>';
	}
	adiary.show_delay(message);

	// アルバムツリーのリロード
	tree_reload();

	// 続けて動画のサムネイルを作る
	make_video_thumbnails(upfolder.value, videos);
}

////////////////////////////////////////////////////////////////////////////////
// ●ajaxでファイルアップロード
////////////////////////////////////////////////////////////////////////////////
function ajax_upload(files) {
	uploading = true;

	var fd = new FormData( upform );
	if (!file_btn.value) fd.delete('_file_btn');

	for(var i=0; i<files.length; i++) {
		if (!files[i]) continue;
		fd.append('file_ary', files[i]);
	}

	// progress message
	var label = create('span', 'label');
	var prog  = document.createElement('div');
	prog.appendChild( label );
	var bar = adiary.progressbar(prog, {
		value: 0,
		change: function(value) {
			label.textContent = "Uploading " + value + "%";
		},
		complete: function() {
			label.textContent = "Upload complete!";
		}
	});

	// submit処理（進み具合を出すので、XMLHttpRequestを使う）
	var xhr = new XMLHttpRequest();
	xhr.open('POST', upform.getAttribute('action'));
	xhr.upload.addEventListener('progress', function(e){
		var par = Math.floor(e.loaded*100/e.total + 0.5);
		bar.set(par);
	});
	var done = false;
	var end = function(ok){
		if (done) return;
		done = true;
		upload_post_process( ok ? xhr.responseText : (xhr.responseText || '') );
		uploading = false;
	};
	xhr.addEventListener('load', function(){
		end(200 <= xhr.status && xhr.status < 300 || xhr.status === 304);
	});
	xhr.addEventListener('error', function(){ end(false) });
	xhr.addEventListener('abort', function(){ end(false) });
	xhr.send(fd);

	adiary.hide(message);
	message.innerHTML = '';
	message.appendChild( prog );
	adiary.show_delay(message);

	return false;
}

////////////////////////////////////////////////////////////////////////////////
// ●リンクのエンコード
////////////////////////////////////////////////////////////////////////////////
function encode_link(str){
	return str.replace(/([%#"'?])/g, function (w,m1) {
		return '%' + m1.charCodeAt(0).toString(16);
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●移動先フォルダ選択メニュー
////////////////////////////////////////////////////////////////////////////////
function folder_select_dialog(callback) {
	var div = $id('move-dialog');

	div.innerHTML = '';
	var box = create('div', 'album-folder-tree');
	var stree = new AdiaryTree(box, {
		clickFolderMode: 1,	// activate only
		imagePath: text_of('icon-path'),
		children: dtree.toDict()
	});
	div.appendChild( box );

	var ok_func = function(){
		var node = stree.getActiveNode();
		if (!node || !node.data) return;
		var folder = node.data.key;
		if (folder == '') return;

		// callback
		if (!callback(folder)) {
			error_msg(folder == cur_folder ? '#msg-same-folder' : '#msg-illegal-folder');
			return;
		}
		adiary.dialog_close(div);
	};
	album_dialog(div, ok_func);
}

//##############################################################################
// ●アルバム用ダイアログの表示ルーチン
//##############################################################################
function album_dialog(div, ok_func) {
	var buttons = {};
	buttons[ div.dataset.ok ] = function(){
		ok_func();
		adiary.dialog_close(div);
	}
	buttons[ div.dataset.cancel ] = function(){
		adiary.dialog_close(div);
	};
	adiary.dialog(div, {
		modal: true,
		minWidth:  240,
		minHeight: 100,
		title: div.dataset.title,
		buttons: buttons,
	});
}

//##############################################################################
});
