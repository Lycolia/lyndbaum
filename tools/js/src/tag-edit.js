//##############################################################################
// タグ編集用JavaScript
//							(C)2013 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';
adiary.ready(function(){
	var form = adiary.secure('#form');
	var tree = adiary.secure('#tree');
	var join = document.getElementById('join-children');
	var del  = document.getElementById('delete');
	var submit = document.getElementById('submit');
	var reset  = document.getElementById('reset');
	var base_url = adiary.myself + '?&amp;t=';
	if (!tree) return;

	var select_node;
	var dels = [];
	var tag_priority_step = 10;

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
			if (select_node) {
				join.disabled = select_node.getChildren() ? false : true;
			}
		},
	},
	onPostInit: function(isReloading, isError) {
		if (isError) {
			join.disabled   = true;
			del.disabled    = true;
			submit.disabled = true;
			reset.disabled  = true;
			const err = document.getElementById('load-error');
			if (err) err.style.display = '';
			return;
		}
		var rootNode = dtree.getRoot();
		rootNode.visit(function(node){
			var par   = node.getParent();
			var path  = (par && par != rootNode) ? par.data.full + '::' : '';
			var data  = node.data;

			data.name = "" + data.title;
			data.full = path + data.title;
			data.href = base_url + encodeURIComponent( data.full );
			set_node_title(node);

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
		del.disabled  = false;
		join.disabled = node.getChildren() ? false : true;
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
// ●データからタイトルを設定
////////////////////////////////////////////////////////////////////////////////
function set_node_title(node) {
	var data  = node.data;
	var title = data.name + ' (' + data.qt + ')';
	data.title = title;
	node.setTitle( title );
}

////////////////////////////////////////////////////////////////////////////////
// ●タグの名称編集
////////////////////////////////////////////////////////////////////////////////
function editNode( node ) {
	// Disable dynatree mouse and key handling
	node.tree.disable();

	// Replace node with <input>
	var inp = document.createElement('input');
	inp.setAttribute('type',  'text');
	inp.setAttribute('value', adiary.tag_decode_amp(node.data.name));

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
	box.appendChild( inp );
	item.replaceWith( box );

	// Focus <input> and bind keyboard handler
	inp.focus();
	inp.select();
	inp.addEventListener('keydown', function(evt){
		switch( evt.which ) {
			case 27: // [esc]
				inp.blur();
				break;
			case 13: // [enter]
				var name = adiary.tag_esc_amp( inp.value );
				if (name.match(/^\s*$/)) {
					inp.blur();
					break;
				}
				if (name.match(/[,]|::/)) {
					adiary.show_error('#tag-name-error');
					break;
				}
				node.data.name = name;
				inp.blur();
				break;
		}
	});

	var tree_click = function(evt){
		if (inp == evt.target) return;
		inp.blur();
	};
	tree.addEventListener('click', tree_click);

	inp.addEventListener('blur', function(evt){
		tree.removeEventListener('click', tree_click);
		set_node_title(node);
		node.tree.enable();
		node.focus();
	});
}

////////////////////////////////////////////////////////////////////////////////
// ●タグの統合
////////////////////////////////////////////////////////////////////////////////
join.addEventListener('click', join_children);
function join_children(){
	var pkey = select_node.data.key;
	var ary  = select_node.data.joinkeys || [];
	join.disabled = true;

	var qt=0;
	function search_nodes(node) {
		var ch = node.getChildren();
		for(var i=ch.length-1; -1<i; i--) {	// removeのために逆回し
			ary.push(ch[i].data.key);
			if (ch[i].data.joinkeys) ary = ary.concat( ch[i].data.joinkeys );
			if (ch[i].getChildren()) search_nodes(ch[i]);
			qt += ch[i].data.qt;
			ch[i].remove();
		}
	}
	search_nodes(select_node);

	select_node.data.joinkeys = ary;
	select_node.data.qt      += qt;
	set_node_title( select_node );
}

////////////////////////////////////////////////////////////////////////////////
// ●タグの削除
////////////////////////////////////////////////////////////////////////////////
del.addEventListener('click', function(){
	if (select_node.getChildren()) join_children();

	var pkey = select_node.data.key;
	var ary  = select_node.data.joinkeys;
	dels.push(pkey);
	if (ary) dels = dels.concat(ary);

	select_node.remove();

	select_node = undefined;
	del.disabled = true;
});

////////////////////////////////////////////////////////////////////////////////
// ●送信前のデータ整形
////////////////////////////////////////////////////////////////////////////////
function hidden(name, value) {
	const inp = document.createElement('input');
	inp.setAttribute('type',  'hidden');
	inp.setAttribute('name',  name);
	inp.setAttribute('value', value);
	return inp;
}
form.addEventListener('submit', function(){
	var rootNode = dtree.getRoot();
	var div = adiary.secure('#div-in-form');
	div.innerHTML = '';

	// タグの削除
	for(var i=0; i<dels.length; i++) {
		div.appendChild( hidden('del_ary', dels[i]) );
	}

	// treeと順序の情報
	var cnt=0;
	function search_nodes(node, upnode) {
		var ch = node.getChildren();
		for(var i=0; i<ch.length; i++) {
			var data = ch[i].data;
			var val = data.key + ',' + upnode + ',' + cnt + ',' + data.name;
			cnt += tag_priority_step;
			div.appendChild( hidden('tag_ary', adiary.tag_decode_amp(val)) );
			// join情報
			if (data.joinkeys) {
				var ary = data.joinkeys;
				ary.unshift( data.key );
				div.appendChild( hidden('join_ary', ary.join(',')) );
			}
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

//##############################################################################
});
