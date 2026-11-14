//##############################################################################
// ツリー（dynatree 1.2.5 の代わり。jQueryを使わない）
//##############################################################################
//[TAB=8]
// dynatree と同じ要素とクラスを作り、dynatree の CSS（dynatree/skin/ui.dynatree.css）を
// そのまま使う。動きは dynatree 1.2.5 のコードから、使っている所だけを写した。
//
//	const tree = new AdiaryTree(要素, {
//		url:		JSON の URL（[{ title, key, children: [...] }, ...]）
//		onPostInit:	function(isReloading, isError)
//		onActivate:	function(node)
//		onClick:	function(node, evt)	false で、選ぶのをやめる
//		onDblClick:	function(node, evt)
//		onKeydown:	function(node, evt)	false で、キーの動きをやめる
//		dnd: {
//			onDragStart:	function(node)			false でドラッグしない
//			onDragEnter:	function(node, srcNode)		true で入れられる
//			onDragOver:	function(node, srcNode, hitMode) false で入れない。"before" などで印の向きを変える
//			onDrop:		function(node, srcNode, hitMode)
//			autoExpandMS:	1000,
//			preventVoidMoves: true
//		}
//	});
//	tree.getRoot()、tree.getActiveNode()、tree.reload()、tree.disable()、tree.enable()
//	AdiaryTree.dbltap(要素, func)	… タッチのダブルタップ（今までの asys の mydbltap と同じ判定）
//
'use strict';
(function(){
////////////////////////////////////////////////////////////////////////////////
// ●クラス名など（dynatree と同じ）
////////////////////////////////////////////////////////////////////////////////
const CN = {
	container:	'dynatree-container',
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
const TouchDnDTime  = 100;	// msec（asys の $$.TouchDnDTime と同じ）
const DoubleTapTime = 400;	// msec（asys の $$.DoubleTapTime と同じ）

function get_node(el) {
	while(el) {
		if (el.dtnode) return el.dtnode;
		el = el.parentNode;
	}
	return null;
}
// jQueryの .offset()、.height()
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
		const d = this.data;
		let html = this.hasChildren() !== false
			? "<span class='" + CN.expander  + "'></span>"
			: "<span class='" + CN.connector + "'></span>";
		html += "<span class='" + CN.nodeIcon + "'></span>";
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
			this.ul.className = CN.container;
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
	addChild: function(ary){
		if (!ary || !ary.length) return;
		// 作り終えてから表示する（dynatree の enableUpdate(false) と同じ）
		const update = this.tree.bEnableUpdate;
		this.tree.bEnableUpdate = false;
		for(const data of ary) {
			const node = new Node(this, this.tree, Object.assign({}, data));
			if (this.childList === null) this.childList = [];
			else if (this.childList.length && this.childList[this.childList.length-1].span)
				this.childList[this.childList.length-1].span.classList.remove(CN.lastsib);
			this.childList.push(node);
			if (data.children) node.addChild(data.children);
		}
		this.tree.bEnableUpdate = update;
		if (update) this.render();
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
	// mode は "before"、"after"、"over"（子にする）
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
		if (!flag && this.getLevel() < 1) return;	// minExpandLevel
		this.bExpanded = flag;
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
	activate: function(){
		const tree = this.tree;
		if (this.isStatusNode()) return;
		if (tree.activeNode) {
			if (tree.activeNode === this) return;
			tree.activeNode.deactivate();
		}
		this.makeVisible();
		tree.activeNode = this;
		this.span.classList.add(CN.active);
		if (tree.options.onActivate) tree.options.onActivate.call(tree, this);
	},
	deactivate: function(){
		const tree = this.tree;
		if (tree.activeNode !== this) return;
		this.span.classList.remove(CN.active);
		tree.activeNode = null;
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
	_outerType: function(evt){	// span の余白を押したとき（dynatree と同じく、位置で決める）
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
			this.activate();
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
			this.activate();
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
		} else {
			if (tree.tnFocused && tree.tnFocused !== this && tree.tnFocused.span)
				tree.tnFocused.span.classList.remove(CN.focused);
			tree.tnFocused = this;
			if (this.span) this.span.classList.add(CN.focused);
		}
	}
};

////////////////////////////////////////////////////////////////////////////////
// ●木
////////////////////////////////////////////////////////////////////////////////
function AdiaryTree(dom, opt) {
	this.div     = dom;
	this.options = opt || {};
	this.dnd     = Object.assign({ autoExpandMS: 1000, preventVoidMoves: true }, this.options.dnd || {});
	this.enabled = true;
	this._bind();
	if (this.options.dnd) this._init_dnd();
	this._load(false);
}
AdiaryTree.prototype = {
	getRoot:	function(){ return this.tnRoot },
	getActiveNode:	function(){ return this.activeNode },
	reload:		function(){ this._load(true) },
	visit:		function(fn, includeSelf){ return this.tnRoot.visit(fn, includeSelf) },
	// 名前を編集する間などに、クリックとキーを止める（今までの $widget.unbind()、bind()。ドラッグは止めない）
	disable:	function(){ this.enabled = false },
	enable:		function(){ this.enabled = true  },

	_load: function(isReloading){
		const self = this;
		const opt  = this.options;
		this.bEnableUpdate = true;
		this._nodeCount = 1;
		this.activeNode = null;
		this.tnFocused  = null;
		this.div.innerHTML = '';
		this.tnRoot = new Node(null, this, {});
		this.tnRoot.bExpanded = true;
		this.tnRoot.render();
		this.div.appendChild(this.tnRoot.ul);

		// 読み込み中の行（読み終わるまで、最初の子にある）
		const root = this.tnRoot;
		root.removeChildren(false);
		this._setStatus({ title: STR.loading, addClass: CN.nodeWait });

		const url = opt.url;
		fetch(url, { cache: 'no-store' }).then(function(res){
			if (!res.ok) throw res.statusText || String(res.status);
			return res.json();
		}).then(function(data){
			if (Array.isArray(data) && data.length) root.addChild(data);
			if (opt.onPostInit) opt.onPostInit.call(self, isReloading, false);
			// 読み込み中の行を消し、最初のノードに focus（autoFocus）
			self._setStatus(null);
			if (root.childList && root.childList.length) root.childList[0].focus();
		}, function(e){
			if (opt.onPostInit) opt.onPostInit.call(self, isReloading, true);
			// 今までと同じく、HTTPの状態の文言（Not Found など）を title に出す
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
			if (ret === false) {	// jQuery と同じく、false は止める
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
	_init_dnd: function(){
		const self = this;
		const div  = this.div;
		let drag;	// { x0, y0, src, target, helper, started, title }

		function start(x, y, evt) {
			const src = get_node(evt.target);
			if (!src || src.tree !== self || src.isStatusNode()) return false;
			drag = { x0: x, y0: y, src: src, started: false, down: evt.target, title: evt.target.closest ? evt.target.closest('.' + CN.title) : null };
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
			// 今までと同じく、木の ul.dynatree-container の中に置く（jQuery UI は、文書の中にあれば body に移さない）
			self.tnRoot.ul.appendChild(h);
			drag.helper  = h;
			drag.started = true;
			drag.src.span.classList.add('dynatree-drag-source');
			place(x, y);
			return true;
		}
		// マウスの位置から、写しの位置を決める（jQuery UI の draggable と同じく、親（offsetParent）からの位置）
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
			const node = get_node(target);
			if (target && !node && target.closest && target.closest('div.dynatree-drag-helper,#dynatree-drop-marker')) return;
			const prev = drag.target;
			drag.target = (node && node.tree === self) ? node : null;
			if (prev && prev !== drag.target) on_leave(prev);
			if (drag.target) {
				if (drag.target === prev) on_over(drag.target, x, y);
					else on_enter(drag.target);
			}
		}
		function scroll(x, y) {	// 今までの jQuery UI の draggable と同じく、端から10pxで7pxずつ
			const sx = window.pageXOffset, sy = window.pageYOffset;
			if (y - sy < 10)				window.scrollTo(sx, sy - 7);
			else if (window.innerHeight - (y - sy) < 10)	window.scrollTo(sx, sy + 7);
			if (x - sx < 10)				window.scrollTo(window.pageXOffset - 7, window.pageYOffset);
			else if (window.innerWidth - (x - sx) < 10)	window.scrollTo(window.pageXOffset + 7, window.pageYOffset);
		}
		function on_enter(node) {
			const d = self.dnd.onDragEnter ? self.dnd.onDragEnter(node, drag.src) : null;
			if (!d) drag.enter = false;
			else if (Array.isArray(d)) drag.enter = { over: d.indexOf('over')>=0, before: d.indexOf('before')>=0, after: d.indexOf('after')>=0 };
			else drag.enter = { over: d===true || d==='over', before: d===true || d==='before', after: d===true || d==='after' };
		}
		function on_over(node, x, y) {
			const d   = self.dnd;
			const src = drag.src;
			const o   = drag.enter;
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
					else if (mode === 'before' && node === src.getNextSibling()) mode = null;
					else if (mode === 'after'  && node === src.getPrevSibling()) mode = null;
					else if (mode === 'over'   && src.parent === node && src.isLastSibling()) mode = null;
				}
				// 落としたときは、この値（下の onDragOver が直す前）を使う。今までの dynatree と同じ
				drag.hitMode = mode;
			}
			if (mode === 'over' && d.autoExpandMS && node.hasChildren() !== false && !node.bExpanded) schedule(node);
			if (mode && d.onDragOver) {
				ret = d.onDragOver(node, src, mode);
				if (ret === 'over' || ret === 'before' || ret === 'after') mode = ret;
			}
			set_status(node, mode, ret !== false && mode !== null);
		}
		function on_leave(node) {
			schedule(null);
			drag.enter   = null;
			drag.hitMode = null;
			set_status(node, 'out', undefined);
		}
		function schedule(node) {	// 閉じたノードの上で待つと開く
			if (self.timer) clearTimeout(self.timer);
			self.timer = null;
			if (node) self.timer = setTimeout(function(){ node.expand(true) }, self.dnd.autoExpandMS);
		}
		function set_status(node, mode, accept) {
			const r = drag.src.span;
			const o = node.span;
			const h = drag.helper;
			let m = self.marker;
			if (!m) {
				m = self.marker = document.createElement('div');
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
				// 印の左を span の左（over は右へ8px）、印の縦の中央を span の上端・下端・中央に合わせる
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
				x.classList.toggle('dynatree-drop-accept', accept === true);
				x.classList.toggle('dynatree-drop-reject', accept === false);
			}
		}
		function stop(dropped, up_target) {
			if (!drag) return;
			const d = drag;
			if (d.started) {
				const t = d.target;
				if (t) {
					if (dropped) {
						const reject = d.helper.classList.contains('dynatree-drop-reject');
						if (d.hitMode && self.dnd.onDrop && !reject) self.dnd.onDrop(t, d.src, d.hitMode);
					}
					on_leave(t);
				}
				if (d.src.span) d.src.span.classList.remove('dynatree-drag-source');
				d.helper.remove();
				// ドラッグの後のクリックは、押した所と離した所が同じときだけ止める（今までの jQuery UI と同じ）。
				// 違うときのクリックは、両方を含む親で起き、その親のノードが選ばれる
				if (up_target && up_target === d.down) {
					const stopclick = function(evt){ evt.stopPropagation(); evt.preventDefault(); };
					document.addEventListener('click', stopclick, true);
					setTimeout(function(){ document.removeEventListener('click', stopclick, true) }, 0);
				}
			}
			drag = null;
		}

		// マウス（とペン）。今までの jQuery UI と同じく、マウスのイベントで受ける（pageX、pageY が整数になる）
		div.addEventListener('mousedown', function(evt){
			if (evt.button !== 0 || drag) return;
			if (evt.target.closest && evt.target.closest('input, textarea, button, select, option')) return;
			// 今までの jQuery UI の draggable と同じく、押した所の外に focus があれば外す
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
				stop(e.button === 0, e.target);
			};
			document.addEventListener('mousemove', mv);
			document.addEventListener('mouseup',   up);
		});
		// 押したときの既定の動き（リンクのドラッグ、文字の選択、focus）は止める。今までの jQuery UI と同じく、
		// 入力欄などは除く（名前の編集の欄）。focus は、クリックの処理（_onClick）で移す
		div.addEventListener('mousedown', function(evt){
			if (evt.button !== 0) return;
			if (evt.target.closest && evt.target.closest('input, textarea, button, select, option')) return;
			evt.preventDefault();
		});

		// タッチ：指を置いて少し待ってから動かすとドラッグ（今までの asys の dndEmulation と同じ）。
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
			if (evt.cancelable) evt.preventDefault();
		}, { passive: false });
		div.addEventListener('touchend', function(evt){
			if (timer) clearTimeout(timer);
			timer = null;
			const t = evt.changedTouches[0];
			stop(true, t && document.elementFromPoint(t.clientX, t.clientY));
		});
		div.addEventListener('touchcancel', function(evt){
			if (timer) clearTimeout(timer);
			timer = null;
			stop(false);
		});
	}
};

////////////////////////////////////////////////////////////////////////////////
// ●ダブルタップ（今までの asys の mydbltap と同じ。マウスのときは呼ばない）
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
