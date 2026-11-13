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

$$.load_msg = function($obj) {
	if (!($obj in jQuery)) { $obj = $($obj); }

	const msgs = this.msgs = this.msgs || {};

	$obj.each(function(idx,dom) {
		try {
			const json = $(dom).html().replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
			const data = JSON.parse(json);
			for(var i in data)
				msgs[i] = data[i];
		} catch(e) {
			console.error(e);
		}
	});
}

