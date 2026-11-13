////////////////////////////////////////////////////////////////////////////////
// popup for mouseenter
////////////////////////////////////////////////////////////////////////////////
$$.popup = function(evt) {
	const self  = this;
	const $obj  = $(evt.target);
	let   delay = $obj.data('delay') || this.PopupDelayTime;
	if (delay<1) delay=1;

	if (!evt.data.$div) {
		const $popup = $('<div>').addClass('popup-block');
		this.$body.append( $popup );
	 	evt.data.$div = $popup;
	}

	$obj.on('mouseleave', evt.data, function(evt){ self.popup_hide(evt) });
	$obj.data('timer', setTimeout(  function()   { self.popup_show(evt) }, delay));
}

$$.popup_show = function(evt) {
	const $obj = $(evt.target);
	const $div = evt.data.$div;
	if ($div.is(":animated")) return;

	if (evt.data.show) evt.data.show(evt, $obj, $div);
	$div.css("left", (this.SP ? 0 : (evt.pageX + this.PopupOffsetX)));
	$div.css("top" ,                 evt.pageY + this.PopupOffsetY);
	$div.showDelay();
}

$$.popup_hide = function(evt) {
	const $obj = $(evt.target);
	const $div = evt.data.$div;
	if ($obj.data('timer')) {
		clearTimeout( $obj.data('timer') );
		$obj.data('timer', null);
	}
	$obj.off('mouseout');
	$div.hide();
	if (evt.data.hide) evt.data.hide(evt, $obj, $div);
}

