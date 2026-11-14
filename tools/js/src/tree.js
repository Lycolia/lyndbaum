//##############################################################################
// ツリー（dynatree 1.2.5の代わり。jQueryを使わない）
//##############################################################################
//[TAB=8]
// dynatreeと同じ要素とクラスを作り、dynatreeのCSS（dynatree/skin/ui.dynatree.css）を
// そのまま使う。動きはdynatree 1.2.5のコードから、使っている所だけを写した。
//
//	const tree = new AdiaryTree(要素, {
//		url:		JSONのURL（[{ title, key, children: [...] }, ...]）
//		children:	urlの代わりに、ノードの配列から作る（tree.toDict()の値など）
//		autoFocus:	読み込んだ後に、最初のノードにfocusするか（既定はtrue）
//		persist:	選んだノード、開いたノードを覚えるか（既定はfalse）。adiary.Storageに、
//				cookieId + '-active'、'-focus'、'-expand'、'-select'の名前で書く（dynatreeと同じ）
//		cookieId:	覚えるときの名前
//		minExpandLevel:	この深さより浅いノードは、閉じられない（既定は1）
//		imagePath:	ノードのdata.iconの画像のディレクトリ
//		clickFolderMode: フォルダ（data.isFolder）を押したとき。3は開け閉めして選ぶ（既定）、1は選ぶだけ
//		onPostInit:	function(isReloading, isError)
//		onActivate:	function(node)
//		onClick:	function(node, evt)	falseで、選ぶのをやめる
//		onDblClick:	function(node, evt)
//		onKeydown:	function(node, evt)	falseで、キーの動きをやめる
//		dnd: {
//			onDragStart:	function(node)			falseでドラッグしない
//			onDragEnter:	function(node, srcNode)		trueで入れられる
//			onDragOver:	function(node, srcNode, hitMode) falseで入れない。"before"などで印の向きを変える
//			onDrop:		function(node, srcNode, hitMode)
//			autoExpandMS:	1000,
//			preventVoidMoves: true
//		}
//	});
//	tree.getRoot()、tree.getActiveNode()、tree.getNodeByKey(key)、tree.toDict()、
//	tree.reload()、tree.disable()、tree.enable()
//	tree.externalDrag(写しの要素)	… ツリーの外の要素のドラッグを、ノードに落とせるようにする（下の説明）
//	AdiaryTree.dbltap(要素, func)	… タッチのダブルタップ（今までのasysのmydbltapと同じ判定）
//
'use strict';
(function(){
////////////////////////////////////////////////////////////////////////////////
// ●クラス名など（dynatreeと同じ）
////////////////////////////////////////////////////////////////////////////////
const CN = {
	container:	'dynatree-container',
	noConnector:	'dynatree-no-connector',
	node:		'dynatree-node',
	folder:		'dynatree-folder',
	expanded:	'dynatree-expanded',
	hasChildren:	'dynatree-has-children',
	lastsib:	'dynatree-lastsib',
	active:		'dynatree-active',
	focused:	'dynatree-focused',
	expander:	'dynatree-expander',
	connector:	'dynatree-connector',
	nodeIcon:	'dynatree-icon',
	title:		'dynatree-title',
	expPrefix:	'dynatree-exp-',
	icoPrefix:	'dynatree-ico-',
	nodeError:	'dynatree-statusnode-error',
	nodeWait:	'dynatree-statusnode-wait'
};
const STR = {
	loading:	'Loading&#8230;',
	loadError:	'Load error!'
};
const TouchDnDTime  = 100;	// msec（asysの$$.TouchDnDTimeと同じ）
const DoubleTapTime = 400;	// msec（asysの$$.DoubleTapTimeと同じ）

function get_node(el) {
	while(el) {
		if (el.dtnode) return el.dtnode;
		el = el.parentNode;
	}
	return null;
}
// jQueryの.offset()、.height()
function offset_of(el) {
	const r = el.getBoundingClientRect();
	return { top: r.top + window.pageYOffset, left: r.left + window.pageXOffset };
}
function height_of(el) {
	const cs = getComputedStyle(el);
	let h = parseFloat(cs.height);
	if (isNaN(h)) return el.offsetHeight;
	if (cs.boxSizing === 'border-box')
		h -= (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0)
		   + (parseFloat(cs.borderTopWidth) || 0) + (parseFloat(cs.borderBottomWidth) || 0);
	return h;
}

////////////////////////////////////////////////////////////////////////////////
// ●ノード
////////////////////////////////////////////////////////////////////////////////
function Node(parent, tree, data) {
	this.parent = parent;
	this.tree   = tree;
	if (typeof(data) === 'string') data = { title: data };
	data.key  = (data.key === null || data.key === undefined) ? '_' + tree._nodeCount++ : '' + data.key;
	this.data = Object.assign({ title: null, key: null, isFolder: false, href: null, addClass: null }, data);
	this.li   = null;
	this.span = null;
	this.ul   = null;
	this.childList = null;
	this.bExpanded = false;
}
Node.prototype = {
	isStatusNode:	function(){ return this.data.isStatusNode === true },
	getParent:	function(){ return this.parent },
	hasChildren:	function(){ return !!this.childList },
	getChildren:	function(){ return this.childList },
	isLastSibling:	function(){
		const p = this.parent;
		return !p || p.childList[p.childList.length-1] === this;
	},
	getPrevSibling:	function(){
		if (!this.parent) return null;
		const ac = this.parent.childList;
		for(let i=1; i<ac.length; i++) if (ac[i] === this) return ac[i-1];
		return null;
	},
	getNextSibling:	function(){
		if (!this.parent) return null;
		const ac = this.parent.childList;
		for(let i=0; i<ac.length-1; i++) if (ac[i] === this) return ac[i+1];
		return null;
	},
	isDescendantOf:	function(node){
		if (!node) return false;
		for(let p=this.parent; p; p=p.parent) if (p === node) return true;
		return false;
	},
	getLevel:	function(){
		let n = 0;
		for(let p=this.parent; p; p=p.parent) n++;
		return n;
	},
	_parentList:	function(includeRoot, includeSelf){
		const ary = [];
		for(let p = includeSelf ? this : this.parent; p; p=p.parent)
			if (includeRoot || p.parent) ary.unshift(p);
		return ary;
	},
	// ノードのデータを、childrenと、選んでいるか、開いているかを付けて返す（dynatreeと同じ）
	toDict:		function(recursive){
		const d = Object.assign({}, this.data);
		d.activate = this.tree.activeNode === this;
		d.focus    = this.tree.focusNode  === this;
		d.expand   = this.bExpanded;
		d.select   = false;
		if (recursive && this.childList) {
			d.children = [];
			for(const c of this.childList) if (!c.isStatusNode()) d.children.push(c.toDict(true));
		} else	delete d.children;
		return d;
	},
	visit:		function(fn, includeSelf){
		let r = true;
		if (includeSelf === true) {
			r = fn(this);
			if (r === false || r === 'skip') return r;
		}
		if (this.childList)
			for(let i=0; i<this.childList.length; i++) {
				r = this.childList[i].visit(fn, true);
				if (r === false) break;
			}
		return r;
	},

	//----------------------------------------------------------------------
	// 表示
	//----------------------------------------------------------------------
	_getInnerHtml: function(){
		const d   = this.data;
		const opt = this.tree.options;
		const lv  = this.getLevel();
		let html  = '';
		if (opt.minExpandLevel > lv) {	// 閉じられないノードは、開閉の印を出さない
			if (lv > 1) html += "<span class='" + CN.connector + "'></span>";
		} else
			html += this.hasChildren() !== false
				? "<span class='" + CN.expander  + "'></span>"
				: "<span class='" + CN.connector + "'></span>";
		if (d.icon) {
			const src = d.icon.charAt(0) === '/' ? d.icon : opt.imagePath + d.icon;
			html += "<img src='" + src + "' alt='' />";
		} else if (d.icon !== false)
			html += d.iconClass ? "<span class=' " + d.iconClass + "'></span>" : "<span class='" + CN.nodeIcon + "'></span>";
		const tip = d.tooltip ? ' title="' + d.tooltip.replace(/"/g, '&quot;') + '"' : '';
		html += '<a href="' + (d.href || '#') + '" class="' + CN.title + '"' + tip + '>' + d.title + '</a>';
		return html;
	},
	render: function(useEffects, includeInvisible){
		const tree = this.tree;
		const par  = this.parent;
		const d    = this.data;
		const last = this.isLastSibling();
		if (par || this.ul) {
			if (par) {
				if (!this.li) {
					this.li = document.createElement('li');
					this.li.dtnode = this;
					this.span = document.createElement('span');
					this.span.className = CN.title;
					this.li.appendChild(this.span);
					if (!par.ul) {
						par.ul = document.createElement('ul');
						par.ul.style.display = 'none';
						par.li.appendChild(par.ul);
					}
					par.ul.appendChild(this.li);
				}
				this.span.innerHTML = this._getInnerHtml();
				const cls = [CN.node];
				if (d.isFolder)				cls.push(CN.folder);
				if (this.bExpanded)			cls.push(CN.expanded);
				if (this.hasChildren() !== false)	cls.push(CN.hasChildren);
				if (last)				cls.push(CN.lastsib);
				if (tree.activeNode === this)		cls.push(CN.active);
				if (d.addClass)				cls.push(d.addClass);
				cls.push(CN.expPrefix + (this.bExpanded ? 'e' : 'c') + (last ? 'l' : ''));
				cls.push(CN.icoPrefix + (this.bExpanded ? 'e' : 'c') + (d.isFolder ? 'f' : ''));
				this.span.className = cls.join(' ');
				this.li.className   = last ? CN.lastsib : '';
			}
		} else {
			this.li = this.span = null;
			this.ul = document.createElement('ul');
			this.ul.className = tree.options.minExpandLevel > 1 ? CN.container + ' ' + CN.noConnector : CN.container;
		}
		if ((this.bExpanded || includeInvisible === true) && this.childList) {
			for(const c of this.childList) c.render(false, includeInvisible);
			this._fixOrder();
		}
		if (this.ul) this.ul.style.display = (this.bExpanded || !par) ? '' : 'none';
	},
	_fixOrder: function(){
		const ac = this.childList;
		if (!ac || !this.ul) return;
		let li = this.ul.firstChild;
		for(let i=0; i<ac.length-1; i++) {
			const n = ac[i];
			const m = li.dtnode;
			if (n !== m) this.ul.insertBefore(n.li, m.li);
				else li = li.nextSibling;
		}
	},
	setTitle: function(title){
		this.data.title = title;
		this.render();
	},

	//----------------------------------------------------------------------
	// 子
	//----------------------------------------------------------------------
	// ノードのデータの配列か、1つのデータを足す。足した（最初の）ノードを返す
	addChild: function(ary){
		if (!ary || ary.length === 0) return;
		if (!Array.isArray(ary)) ary = [ ary ];
		// 作り終えてから表示する（dynatreeのenableUpdate(false)と同じ）
		const tree   = this.tree;
		const update = tree._enableUpdate(false);
		let first = null;
		for(const data of ary) {
			const node = this._addChildNode( new Node(this, tree, Object.assign({}, data)) );
			if (!first) first = node;
			if (data.children) node.addChild(data.children);
		}
		tree._enableUpdate(update);
		return first;
	},
	_addChildNode: function(node){
		const tree = this.tree;
		const opt  = tree.options;
		const ps   = tree.persistence;
		if (this.childList === null) this.childList = [];
		else if (this.childList.length && this.childList[this.childList.length-1].span)
			this.childList[this.childList.length-1].span.classList.remove(CN.lastsib);
		this.childList.push(node);

		const d = node.data;
		if (opt.persist && ps.cookiesFound && tree._isInitializing()) {
			// 読み込みの時は、覚えていたノードを選び、開く
			if (ps.activeKey  === d.key) tree.activeNode = node;
			if (ps.focusedKey === d.key) tree.focusNode  = node;
			node.bExpanded = ps.expandedKeyList.indexOf(d.key) >= 0;
		} else {
			if (d.activate) {
				tree.activeNode = node;
				if (opt.persist) ps.activeKey = d.key;
			}
			if (d.focus) {
				tree.focusNode = node;
				if (opt.persist) ps.focusedKey = d.key;
			}
			node.bExpanded = d.expand === true;
			if (node.bExpanded && opt.persist) ps.addExpand(d.key);
		}
		if (opt.minExpandLevel >= node.getLevel()) this.bExpanded = true;
		if (tree.bEnableUpdate) this.render();
		return node;
	},
	removeChild: function(node){
		const ac = this.childList;
		if (ac.length === 1) return this.removeChildren();
		if (node === this.tree.activeNode) node.deactivate();
		node.removeChildren(true);
		if (this.ul && node.li) this.ul.removeChild(node.li);
		ac.splice(ac.indexOf(node), 1);
	},
	removeChildren: function(isRecursiveCall){
		const tree = this.tree;
		const ac   = this.childList;
		if (ac) {
			for(const c of ac) {
				if (c === tree.activeNode) c.deactivate();
				c.removeChildren(true);
				if (this.ul && c.li) this.ul.querySelectorAll('li').forEach(function(x){ x.remove() });
			}
			this.childList = null;
		}
		if (!isRecursiveCall) this.render();
	},
	remove: function(){
		return this.parent.removeChild(this);
	},
	// modeは"before"、"after"、"over"（子にする）
	move: function(target, mode){
		if (this === target) return;
		if (mode === undefined || mode === 'over') mode = 'child';
		const prev = this.parent;
		const par  = (mode === 'child') ? target : target.parent;
		if (par.isDescendantOf(this)) throw "Cannot move a node to it's own descendant";

		if (this.parent.childList.length === 1) {
			this.parent.childList = null;
			this.parent.bExpanded = false;
		} else {
			this.parent.childList.splice(this.parent.childList.indexOf(this), 1);
		}
		if (this.parent.ul) this.parent.ul.removeChild(this.li);
		this.parent = par;
		if (par.hasChildren()) {
			if (mode === 'child')	par.childList.push(this);
			else {
				const i = par.childList.indexOf(target);
				par.childList.splice(mode === 'before' ? i : i+1, 0, this);
			}
		} else	par.childList = [this];
		if (!par.ul) {
			par.ul = document.createElement('ul');
			par.ul.style.display = 'none';
			par.li.appendChild(par.ul);
		}
		if (this.li) par.ul.appendChild(this.li);
		if (!prev.isDescendantOf(par)) prev.render();
		if (!par.isDescendantOf(prev)) par.render();
	},

	//----------------------------------------------------------------------
	// 開け閉め、選ぶ、focus
	//----------------------------------------------------------------------
	_expand: function(flag){
		if (this.bExpanded === flag) return;
		const opt = this.tree.options;
		if (!flag && this.getLevel() < opt.minExpandLevel) return;	// 閉じられない
		this.bExpanded = flag;
		if (opt.persist) {
			if (flag) this.tree.persistence.addExpand(this.data.key);
			     else this.tree.persistence.clearExpand(this.data.key);
		}
		this.render(true);
		// activeVisible
		const act = this.tree.activeNode;
		if (act && !act.isVisible()) act.deactivate();
	},
	expand: function(flag){
		flag = flag !== false;
		if (!this.childList && flag) return;
		if (this.parent === null && !flag) return;
		this._expand(flag);
	},
	toggleExpand: function(){ this.expand(!this.bExpanded) },
	isVisible: function(){
		for(const p of this._parentList(true, false)) if (!p.bExpanded) return false;
		return true;
	},
	makeVisible: function(){
		for(const p of this._parentList(true, false)) p._expand(true);
	},
	focus: function(){
		this.makeVisible();
		const a = this.span && this.span.querySelector(':scope > a');
		if (a) a.focus();
	},
	activate:	  function(){ this._activate(true) },
	activateSilently: function(){ this._activate(false) },	// onActivateを呼ばない
	_activate: function(callback){
		const tree = this.tree;
		const opt  = tree.options;
		if (this.isStatusNode()) return;
		if (tree.activeNode) {
			if (tree.activeNode === this) return;
			tree.activeNode.deactivate();
		}
		this.makeVisible();
		tree.activeNode = this;
		if (opt.persist) tree._persist_set('-active', this.data.key);
		tree.persistence.activeKey = this.data.key;
		if (this.span) this.span.classList.add(CN.active);
		if (callback && opt.onActivate) opt.onActivate.call(tree, this);
	},
	deactivate: function(){
		const tree = this.tree;
		if (tree.activeNode !== this) return;
		if (this.span) this.span.classList.remove(CN.active);
		if (tree.options.persist) tree._persist_set('-active', '');
		tree.persistence.activeKey = null;
		tree.activeNode = null;
	},
	// クリックやspaceで選ぶ（フォルダはclickFolderModeによる）
	_userActivate: function(){
		let act = true;
		let exp = false;
		if (this.data.isFolder) switch(this.tree.options.clickFolderMode) {
			case 2: act = false; exp = true; break;
			case 3: act = exp = true;
		}
		if (this.parent === null) exp = false;
		if (exp) {
			this.toggleExpand();
			this.focus();
		}
		if (act) this.activate();
	},
	isActive: function(){ return this.tree.activeNode === this },

	//----------------------------------------------------------------------
	// イベント
	//----------------------------------------------------------------------
	_targetType: function(evt){
		const cls = evt && evt.target && typeof(evt.target.className) === 'string' ? evt.target.className : '';
		if (cls.indexOf(CN.title)    >= 0) return 'title';
		if (cls.indexOf(CN.expander) >= 0) return 'expander';
		if (cls.indexOf(CN.nodeIcon) >= 0) return 'icon';
		if (cls.indexOf(CN.connector)>= 0) return 'prefix';
		if (cls.indexOf(CN.node)     >= 0) return this._outerType(evt);
		return null;
	},
	_outerType: function(evt){	// spanの余白を押したとき（dynatreeと同じく、位置で決める）
		const el = evt.target;
		const x  = evt.pageX - el.offsetLeft;
		const y  = evt.pageY - el.offsetTop;
		for(const c of el.childNodes) {
			const l = c.offsetLeft - el.offsetLeft;
			const t = c.offsetTop  - el.offsetTop;
			if (x>=l && l+c.clientWidth>=x && y>=t && t+c.clientHeight>=y) {
				if (c.className == CN.title)    return 'title';
				if (c.className == CN.expander) return 'expander';
				if (c.className == CN.nodeIcon) return 'icon';
			}
		}
		return 'prefix';
	},
	_onClick: function(evt){
		if (this._targetType(evt) === 'expander') {
			this.toggleExpand();
			this.focus();
		} else {
			this._userActivate();
			const a = this.span.getElementsByTagName('a');
			if (!a[0]) return true;
			a[0].focus();
		}
		evt.preventDefault();
	},
	_onKeydown: function(evt){
		let sib;
		let handled = true;
		switch(evt.which || evt.keyCode) {
		case 107: case 187:	// +
			if (!this.bExpanded) this.toggleExpand();
			break;
		case 109: case 189:	// -
			if (this.bExpanded) this.toggleExpand();
			break;
		case 32:		// space
			this._userActivate();
			break;
		case 8:			// backspace
			if (this.parent) this.parent.focus();
			break;
		case 37:		// ←
			if (this.bExpanded) {
				this.toggleExpand();
				this.focus();
			} else if (this.parent && this.parent.parent) {
				this.parent.focus();
			}
			break;
		case 39:		// →
			if (!this.bExpanded && this.childList) {
				this.toggleExpand();
				this.focus();
			} else if (this.childList) {
				this.childList[0].focus();
			}
			break;
		case 38:		// ↑
			for(sib = this.getPrevSibling(); sib && sib.bExpanded && sib.childList; )
				sib = sib.childList[sib.childList.length-1];
			if (!sib && this.parent && this.parent.parent) sib = this.parent;
			if (sib) sib.focus();
			break;
		case 40:		// ↓
			if (this.bExpanded && this.childList) {
				sib = this.childList[0];
			} else {
				const ps = this._parentList(false, true);
				for(let i=ps.length-1; i>=0; i--) {
					sib = ps[i].getNextSibling();
					if (sib) break;
				}
			}
			if (sib) sib.focus();
			break;
		default:
			handled = false;
		}
		if (handled) evt.preventDefault();
	},
	_onFocus: function(evt){
		const tree = this.tree;
		if (evt.type === 'blur' || evt.type === 'focusout') {
			if (tree.tnFocused && tree.tnFocused.span) tree.tnFocused.span.classList.remove(CN.focused);
			tree.tnFocused = null;
			if (tree.options.persist) tree._persist_set('-focus', '');
		} else {
			if (tree.tnFocused && tree.tnFocused !== this && tree.tnFocused.span)
				tree.tnFocused.span.classList.remove(CN.focused);
			tree.tnFocused = this;
			if (this.span) this.span.classList.add(CN.focused);
			if (tree.options.persist) tree._persist_set('-focus', this.data.key);
		}
	}
};

////////////////////////////////////////////////////////////////////////////////
// ●覚えておく値（dynatreeのDynaTreeStatusと同じ。$.cookieの代わりにadiary.Storage）
////////////////////////////////////////////////////////////////////////////////
function storage() {
	return window.adiary && window.adiary.Storage;
}
function Persistence(id) {
	this.cookieId     = id;
	this.cookiesFound = undefined;
	this.activeKey    = null;
	this.focusedKey   = null;
	this.expandedKeyList = null;
	this.selectedKeyList = null;
}
Persistence.prototype = {
	_get: function(name){
		const ls = storage();
		return ls ? ls.get(this.cookieId + name) : undefined;
	},
	_set: function(name, val){
		const ls = storage();
		if (ls) ls.set(this.cookieId + name, val);
	},
	read: function(){
		this.cookiesFound = false;
		let v = this._get('-active');
		this.activeKey = v || '';
		if (v) this.cookiesFound = true;
		v = this._get('-focus');
		this.focusedKey = v || '';
		if (v) this.cookiesFound = true;
		v = this._get('-expand');
		this.expandedKeyList = v ? v.split(',') : [];
		if (v) this.cookiesFound = true;
		v = this._get('-select');
		this.selectedKeyList = v ? v.split(',') : [];
		if (v) this.cookiesFound = true;
	},
	write: function(){
		this._set('-active', this.activeKey  === null ? '' : this.activeKey);
		this._set('-focus',  this.focusedKey === null ? '' : this.focusedKey);
		this._set('-expand', this.expandedKeyList === null ? '' : this.expandedKeyList.join(','));
		this._set('-select', this.selectedKeyList === null ? '' : this.selectedKeyList.join(','));
	},
	addExpand: function(key){
		if (this.expandedKeyList.indexOf(key) >= 0) return;
		this.expandedKeyList.push(key);
		this._set('-expand', this.expandedKeyList.join(','));
	},
	clearExpand: function(key){
		const i = this.expandedKeyList.indexOf(key);
		if (i < 0) return;
		this.expandedKeyList.splice(i, 1);
		this._set('-expand', this.expandedKeyList.join(','));
	},
	isReloading: function(){
		return this.cookiesFound === true;
	}
};

////////////////////////////////////////////////////////////////////////////////
// ●木
////////////////////////////////////////////////////////////////////////////////
function AdiaryTree(dom, opt) {
	this.div     = dom;
	this.options = Object.assign({
		autoFocus:	true,
		persist:	false,
		cookieId:	'dynatree',
		minExpandLevel:	1,
		imagePath:	'',
		clickFolderMode: 3
	}, opt || {});
	if (this.options.minExpandLevel < 1) this.options.minExpandLevel = 1;
	this.dnd     = Object.assign({ autoExpandMS: 1000, preventVoidMoves: true }, this.options.dnd || {});
	this.enabled = true;
	this.phase   = 'init';
	this._bind();
	if (this.options.dnd) this._init_dnd();
	this._load();
}
AdiaryTree.prototype = {
	getRoot:	function(){ return this.tnRoot },
	getActiveNode:	function(){ return this.activeNode },
	reload:		function(){ this._load() },
	visit:		function(fn, includeSelf){ return this.tnRoot.visit(fn, includeSelf) },
	getNodeByKey:	function(key){
		let node = null;
		this.visit(function(n){
			if (n.data.key === key) { node = n; return false; }
		}, true);
		return node;
	},
	// ノードのデータの配列（childrenの形）。new AdiaryTree()のchildrenに渡せる
	toDict:		function(includeRoot){
		const d = this.tnRoot.toDict(true);
		return includeRoot ? d : d.children;
	},
	// 名前を編集する間などに、クリックとキーを止める（今までの$widget.unbind()、bind()。ドラッグは止めない）
	disable:	function(){ this.enabled = false },
	enable:		function(){ this.enabled = true  },

	_isInitializing: function(){ return this.phase === 'init' || this.phase === 'postInit' },
	_enableUpdate: function(flag){	// 前の値を返す
		if (this.bEnableUpdate === flag) return flag;
		this.bEnableUpdate = flag;
		if (flag) this.tnRoot.render();
		return !flag;
	},
	_persist_set: function(name, val){
		this.persistence._set(name, val);
	},

	//----------------------------------------------------------------------
	// 読み込み（dynatreeの_load、_reloadAjax、appendAjaxと同じ順に動かす）
	//----------------------------------------------------------------------
	_load: function(){
		const opt  = this.options;
		this.phase = 'init';
		this.bEnableUpdate = true;
		this._nodeCount = 1;
		this.activeNode = null;
		this.focusNode  = null;
		this.tnFocused  = null;
		this.persistence = new Persistence(opt.cookieId);
		if (opt.persist) this.persistence.read();

		this.div.innerHTML = '';
		this.tnRoot = new Node(null, this, {});
		this.tnRoot.bExpanded = true;
		this.tnRoot.render();
		this.div.appendChild(this.tnRoot.ul);

		const isReloading = opt.persist && this.persistence.isReloading();
		const update = this._enableUpdate(false);
		let ajax = false;
		if (opt.children) {
			this.tnRoot.addChild(opt.children);
		} else if (opt.url) {
			ajax = true;
			this._loadAjax();
		}
		this._enableUpdate(update);
		this.phase = 'postInit';
		if (opt.persist) this.persistence.write();
		if (this.focusNode && this.focusNode.isVisible()) this.focusNode.focus();
		if (!ajax && opt.onPostInit) opt.onPostInit.call(this, isReloading, false);
		this.phase = 'idle';
	},
	_loadAjax: function(){
		const self = this;
		const opt  = this.options;
		const root = this.tnRoot;
		const isReloading = this.persistence.isReloading();

		// 読み込み中の行（読み終わるまで、最初の子にある）
		root.removeChildren(false);
		this._setStatus({ title: STR.loading, addClass: CN.nodeWait });

		fetch(opt.url, { cache: 'no-store' }).then(function(res){
			if (!res.ok) throw res.statusText || String(res.status);
			return res.json();
		}).then(function(data){
			const prev = self.phase;
			const empty = Array.isArray(data) && data.length === 0;
			self.phase = 'init';
			if (!empty) root.addChild(data);
			self.phase = 'postInit';
			if (opt.onPostInit) opt.onPostInit.call(self, isReloading, false);
			self.phase = prev;
			// 読み込み中の行を消し、最初のノードにfocus（autoFocus）
			self._setStatus(null);
			if (empty) {
				root.childList = [];
				root.render();
			}
			if (opt.autoFocus && root.childList && root.childList.length) root.childList[0].focus();
		}, function(e){
			if (opt.onPostInit) opt.onPostInit.call(self, isReloading, true);
			// 今までと同じく、HTTPの状態の文言（Not Foundなど）をtitleに出す
			const tip = typeof(e) === 'string' ? e : (e && e.message) || '';
			self._setStatus({ title: STR.loadError + ' (error)', tooltip: tip || null, addClass: CN.nodeError });
		});
	},
	_setStatus: function(data){
		const root = this.tnRoot;
		const first = root.childList ? root.childList[0] : null;
		if (data) {
			data.isStatusNode = true;
			data.key = '_statusNode';
			if (first && first.isStatusNode()) {
				first.data = Object.assign(first.data, data);
				first.render();
			} else {
				const node = new Node(root, this, data);
				if (root.childList === null) root.childList = [];
				root.childList.unshift(node);
				root.render();
			}
			return;
		}
		if (first && first.isStatusNode()) {
			if (root.ul && first.li) root.ul.removeChild(first.li);
			first.li = null;
			if (root.childList.length === 1) root.childList = [];
				else root.childList.shift();
		}
	},

	//----------------------------------------------------------------------
	// クリック、ダブルクリック、キー、focus
	//----------------------------------------------------------------------
	_bind: function(){
		const self = this;
		const opt  = this.options;
		const handler = function(evt){
			if (!self.enabled) return;
			const node = get_node(evt.target);
			if (!node || node.tree !== self) return;
			let ret;
			const phase = self.phase;
			self.phase = 'userEvent';
			switch(evt.type) {
			case 'click':
				ret = (opt.onClick && opt.onClick.call(self, node, evt) === false) ? false : node._onClick(evt);
				break;
			case 'dblclick':
				ret = (opt.onDblClick && opt.onDblClick.call(self, node, evt) === false) ? false : undefined;
				break;
			case 'keydown':
				ret = (opt.onKeydown && opt.onKeydown.call(self, node, evt) === false) ? false : node._onKeydown(evt);
				break;
			}
			self.phase = phase;
			if (ret === false) {	// jQueryと同じく、falseは止める
				evt.preventDefault();
				evt.stopPropagation();
			}
		};
		['click', 'dblclick', 'keydown'].forEach(function(t){ self.div.addEventListener(t, handler) });
		const focus = function(evt){
			const node = get_node(evt.target);
			if (node && node.tree === self) node._onFocus(evt);
		};
		this.div.addEventListener('focus', focus, true);
		this.div.addEventListener('blur',  focus, true);
	},

	//----------------------------------------------------------------------
	// ドラッグ
	//----------------------------------------------------------------------
	// ドラッグの間の状態stは{ src, helper, target, enter, hitMode }。
	// srcはつかんだノード（ツリーの外からのドラッグではnull）
	//
	// ツリーの外の要素のドラッグ（今までのjQuery UIのdraggableのconnectToDynatreeと同じ）:
	//	const ext = tree.externalDrag(写しの要素);
	//	ext.move(マウスの下の要素, pageX, pageY);	… 動かすたびに
	//	ext.stop(落としたか);				… 離したとき。dnd.onDrop(node, null, hitMode)を呼ぶ
	//	写しの要素には、dynatree-drop-accept、dynatree-drop-rejectが付く
	externalDrag: function(helper){
		const self = this;
		const st   = { src: null, helper: helper, target: null };
		return {
			move: function(target, x, y){ self._dnd_move(st, target, x, y) },
			stop: function(dropped){ self._dnd_stop(st, dropped) }
		};
	},
	// マウスの下のノードに、入る・上にいる・離れるを伝える
	_dnd_move: function(st, target, x, y){
		const node = get_node(target);
		if (target && !node && target.closest && target.closest('div.dynatree-drag-helper,#dynatree-drop-marker')) return;
		const prev = st.target;
		st.target = (node && node.tree === this) ? node : null;
		if (prev && prev !== st.target) this._dnd_leave(st, prev);
		if (st.target && this.dnd.onDrop) {
			if (st.target === prev) this._dnd_over(st, st.target, x, y);
				else this._dnd_enter(st, st.target);
		}
	},
	_dnd_stop: function(st, dropped){
		const t = st.target;
		if (!t) return;
		if (dropped) {
			const reject = st.helper.classList.contains('dynatree-drop-reject');
			if (st.hitMode && this.dnd.onDrop && !reject) this.dnd.onDrop(t, st.src, st.hitMode);
		}
		this._dnd_leave(st, t);
	},
	_dnd_enter: function(st, node){
		const d = this.dnd.onDragEnter ? this.dnd.onDragEnter(node, st.src) : null;
		if (!d) st.enter = false;
		else if (Array.isArray(d)) st.enter = { over: d.indexOf('over')>=0, before: d.indexOf('before')>=0, after: d.indexOf('after')>=0 };
		else st.enter = { over: d===true || d==='over', before: d===true || d==='before', after: d===true || d==='after' };
	},
	_dnd_over: function(st, node, x, y){
		const d   = this.dnd;
		const src = st.src;
		const o   = st.enter;
		let mode  = null;
		let ret   = null;
		if (o === false) {
			// 入れられない
		} else if (typeof(o) === 'string') {
			mode = o;
		} else {
			const p = offset_of(node.span);
			const g = (y - p.top) / height_of(node.span);
			if      (o.after  && g > .75)		mode = 'after';
			else if (!o.over  && o.after && g > .5)	mode = 'after';
			else if (o.before && .25 >= g)		mode = 'before';
			else if (!o.over  && o.before && .5 >= g) mode = 'before';
			else if (o.over)			mode = 'over';
			if (d.preventVoidMoves) {
				if (node === src) mode = null;
				else if (mode === 'before' && src && node === src.getNextSibling()) mode = null;
				else if (mode === 'after'  && src && node === src.getPrevSibling()) mode = null;
				else if (mode === 'over'   && src && src.parent === node && src.isLastSibling()) mode = null;
			}
			// 落としたときは、この値（下のonDragOverが直す前）を使う。今までのdynatreeと同じ
			st.hitMode = mode;
		}
		if (mode === 'over' && d.autoExpandMS && node.hasChildren() !== false && !node.bExpanded) this._dnd_schedule(node);
		if (mode && d.onDragOver) {
			ret = d.onDragOver(node, src, mode);
			if (ret === 'over' || ret === 'before' || ret === 'after') mode = ret;
		}
		this._dnd_status(st, node, mode, ret !== false && mode !== null);
	},
	_dnd_leave: function(st, node){
		this._dnd_schedule(null);
		st.enter   = null;
		st.hitMode = null;
		this._dnd_status(st, node, 'out', undefined);
	},
	_dnd_schedule: function(node){	// 閉じたノードの上で待つと開く
		if (this.timer) clearTimeout(this.timer);
		this.timer = null;
		if (node) this.timer = setTimeout(function(){ node.expand(true) }, this.dnd.autoExpandMS);
	},
	_dnd_status: function(st, node, mode, accept){
		const r = st.src ? st.src.span : null;
		const o = node.span;
		const h = st.helper;
		const div = this.div;
		let m = this.marker;
		if (!m) {
			m = this.marker = document.createElement('div');
			m.id = 'dynatree-drop-marker';
			m.style.zIndex  = 1000;
			m.style.display = 'none';
			div.parentNode.insertBefore(m, div.parentNode.firstChild);
		}
		if (mode === 'after' || mode === 'before' || mode === 'over') {
			let at = 'center';
			let dx = 0;
			m.classList.remove('dynatree-drop-before', 'dynatree-drop-after', 'dynatree-drop-over');
			if (mode === 'before') { m.classList.add('dynatree-drop-before'); at = 'top'; }
			else if (mode === 'after') { m.classList.add('dynatree-drop-after'); at = 'bottom'; }
			else { m.classList.add('dynatree-drop-over'); o.classList.add('dynatree-drop-target'); dx = 8; }
			// 印の左をspanの左（overは右へ8px）、印の縦の中央をspanの上端・下端・中央に合わせる
			m.style.display = '';
			const sr = o.getBoundingClientRect();
			const ay = at === 'top' ? sr.top : (at === 'bottom' ? sr.bottom : sr.top + sr.height/2);
			m.style.top  = '0px';
			m.style.left = '0px';
			const mr = m.getBoundingClientRect();
			m.style.top  = (ay - mr.height/2 - mr.top) + 'px';
			m.style.left = (sr.left + dx - mr.left) + 'px';
		} else {
			o.classList.remove('dynatree-drop-target');
			m.style.display = 'none';
		}
		o.classList.toggle('dynatree-drop-after',  mode === 'after');
		o.classList.toggle('dynatree-drop-before', mode === 'before');
		for(const x of [r, o, h]) {
			if (!x) continue;
			x.classList.toggle('dynatree-drop-accept', accept === true);
			x.classList.toggle('dynatree-drop-reject', accept === false);
		}
	},

	// ツリーのノードのドラッグ
	_init_dnd: function(){
		const self = this;
		const div  = this.div;
		let drag;	// { x0, y0, src, target, helper, started, title, down, enter, hitMode }

		function start(x, y, evt) {
			const src = get_node(evt.target);
			if (!src || src.tree !== self || src.isStatusNode()) return false;
			drag = { x0: x, y0: y, src: src, started: false, title: evt.target.closest ? evt.target.closest('.' + CN.title) : null };
			return true;
		}
		function begin(x, y) {
			const d = self.dnd;
			if (d.onDragStart && d.onDragStart(drag.src) === false) { drag = null; return false; }
			// つかんだものの写し（今までと同じく、マウスの左上の少し下に出す）
			const h = document.createElement('div');
			h.className = 'dynatree-drag-helper';
			h.innerHTML = "<span class='dynatree-drag-helper-img'></span>";
			if (drag.title) h.appendChild( drag.title.cloneNode(true) );
			h.classList.add('ui-draggable-dragging');
			h.style.position = 'absolute';
			// 今までと同じく、木のul.dynatree-containerの中に置く（jQuery UIは、文書の中にあればbodyに移さない）
			self.tnRoot.ul.appendChild(h);
			drag.helper  = h;
			drag.started = true;
			drag.src.span.classList.add('dynatree-drag-source');
			place(x, y);
			return true;
		}
		// マウスの位置から、写しの位置を決める（jQuery UIのdraggableと同じく、親（offsetParent）からの位置）
		function place(x, y) {
			const h  = drag.helper;
			const op = h.offsetParent || document.documentElement;
			let left = 0, top = 0;
			if (!/^(?:html|body)$/i.test(op.tagName)) {
				const o = offset_of(op);
				left = o.left;
				top  = o.top;
			}
			const cs = getComputedStyle(op);
			left += parseInt(cs.borderLeftWidth) || 0;
			top  += parseInt(cs.borderTopWidth)  || 0;
			if (op !== document.documentElement && op !== document.body) {
				left -= op.scrollLeft;
				top  -= op.scrollTop;
			}
			h.style.left = (x - 16 - left) + 'px';
			h.style.top  = (y + 2  - top)  + 'px';
		}
		function move(x, y, target) {
			if (!drag) return;
			if (!drag.started) {
				if (Math.max(Math.abs(x - drag.x0), Math.abs(y - drag.y0)) < 4) return;
				if (!begin(x, y)) return;
			}
			place(x, y);
			scroll(x, y);
			self._dnd_move(drag, target, x, y);
		}
		function scroll(x, y) {	// 今までのjQuery UIのdraggableと同じく、端から10pxで7pxずつ
			const sx = window.pageXOffset, sy = window.pageYOffset;
			if (y - sy < 10)				window.scrollTo(sx, sy - 7);
			else if (window.innerHeight - (y - sy) < 10)	window.scrollTo(sx, sy + 7);
			if (x - sx < 10)				window.scrollTo(window.pageXOffset - 7, window.pageYOffset);
			else if (window.innerWidth - (x - sx) < 10)	window.scrollTo(window.pageXOffset + 7, window.pageYOffset);
		}
		function stop(dropped) {
			if (!drag) return;
			const d = drag;
			if (d.started) {
				self._dnd_stop(d, dropped);
				if (d.src.span) d.src.span.classList.remove('dynatree-drag-source');
				d.helper.remove();
				// ドラッグの後のクリックは止める。押した所と離した所が違うとき、クリックは両方を含む親で起きる。
				// 止めないと、その親のノードが選ばれて開け閉めされる（フォルダを隣のフォルダに入れると、親が閉じる）
				const stopclick = function(evt){ evt.stopPropagation(); evt.preventDefault(); };
				document.addEventListener('click', stopclick, true);
				setTimeout(function(){ document.removeEventListener('click', stopclick, true) }, 0);
			}
			drag = null;
		}

		// マウス（とペン）。今までのjQuery UIと同じく、マウスのイベントで受ける（pageX、pageYが整数になる）
		div.addEventListener('mousedown', function(evt){
			if (evt.button !== 0 || drag) return;
			if (evt.target.closest && evt.target.closest('input, textarea, button, select, option')) return;
			// 今までのjQuery UIのdraggableと同じく、押した所の外にfocusがあれば外す
			const ae = document.activeElement;
			if (ae && ae !== document.body && !ae.contains(evt.target)) ae.blur();
			if (!start(evt.pageX, evt.pageY, evt)) return;
			const mv = function(e){
				move(e.pageX, e.pageY, e.target);
				if (drag && drag.started) e.preventDefault();
			};
			const up = function(e){
				document.removeEventListener('mousemove', mv);
				document.removeEventListener('mouseup',   up);
				stop(e.button === 0);
			};
			document.addEventListener('mousemove', mv);
			document.addEventListener('mouseup',   up);
		});
		// 押したときの既定の動き（リンクのドラッグ、文字の選択、focus）は止める。今までのjQuery UIと同じく、
		// 入力欄などは除く（名前の編集の欄）。focusは、クリックの処理（_onClick）で移す
		div.addEventListener('mousedown', function(evt){
			if (evt.button !== 0) return;
			if (evt.target.closest && evt.target.closest('input, textarea, button, select, option')) return;
			evt.preventDefault();
		});

		// タッチ：指を置いて少し待ってから動かすとドラッグ（今までのasysのdndEmulationと同じ）。
		// すぐに動かしたときはスクロール
		let timer, flag;
		div.addEventListener('touchstart', function(evt){
			if (drag) return;
			const t = evt.touches[0];
			flag = false;
			if (!start(t.pageX, t.pageY, evt)) return;
			timer = setTimeout(function(){ timer = null; flag = true; }, TouchDnDTime);
		}, { passive: true });
		div.addEventListener('touchmove', function(evt){
			if (!drag) return;
			if (!flag) {
				if (timer) clearTimeout(timer);
				timer = null;
				drag = null;
				return;
			}
			const t  = evt.changedTouches[0];
			const el = document.elementFromPoint(t.clientX, t.clientY);
			move(t.pageX, t.pageY, el);
			// 今までのdndEmulationは、1回のtouchmoveでmousemoveを何回も起こしていたので、
			// 指がノードに乗った最初のtouchmoveで、ノードに入る・上にいるが両方起きていた。それに合わせる
			if (drag && drag.started) self._dnd_move(drag, el, t.pageX, t.pageY);
			if (evt.cancelable) evt.preventDefault();
		}, { passive: false });
		div.addEventListener('touchend', function(evt){
			if (timer) clearTimeout(timer);
			timer = null;
			stop(true);
		});
		div.addEventListener('touchcancel', function(evt){
			if (timer) clearTimeout(timer);
			timer = null;
			stop(false);
		});
	}
};

////////////////////////////////////////////////////////////////////////////////
// ●ダブルタップ（今までのasysのmydbltapと同じ。マウスのときは呼ばない）
////////////////////////////////////////////////////////////////////////////////
AdiaryTree.dbltap = function(dom, func) {
	let flag;
	let mouse;
	dom.addEventListener('click', function(evt){
		if (flag) {
			flag = false;
			if (mouse) return;
			return func(evt);
		}
		flag  = true;
		mouse = true;
		setTimeout(function(){ flag = false }, DoubleTapTime);
	}, { passive: true });
	dom.addEventListener('touchstart', function(){
		mouse = false;
	}, { passive: true });
};

window.AdiaryTree = AdiaryTree;
})();
