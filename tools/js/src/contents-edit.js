//##############################################################################
// 固定ページの表示順の編集用JavaScript
//							(C)2013 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';
adiary.ready(function(){
	var form = adiary.secure('#form');
	var tree = document.getElementById('tree');
	var submit = document.getElementById('submit');
	var reset  = document.getElementById('reset');
	if (!tree) return;

	var select_node;
	var dels = [];
	var contents_priority_step = 10;

	var isMac = /Mac/.test(navigator.platform);
	var dtree;
////////////////////////////////////////////////////////////////////////////////
// ●初期化処理
////////////////////////////////////////////////////////////////////////////////
dtree = new AdiaryTree(tree, {
	url: tree.dataset.url,
	dnd: {
		onDragStart: function(node) {
			return true;	// Return false to cancel dragging of node.
		},
		autoExpandMS: 1000,
		preventVoidMoves: true, // Prevent dropping nodes 'before self', etc.
		onDragEnter: function(node, sourceNode) {
			 return true;
		},
		onDragOver: function(node, sourceNode, hitMode) {
			if(node.isDescendantOf(sourceNode))
				return false;
		        // Prohibit creating childs in non-folders (only sorting allowed)
			if( !node.data.isFolder && hitMode === "over" )
				return "after";
		},
		onDrop: function(node, sourceNode, hitMode) {
			sourceNode.move(node, hitMode);
			rebuild_link_key(sourceNode);	// 親が変わるとパーマリンクも変わる
		},
	},
	onPostInit: function(isReloading, isError) {
		if (isError) {
			submit.disabled = true;
			reset.disabled  = true;
			const err = document.getElementById('load-error');
			if (err) err.style.display = '';
			return;
		}
		var rootNode = dtree.getRoot();
		rootNode.visit(function(node){
			var data  = node.data;
			var elink_key = link_key_encode( data.link_key );
			data.href = adiary.myself2 + elink_key;
			node.setTitle( data.title );

			// ダブルタップで編集
			if (node.span) AdiaryTree.dbltap(node.span, function(evt) {
				editNode(node);
			});
			// ノードを開く
			node.expand(true);
		});
		// 最初の子は、まだ「Loading…」の行（読み込み後に消える）なので、ch[1] が最初のノード
		var ch = rootNode.getChildren();
		if (ch && ch.length>0) ch[1].activate();
		submit.disabled = false;
		reset.disabled  = false;
	},
	onActivate: function(node) {
		select_node = node;
	},
	// ノードの編集
	onClick: function(node, event) {
		if( event.shiftKey ) editNode(node);
		return true;
	},
	onDblClick: function(node, event) {
		editNode(node);
		return false;
	},
	onKeydown: function(node, event) {
		switch( event.which ) {
			case 113: // [F2]
				editNode(node);
				return false;
			case 13: // [enter]
				if( isMac ) editNode(node);
				return false;
		}
	}
});
////////////////////////////////////////////////////////////////////////////////
// ●リンクの動作を停止
////////////////////////////////////////////////////////////////////////////////
['click', 'dblclick'].forEach(function(type){
	tree.addEventListener(type, function(evt) {
		const a = evt.target.closest('a');
		if (a && tree.contains(a)) evt.preventDefault();
	});
});

////////////////////////////////////////////////////////////////////////////////
// ●ツリーを閉じる
////////////////////////////////////////////////////////////////////////////////
const close_btn = document.getElementById('close-button');
if (close_btn) close_btn.addEventListener('click', function(evt) {
	dtree.getRoot().visit(function(dtnode){
		dtnode.expand(false);
	});
});

////////////////////////////////////////////////////////////////////////////////
// ●パーマリンクは「親のパーマリンク/名前」
////////////////////////////////////////////////////////////////////////////////
// 名前はパーマリンクの最後の部分（/の後ろ）
function key_name(link_key) {
	return (link_key || '').replace(/^.*\//, '');
}
function parent_key(node) {
	var par = node.getParent();
	return par && par.data.link_key;	// 根のノードにはない
}
// ノードと子孫のパーマリンクとリンク先を、親に合わせて作り直す（保存するときはサーバーも作り直す）
function rebuild_link_key(node) {
	var pk = parent_key(node);
	var data = node.data;
	data.link_key = (pk ? pk + '/' : '') + key_name(data.link_key);
	data.href = adiary.myself2 + link_key_encode( data.link_key );
	node.setTitle( data.title );
	var ch = node.getChildren();
	if (ch) ch.forEach(rebuild_link_key);
}

////////////////////////////////////////////////////////////////////////////////
// ●パーマリンクの名前の編集
////////////////////////////////////////////////////////////////////////////////
function editNode( node ) {
	var link_key = node.data.link_key;
	var title = node.data.title;
	var pk    = parent_key(node);

	// Disable dynatree mouse and key handling
	node.tree.disable();

	// Replace node with <input>
	var inp = document.createElement('input');
	inp.setAttribute('type',  'text');
	inp.setAttribute('value', adiary.tag_decode(key_name(link_key)));

	// ノードの選択中表示を解除する
	var span = node.span;
	span.classList.remove('dynatree-active');

	// <a>タグが消える瞬間にイベントを拾ってしまうので対策
	var item = span.querySelector( ".dynatree-title" );	// aタグ
	item.removeAttribute('href');

	// aタグ内にinputを入れるとマウスクリックに対して
	// 不可思議な動作をするので、span に置き換える。
	var box = document.createElement('span');
	box.className = item.getAttribute('class');
	if (pk) box.appendChild( document.createTextNode(adiary.tag_decode(pk) + '/') );	// 親のパーマリンクは変えられない
	box.appendChild( inp );
	item.replaceWith( box );

	// Focus <input> and bind keyboard handler
	inp.focus();
	inp.addEventListener('keydown', function(evt){
		switch( evt.which ) {
			case 27: // [esc]
				inp.blur();
				break;
			case 13: // [enter]
				if (inp.value.indexOf('/') >= 0) {	// 親との間に階層を挟めない
					adiary.show_error('#name-error');
					break;
				}
				node.data.link_key = (pk ? pk + '/' : '') + inp.value;
				inp.blur();
				rebuild_link_key(node);
				break;
		}
	});

	var tree_click = function(evt){
		if (inp == evt.target) return;
		inp.blur();
	};
	// ダブルタップでは、編集を始めたclickがこの後treeに届くので、受け付けるのは次から
	var ended;
	setTimeout(function(){ if (!ended) tree.addEventListener('click', tree_click) }, 0);

	inp.addEventListener('blur', function(evt){
		ended = true;
		tree.removeEventListener('click', tree_click);
		node.setTitle(title);
		node.tree.enable();
		node.focus();
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●送信前のデータ整形
////////////////////////////////////////////////////////////////////////////////
form.addEventListener('submit', function(){
	var rootNode = dtree.getRoot();
	var div = adiary.secure('#div-in-form');
	div.innerHTML = '';

	// treeと順序の情報
	var cnt=contents_priority_step;
	function search_nodes(node, upnode) {
		var ch = node.getChildren();
		for(var i=0; i<ch.length; i++) {
			var data = ch[i].data;
			var val = data.key + ',' + upnode + ',' + cnt + ',' + key_name(data.link_key);	// 名前を送る
			cnt += contents_priority_step;
			var inp = document.createElement('input');
			inp.setAttribute('type',  'hidden');
			inp.setAttribute('name',  'contents_txt_ary');
			inp.setAttribute('value', val);
			div.appendChild(inp);
			// 再帰呼び出し
			if (ch[i].getChildren()) search_nodes(ch[i], data.key);
		}
	}
	search_nodes(rootNode, 0);

	return true;
});

////////////////////////////////////////////////////////////////////////////////
// ●キャンセル（リロード）
////////////////////////////////////////////////////////////////////////////////
reset.addEventListener('click', function(){
	dtree.reload();
});


////////////////////////////////////////////////////////////////////////////////
// ●link_keyのエンコード :: adiary.pmと同一の処理
////////////////////////////////////////////////////////////////////////////////
function link_key_encode(text) {
	if (typeof text != 'string') { return ''; }
	return text.replace(/[^^\w!\(\)\*\-\.\~\/:;=]/g, function(data) {
		return '%' + ('0' + data.charCodeAt().toString(16)).substr(-2);
	}).replace(/^\//, './/');
}

//##############################################################################
});
