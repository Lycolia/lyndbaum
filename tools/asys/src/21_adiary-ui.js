//##############################################################################
// adiary UI
//							(C)2019-2022 nabe@abk
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// dialog, only modal mode.
////////////////////////////////////////////////////////////////////////////////
// 本体は 40_dialog.js の $$.dialog() など（jQueryを使わない）。ここはjQueryから呼ぶ包み。
// コールバックには、今までどおりjQueryの要素を渡す。閉じるときは、今までどおり
// jQueryの .remove() で消し、中の要素のjQueryのデータとイベントも消す
$.fn.adiaryDialog = function(opt) {
	if ( opt === 'open' )	return this.adiaryDialogOpen();
	if ( opt === 'close' )	return this.adiaryDialogClose();

	const self = this;
	const o    = Object.assign({}, opt);
	if (opt.open)        o.open        = function(evt){ return opt.open.call(this, evt, self) };
	if (opt.beforeClose) o.beforeClose = function(){ return opt.beforeClose.call(null, self) };
	if (opt.close)       o.close       = function(){ return opt.close.call(null, self) };
	o._remove = function(dom){ $(dom).remove() };
	$$.dialog(this[0], o);
	return this;
};
$.fn.adiaryDialogOpen = function() {
	$$.dialog_open(this[0]);
	return this;
};
$.fn.adiaryDialogClose = function() {
	$$.dialog_close(this[0]);
	return this;
};

////////////////////////////////////////////////////////////////////////////////
// overlay function
////////////////////////////////////////////////////////////////////////////////
$.adiaryOverlay = function() {
	return $( $$.overlay() );
};
$.adiaryOverlayShow = function() {
	return $( $$.overlay_show() );
};
$.adiaryUIAppend = $.fn.adiaryUIAppend = function($obj) {
	if (!$obj || $obj.length !== 1) return;
	$$.ui_append($obj[0]);
};

////////////////////////////////////////////////////////////////////////////////
// Progressbar
////////////////////////////////////////////////////////////////////////////////
$.fn.adiaryProgressbar = function(opt) {
	const data  = this.adiaryUIData('progress');
	if (opt === 'value') return data.value;

	if (opt.change)   data.change   = opt.change;
	if (opt.complete) data.complete = opt.complete;

	let init;
	if (!('$value' in data)) {
		this.find('.ui-progressbar-value').remove();
		// initalize
		data.$value = $('<div>').addClass('ui-progressbar-value');
		this.addClass('ui-progressbar');
		this.append( data.$value );
		init = true;
	}

	// value set
	const old   = data.value;
	const value = opt.value;
	data.value  = value;
	data.$value.css('width', value + '%');

	if (init || data.change && old != value) data.change  (data.value);
	if (      data.complete && 100 <= value) data.complete(data.value);
	return this;
};

////////////////////////////////////////////////////////////////////////////////
// accordion
////////////////////////////////////////////////////////////////////////////////
$.fn.adiaryAccordion = function(opt) {
	const $objs = this.children("h1,h2,h3,h4,h5,h6");
	$objs.click(function(evt){
		const $obj = $(evt.target);
		const $div = $obj.next('div');
		if (!$div.length) return;
		$div.toggleDelay();
	});
	$objs.next('div').hide();
};

////////////////////////////////////////////////////////////////////////////////
// draggable（本体は 40_dialog.js の $$.draggable()）
////////////////////////////////////////////////////////////////////////////////
$.fn.adiaryDraggable = function(opt) {
	this.each(function(i, dom){ $$.draggable(dom, opt) });
	return this;
};

////////////////////////////////////////////////////////////////////////////////
// data function
////////////////////////////////////////////////////////////////////////////////
$.fn.adiaryUIData = function(name, key, val) {
	name = 'aui_' + name;
	const data = this[name] = this[name] || {};
	if (arguments.length==2) return data[key];
	if (arguments.length==3) data[key] = val;
	return data;
};
