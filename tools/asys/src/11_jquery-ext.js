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
// Drag and Drop emulation by touch event
////////////////////////////////////////////////////////////////////////////////
$.fn.dndEmulation = function(opt){
	if (!opt) opt={};

	// make mouse event object from touch event infomation
	function make_mouse_event(name, evt, touch) {
		const e    = $.Event(name);
		e.altKey   = evt.altKey;
		e.metaKey  = evt.metaKey;
		e.ctrlKey  = evt.ctrlKey;
		e.shiftKey = evt.shiftKey;
		e.clientX  = touch.clientX;
		e.clientY  = touch.clientY;
		e.screenX  = touch.screenX;
		e.screenY  = touch.screenY;
		e.pageX    = touch.pageX;
		e.pageY    = touch.pageY;
		e.which    = 1;
		return e;
	}

	// get all parents element including yourself.
	function get_par_elements(dom) {
		var ary  = [];
		while(dom) {
			ary.push( dom );
			if (dom == self) break;
			dom = dom.parentNode;
		}
		return ary;
	}

	function regist_dnd_emulation(dom) {
		let prev;
		let flag;
		let timer;
		let orig_touch;

		// mousedown
		dom.addEventListener('touchstart', function(evt) {
			prev = evt.target;
			orig_touch = evt.touches[0];
			const e = make_mouse_event('mousedown', evt, evt.touches[0]);
			$( prev ).trigger(e);

			// Disable the process if it does not pass a certain amount of time.
			flag  = false;
			timer = setTimeout(function(){
				timer = false;
				flag  = true;
			}, $$.TouchDnDTime)
		}, { passive: true });

		// mouseup
		dom.addEventListener('touchend', function(evt){
			if (timer) clearTimeout(timer);
			timer = false;
			const e = make_mouse_event('mouseup', evt, evt.changedTouches[0]);
			$( evt.target ).trigger(e);
		});

		// drag
		dom.addEventListener('touchmove', function(evt) {
			// move wait
			if (!flag) {
				if (timer) clearTimeout(timer);
				timer = false;
				return;
			}

			const touch = evt.changedTouches[0];
			const dom   = document.elementFromPoint(touch.clientX, touch.clientY);
			const enter = get_par_elements(dom);

			const e = make_mouse_event('mousemove', evt, touch);
			$(enter).trigger(e);

			if (evt.cancelable) evt.preventDefault();
			if (!opt.leave || dom == prev) return;

			////////////////////////////////////////////////////////
			// leave and enter event emulation
			////////////////////////////////////////////////////////
			const leave = get_par_elements(prev);

			// Remove common elements
			while(leave.length && enter.length
			   && leave[leave.length -1] == enter[enter.length -1]) {
				leave.pop();
				enter.pop();
			}

			const e_leave = make_mouse_event('mouseleave', evt, touch);
			const e_out   = make_mouse_event('mouseout',   evt, touch);
			const e_enter = make_mouse_event('mouseenter', evt, touch);
			const e_over  = make_mouse_event('mouseover',  evt, touch);
			$(leave).trigger( e_leave );
			$(prev) .trigger( e_out   );
			$(enter).trigger( e_enter );
			$(dom)  .trigger( e_over  );

			// save current dom
			prev=dom;
		}, {passive: false});
	}

	this.each( function(idx, dom){
		regist_dnd_emulation(dom)
	});
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
