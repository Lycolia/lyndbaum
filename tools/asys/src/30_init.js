////////////////////////////////////////////////////////////////////////////////
// make main object
////////////////////////////////////////////////////////////////////////////////
'use strict';
let $$ = {
	name:			'asys',	// global export name
	Initialize:		true,	// auto run $$.init()

//	DialogWidth:		 -1,	// -1 is auto
//	DialogMinWidth:		200,
//	DialogMinHeight:	100,

	DefaultShowSpeed:	300,	// msec
	TouchDnDTime:		100,	// msec
	DoubleTapTime:		400,	// msec
	PopupDelayTime:		300,	// msec
	PopupOffsetX:		 15,
	PopupOffsetY:		 10
};

////////////////////////////////////////////////////////////////////////////////
// initalize
////////////////////////////////////////////////////////////////////////////////
(function(){
	const ary = [];
	let   initialized;

	$$.init = function(func, priority) {
		if (func) {
			if (initialized) {
				if (priority) console.warn('init() initialized, but priority set', priority);
				func.call(this);
			}
			return ary.push({
				func:	func,
				p:	priority || 100
			});
		}

		// initlize functions
		ary.sort(function(a,b) {
			return a.p - b.p;
		});

		for(var i=0; i<ary.length; i++)
			ary[i].func.call(this);

		initialized = true;
	};
})();

////////////////////////////////////////////////////////////////////////////////
// load message
////////////////////////////////////////////////////////////////////////////////
$$.msg = function(key, _default) {
	if (!this.msgs) {
		const msgs = this.msgs = this.msgs || {};
		if (this.load_msg) this.load_msg();
	}
	const val = this.msgs[key];
	return (val === undefined) ? (_default || key.toUpperCase()) : val;
}
$$.set_msg = function(obj, msg) {
	const msgs = this.msgs = this.msgs || {};

	if (typeof(obj) != 'object') {
		msgs[obj] = msg;
		return;
	}
	const keys = Object.keys(obj);
	for(let i=0; i<keys.length; i++) {
		msgs[ keys[i] ] = obj[ keys[i] ];
	}
}

// sel は選択子か要素
$$.load_msg = function(sel) {
	const doms = typeof(sel) === 'string' ? document.querySelectorAll(sel) : (sel ? [ sel ] : []);
	const msgs = this.msgs = this.msgs || {};

	doms.forEach(function(dom) {
		try {
			const json = dom.innerHTML.replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
			const data = JSON.parse(json);
			for(var i in data)
				msgs[i] = data[i];
		} catch(e) {
			console.error(e);
		}
	});
}


////////////////////////////////////////////////////////////////////////////////
// data-* の値（jQueryの.data()と同じく、"0"は数の0、"true"は真などに直す）
////////////////////////////////////////////////////////////////////////////////
$$.data_value = function(dom, name) {
	const v = dom.getAttribute('data-' + name);
	if (v === null) return undefined;
	if (v === 'true')  return true;
	if (v === 'false') return false;
	if (v === 'null')  return null;
	if (v === +v + '') return +v;
	if (/^(?:\{[\w\W]*\}|\[[\w\W]*\])$/.test(v)) {
		try { return JSON.parse(v) } catch(e) { }
	}
	return v;
};

////////////////////////////////////////////////////////////////////////////////
// 範囲の要素自身も含めて探す
////////////////////////////////////////////////////////////////////////////////
$$.find_all = function(root, sel) {
	const ary = Array.from(root.querySelectorAll(sel));
	if (root.matches && root.matches(sel)) ary.unshift(root);
	return ary;
};

////////////////////////////////////////////////////////////////////////////////
// 要素のいちばん上の親の中から探す（今までの jQuery の rootfind）
////////////////////////////////////////////////////////////////////////////////
// 文書の中なら文書全体から、まだ文書に入れていない要素（ダイアログの中身など）なら、その中から探す
$$.rootfind = function(dom, sel) {
	let root = dom;
	while(root.parentElement) root = root.parentElement;
	if (root === dom) return [];
	return Array.from(root.querySelectorAll(sel));
};

////////////////////////////////////////////////////////////////////////////////
// asysの部品のchangeの処理
////////////////////////////////////////////////////////////////////////////////
// on_change で付けた処理は、ふつうのchangeで動く。fire_change は、その処理だけを、
// 付けた順に呼ぶ（今までのjQueryの.change()と同じく、jQueryを使わずに付けた処理には届かない）
{
	const handlers = new WeakMap();
	$$.on_change = function(dom, func) {
		if (!handlers.has(dom)) handlers.set(dom, []);
		handlers.get(dom).push(func);
		dom.addEventListener('change', func);
	};
	$$.fire_change = function(dom) {
		const evt = { type: 'change', target: dom, currentTarget: dom, preventDefault: function(){}, stopPropagation: function(){} };
		for(const func of (handlers.get(dom) || [])) func(evt);
	};
}
