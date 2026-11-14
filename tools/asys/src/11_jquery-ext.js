//##############################################################################
//extend jQuery
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// show, hide with delay
////////////////////////////////////////////////////////////////////////////////
$.fn.showDelay = function(){
	let args = Array.from(arguments)
	args.unshift($$.DefaultShowSpeed);
	return $.fn.show.apply(this, args);
};
$.fn.hideDelay = function(){
	let args = Array.from(arguments);
	args.unshift($$.DefaultShowSpeed);
	return $.fn.hide.apply(this, args);
};
$.fn.toggleDelay = function(){
	let args = Array.from(arguments);
	args.unshift($$.DefaultShowSpeed);
	return $.fn.toggle.apply(this, args);
};
////////////////////////////////////////////////////////////////////////////////
// find dom element including itself
////////////////////////////////////////////////////////////////////////////////
$.fn.findx = function() {
	return $.fn.filter.apply(this, arguments).add( $.fn.find.apply(this, arguments) );
};

////////////////////////////////////////////////////////////////////////////////
// extra find function
////////////////////////////////////////////////////////////////////////////////
$.fn.rootfind = function(sel) {
	return this.parents().last().find(sel);
};
$.fn.parentsOne = function(filter) {
	return this.parents(filter).first();
};
$.fn.existsData = function(name) {
	const v = this.data(name);
	return v !== undefined;
};

////////////////////////////////////////////////////////////////////////////////
// parse form to hash
////////////////////////////////////////////////////////////////////////////////
$.fn.parseFormHash = function(cancel) {
	return this._parseForm(false, cancel);
}
$.fn.parseFormFD = function(cancel) {
	return this._parseForm(true,  cancel);
}
$.fn._parseForm = function(fdmode, cancel) {
	const data = fdmode ? new FormData : {};
	const $cancel = (cancel instanceof $) ? cancel
		: (cancel === undefined ? cancel : $(cancel));

	this.find('input, select, textarea').each(function(idx, dom){
		if (dom.disabled) return;
		if (dom.type == 'checkbox' && !dom.checked) return;
		if ($cancel && $cancel.find(dom).length) return;

		const name = dom.name;

		// file
		if (dom.tagName == 'INPUT' && dom.type == 'file') {
			if (!fdmode) return;
			const files = dom.files;
			for(let i=0; i<files.length; i++)
				data.append(name, files[i]);
			return;
		}
		if (name == undefined || name == '') return;
		if (fdmode)
			data.append(name, $(dom).val());
		else
			data[name] = $(dom).val();
	});
	return data;
};

////////////////////////////////////////////////////////////////////////////////
// any serialize
////////////////////////////////////////////////////////////////////////////////
$.fn.anySerialize = function(){
	return this.find('input, textarea, select').serialize();
}
$.fn.anySerializeArray = function(){
	return this.find('input, textarea, select').serializeArray();
}

////////////////////////////////////////////////////////////////////////////////
// Function calls sequentially when an event occurs
////////////////////////////////////////////////////////////////////////////////
$.fn.onSequence = function(_event, _priority, _func) {
	const name = '_on_' + _event.replace(/[^\w]/g, '_');

	this.each(function(idx, dom) {
		const self = $(dom);

		if (!self.data(name)) {
			const list = [];
			self.data(name, list);

			self.on(_event, function(){
				for(var x in list) {
					var r = list[x].func.apply(null, arguments);
					if (!r) return false;	// false break
				}
				return true;
			})
		}
		const list = self.data(name);
		list.push({
			priority:	_priority,
			func:		_func
		});
		self.data(name, list.sort(function(a,b){
			return a.priority - b.priority
		}));
	});
	return this;
};

////////////////////////////////////////////////////////////////////////////////
// "dbltap" event exclusive mouse
////////////////////////////////////////////////////////////////////////////////
// Double touch event order: touchstart, click, touchstart, click
// Mouse double click order: click, click, dblclick
$.event.special.mydbltap = {
	setup: function(){
		let flag;
		let mouse;
		this.addEventListener('click', function(evt) {
			if (flag) {
				flag = false;
				if (mouse) return;
				return $(evt.target).trigger('mydbltap');
			}
			flag  = true;
			mouse = true;
			setTimeout( function(){ flag = false; }, $$.DoubleTapTime);
		}, { passive: true });

		this.addEventListener('touchstart', function(){
			mouse = false;
		}, { passive: true });
	}
};
