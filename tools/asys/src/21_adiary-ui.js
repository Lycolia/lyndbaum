//##############################################################################
// adiary UI
//							(C)2019-2022 nabe@abk
//##############################################################################
$._adiary_ui = {
	zindexStart:	1000,
	dialogs:	[],
	objs:		[],
	escHook:	false
};
////////////////////////////////////////////////////////////////////////////////
// dialog, only modal mode.
////////////////////////////////////////////////////////////////////////////////
$.fn.adiaryDialog = function(opt) {
	const self = this;
	if ( opt === 'open' )	return this.adiaryDialogOpen();
	if ( opt === 'close' )	return this.adiaryDialogClose();

	const useDialog = opt.dialog;

	////////////////////////////////////////////////////////////////////////
	// init dialog
	////////////////////////////////////////////////////////////////////////
	const $win = $(window);
	const $dialog = $(useDialog ? '<dialog>' : '<div>').addClass('ui-dialog aui-dialog');
	if (useDialog) {
		$dialog.attr('method', 'dialog');
	}
	const min_w = opt.minWidth  || 200;
	const min_h = opt.minHeight || 150;
	let   width = opt.width     || 300;
	if (width<0) width='auto';
	$dialog.css({
		width:		width,
		minWidth:	min_w,
		minHeight:	min_h
	});
	if (opt.maxWidth)  $dialog.css('max-width',  opt.maxWidth );
	if (opt.maxHeight) $dialog.css('max-height', opt.maxHeight);
	if (opt.dialogClass)
		$dialog.addClass( opt.dialogClass );

	const data = this.adiaryUIData('dialog');
	////////////////////////////////////////////////////////////////////////
	// header
	////////////////////////////////////////////////////////////////////////
	{
		const $title = $('<div>').addClass('ui-dialog-titlebar ui-widget-header');
		const $span  = $('<span>').addClass('ui-dialog-title')
			.html( opt.title || this.attr('title') || '&ensp;' );
		$title.append( $span );
		const $close = $('<button>').addClass('ui-button').attr({
			title: 'Close',
			tabindex: -1
		});
		$close.append( $('<span>').addClass('ui-icon ui-icon-closethick') );
		$title.append( $close );
		$dialog.append( $title );

		$close.on('click', function(){
			if (opt.exit) opt.exit();
			self.adiaryDialogClose();
		});
		data.$header = $title;
	}

	////////////////////////////////////////////////////////////////////////
	// ESC
	////////////////////////////////////////////////////////////////////////
	if (!('closeOnEscape' in opt) || opt.closeOnEscape) {
		const dialogs = $._adiary_ui.dialogs = $.adiaryUIFilterExists( $._adiary_ui.dialogs );
		dialogs.push( $dialog );

		if (!$._adiary_ui.escHook) {
			$._adiary_ui.escHook = true;
			$(window).on('keydown', function(evt){
				if (evt.which != 27)  return;	// ESC

				const $dialog = $._adiary_ui.dialogs.pop();
				if ($dialog) $dialog.find('div.ui-dialog-titlebar .ui-icon-closethick').click();
			});
		}
	}

	////////////////////////////////////////////////////////////////////////
	// main
	////////////////////////////////////////////////////////////////////////
	this.addClass('ui-dialog-content');
	data.$restore = this.parent();
	$dialog.append( this );
	this.show();

	////////////////////////////////////////////////////////////////////////
	// button
	////////////////////////////////////////////////////////////////////////
	if (opt.buttons) {
		const $footer = $('<div>').addClass('ui-dialog-buttonpane');
		const $btnset = $('<div>').addClass('ui-dialog-buttonset');
		const btns = opt.buttons;
		const $btns = [];
		for(let i in btns) {
			let $btn = $('<button>')
					.addClass('ui-button')
					.attr('type', 'button')
					.text( i );
			$btn.on('click', btns[i]);
			$btnset.append($btn);
			$btns.push($btn);
		}
		$footer.append( $btnset );
		$dialog.append( $footer );
		data.$footer = $footer;
	}

	////////////////////////////////////////////////////////////////////////
	// disable tab indexes
	////////////////////////////////////////////////////////////////////////
	if (!useDialog) {
		const tabs = [];
		data.tabs = tabs;
		$('a, input, button, select, textarea').each(function(idx,dom){
			const $obj = $(dom);
			tabs.push({
				$obj:	$obj,
				index:	$obj.attr('tabindex')
			})
			$obj.attr('tabindex', -1);
		});
		if (document.activeElement) $(document.activeElement).blur();
	}

	////////////////////////////////////////////////////////////////////////
	// append dialog obj
	////////////////////////////////////////////////////////////////////////
	if (!useDialog) data.$overlay = $('<div>').addClass('ui-overlay aui-overlay');
	data.$dialog     = $dialog;
	data.open        = opt.open;
	data.close       = opt.close;
	data.beforeClose = opt.beforeClose;
	data.useDialog   = useDialog;
	data.min_h       = min_h;

	if (opt && !opt.autoOpen && 'autoOpen' in opt) return this;

	return this.adiaryDialogOpen();
};

$.fn.adiaryDialogOpen = function() {
	const data    = this.adiaryUIData('dialog');
	const $overlay= data.$overlay;
	const $dialog = data.$dialog;
	if (!$dialog) throw("Do not open dialog!");

	$overlay.css('visibility', 'hidden');
	$dialog .css('visibility', 'hidden');
	this.adiaryUIAppend( data.$overlay );
	this.adiaryUIAppend( $dialog       );

	// set css
	const $win = $(window);
	const hf   = data.$header.outerHeight() + (data.$footer ? data.$footer.outerHeight() : 0);
	this.css('min-height', (data.min_h    - hf) + 'px');
	this.css('max-height', ($win.height() - hf) + 'px');

	const x = $win.scrollLeft() + ($win.width()  - $dialog.outerWidth() )/2;
	const y = $win.scrollTop()  + ($win.height() - $dialog.outerHeight())/2;
	$dialog.css({
		left:	x,
		top:	y
	});
	$dialog.adiaryDraggable({
		handle: '.ui-dialog-titlebar'
	});
	$overlay.css('visibility', 'visible');
	$dialog .css('visibility', 'visible');

	if (data.open) data.open( null, this );

	return this;
};

$.fn.adiaryDialogClose = function() {
	const data = this.adiaryUIData('dialog');
	if (data.beforeClose) data.beforeClose.call( null, this );

	if (data.$overlay) data.$overlay.remove();
	data.$dialog.remove();
	if (data.$restore && data.$restore.length) data.$restore.append( this );

	data.$overlay=null;
	data.$dialog =null;

	// recovery tab index
	if (!data.useDialog) {
		const tabs = data.tabs;
		for(let i in tabs) {
			let tab = tabs[i];
			let idx = tab.index;
			if (idx === undefined) tab.$obj.removeAttr('tabindex');
					else   tab.$obj.attr('tabindex', idx)
		}
	}
	if (data.close) data.close.call( null, this );

	return this;
};

////////////////////////////////////////////////////////////////////////////////
// overlay function
////////////////////////////////////////////////////////////////////////////////
$.adiaryOverlay = function() {
	return $('<div>').addClass('ui-overlay aui-overlay');
};

$.adiaryOverlayShow = function() {
	const $overlay = $.adiaryOverlay();
	$.adiaryUIAppend($overlay);
	return $overlay;
};

////////////////////////////////////////////////////////////////////////////////
// dialog sub functions
////////////////////////////////////////////////////////////////////////////////
$.adiaryUIAppend = $.fn.adiaryUIAppend = function($obj) {
	if (!$obj || $obj.length !== 1) return;

	let   zindex = $._adiary_ui.zindexStart -1;
	const objs   = $.adiaryUIFilterExists( $._adiary_ui.objs, function($obj){
		let zi = $obj.adiaryUIData('Append', 'zindex');
		if (zindex<zi) zindex=zi;
	});
	objs.push( $obj );
	$._adiary_ui.objs = objs;

	$obj.css('z-index', ++zindex);
	$obj.adiaryUIData('Append', 'zindex', zindex);

	$('body').append( $obj );
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
// draggable
////////////////////////////////////////////////////////////////////////////////
$.fn.adiaryDraggable = function(opt) {
	let sx;
	let sy;
	let $obj;
	this.addClass('aui-draggable');

	this.on('mousedown', function(evt){
		$('iframe').css('pointer-events', 'none');
		const $tar = $(evt.target);
		$obj = $tar.hasClass('aui-draggable') ? $tar : $tar.parentsOne('.aui-draggable');

		if (opt) {
			const $o = $tar;
			if ($tar != $obj) $o.add($tar.parentsUntil('.aui-draggable'));
			if (opt.cancel &&  $o.filter(opt.cancel).length) return;
			if (opt.handle && !$o.filter(opt.handle).length) return;
		}
		const p = $obj.offset();
		sx = p.left - evt.pageX;
		sy = p.top  - evt.pageY;
		document.addEventListener('mousemove', move);
		evt.preventDefault();
		return;
	});

	this.on('mouseup', function(evt){
		$('iframe').css('pointer-events', 'auto');
		document.removeEventListener('mousemove', move);
		evt.preventDefault();
	});

	function move(evt) {
		const x = sx + evt.pageX;
		const y = sy + evt.pageY;
		$obj.css({
			position:	'absolute',
			left:		x + 'px',
			top:		y + 'px'
		});
		evt.preventDefault();
	}
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

////////////////////////////////////////////////////////////////////////////////
// filter function
////////////////////////////////////////////////////////////////////////////////
$.adiaryUIFilterExists = function($objs, callback) {
	const $ary  = [];
	const $body = $('body');

	for(let k in $objs) {
		if (! $body.find($objs[k]).length) continue;
		$ary.push($objs[k]);
		if (callback) callback($objs[k]);
	}
	return $ary;
}