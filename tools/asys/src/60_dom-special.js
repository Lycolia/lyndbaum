//##############################################################################
// dom special extentions
//##############################################################################
(function(){
	const ary = [];
	let   initialized;

	$$.dom_init = function(func, priority) {
		if (typeof(func) == 'function') {
			if (initialized) {
				if (priority) console.warn('dom_init() initialized, but priority set', priority);
				func.call(this, this.$body);
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

		const $obj = func ? func : this.$body;
		for(var i=0; i<ary.length; i++)
			ary[i].func.call(this, $obj);

		initialized = true;
	};

	$$.init($$.dom_init);
})();

////////////////////////////////////////////////////////////////////////////////
// submit checker
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	const self=this;

	$R.findx('button.js-check-form').on('click', function(evt){
		const $obj  = $(evt.target);
		const $form = $obj.parents('form.js-check-form');
		if (!$form.length) return;
		$form.data('confirm', $obj.data('confirm') );
		$form.data('focus',   $obj.data('focus')   );
		$form.data('button',  $obj);
	});

	$R.findx('form.js-check-form').onSequence('submit', 10, function(evt){
		const $form  = $(evt.target);
		const target = $form.data('target');
		let count=0;
		if (target) {
			count = $form.rootfind( target + ":checked" ).length;
			if (!count) return false;	// no check
		}

		// confirm message
		let confirm = $form.data('confirm');
		if (!confirm) return true;
  		if ($form.data('_confirm_ok')) {
  			$form.data('_confirm_ok', false);
  			return true;
  		}

		// confirm dialog
		confirm = confirm.toString().replace("%c", count);
		self.confirm({
			html: confirm,
			focus: $form.data('focus')
		}, function(flag) {
			if (!flag) return;
  			$form.data('_confirm_ok', true);
			if ($form.data('button')) return $form.data('button').click();

			$form.submit();
		});
		return false;
	});
});

////////////////////////////////////////////////////////////////////////////////
// ajax form
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R) {
	const self=this;
	const func = function($obj){
		$obj.find('.error').removeClass('error');

		const gen  = $obj.data('generator');
		const data = (typeof(gen) === 'function') ? gen($obj) : (function(){
			const $infile = $obj.find('input[type="file"]');
			return $infile.length ? (new FormData($obj[0])) : $obj.serialize();
		})();

		if ($obj.data('--js-ajax-stop')) return;
		$obj.data('--js-ajax-stop', true);
		$obj.prop('disabled', true);
		if ($obj.data('overlay'))
			$obj.data('--overlay-obj', $.adiaryOverlayShow());

		const start_func = $obj.data('start');
		const comp_func  = $obj.data('complete');
		if (typeof(start_func) === 'function') start_func($obj);

		self.send_ajax({
			data:	data,
			success: function(h) {
				const success = $obj.data('success');
				const url = $obj.data('url');
				if (typeof(success) === 'function') return success(h);
				if (typeof(success) === 'string' && success != '') {
					return self.show_dialog(success, function(){
						if (url) window.location = url;
					});
				}
				if (url) window.location = url;
			},
			error: function(err, h) {
				const error = $obj.data('error');
				if (typeof(error) === 'function') return error(h);

				if (!h || !h.errs) return;
				const e = h.errs;
				for(let k in e) {
					if (k == '_order') continue;

					// with number?
					const ma  = k.match(/^(.*)#(\d+)$/);
					const num = ma ? ma[2] : undefined;
					k = ma ? ma[1] : k;
					try {
						let $x = $obj.find('[name="' + k+ '"], [data-name="' + k + '"]');
						if (num) $x = $($x[num-1]);
						$x.addClass('error');
					} catch(e) {
						console.error(e);
					}
				}
			},
			error_dialog_callback: function(){
				const callback = $obj.data('error_dialog_callback');
				if (typeof(callback) === 'function') return callback();
			},
			complete: function(h) {
				if (typeof(comp_func) === 'function') comp_func($obj);
				$obj.data('--js-ajax-stop', false);
				$obj.prop('disabled', false);
				if ($obj.data('--overlay-obj')) $obj.data('--overlay-obj').remove();
			}
		});
		return false;
	};

	$R.find('form.js-ajax').onSequence('submit', 100, function(evt) {
		const $obj = $(evt.target);
		const callback = function(){ func($obj) };

		const checker  = $obj.data('checker');
		if (typeof(checker) === 'function') {
			if (! checker($obj, callback)) return false;
		}
		func($obj);
		return false;
	});
});

////////////////////////////////////////////////////////////////////////////////
// auto save form value
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R) {
	const self = this;

	$R.findx('input.js-save, select.js-save').each( function(idx, dom) {
		const $obj = $(dom);
		const type = $obj[0].type;

		let id = type != 'radio' && $obj.attr("id");
		if (!id) id = 'name=' + $obj.attr("name");
		if (!id) return;

		if (type == 'checkbox') {
			$obj.change( function(evt){
				const $o = $(evt.target);
				self.Storage.set(id, $o.prop('checked') ? 1 : 0);
			});
			if ( self.Storage.defined(id) )
				$obj.prop('checked', self.Storage.get(id) != 0 );
			return;
		}
		if (type == 'radio') {
			const val = $obj.attr('value');
			$obj.change( function(evt){
				const $o = $(evt.target);
				self.Storage.set(id, val);
			});
			if ( self.Storage.defined(id) && val == self.Storage.get(id)) {
				$obj.prop('checked', 1);
			}
			return;
		}
		$obj.change( function(evt){
			const $o = $(evt.target);
			if ($o.val() == self.js_combo_dummy_val) return;
			self.Storage.set(id, $o.val());
		});
		const val = self.Storage.get(id);
		if (! val) return;
		if (dom.tagName == 'SELECT')
			return self.set_value_on_select( $obj, val );
		
		return $obj.val( val );
	});
});

////////////////////////////////////////////////////////////////////////////////
// form dom element enable/disable by other form elements
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function($R){
	const $objs = $R.findx('input.js-enable, input.js-disable, select.js-enable, select.js-disable');

	let   init;
	const func = function(evt) {
		const $btn = $(evt.target);
		const $tar = $btn.rootfind( $btn.data('target') );

		const type = $btn[0].type;

		// radio button with data-state="0" or "1"
		if (type == 'radio') {
			if ($btn.prop("disabled") || !$btn.prop("checked")) return;
			let flag = $btn.data("state");
			if ($btn.hasClass('js-enable')) flag=!flag;
			$tar.prop('disabled', flag);
			return;
		}

		let flag;
		if (type == 'checkbox') {
			flag = !$btn.prop("disabled") && $btn.prop("checked");
		} else if (type == 'number' || $btn.data('type') == 'int') {
			var val = $btn.val();
			flag = val.length && val > 0;
		} else {
			flag = ! ($btn.val() + '').match(/^\s*$/);
		}

		// change flag?
		if (!init && $btn.data('_flag') === flag) return;
		$btn.data('_flag', flag);

		// disabled?
		const counter = $btn.hasClass('js-disable') ? '_disable_c' :  '_enable_c';
		const add     = flag ? 1 : (init ? 0 : -1);
		$tar.each(function(idx,dom){
			const $obj = $(dom);
			$obj.data(counter, ($obj.data(counter) || 0) + add);

			const diff = ($obj.data('_disable_c') || 0) - ($obj.data('_enable_c') || 0)
				   + ($btn.hasClass('js-enable') ? 0.1 : 0);

			$obj.prop('disabled', diff>0);
		});
	}
	// regist
	$objs.change( func );
	init = true;
	$objs.change();
	init = false;
});

////////////////////////////////////////////////////////////////////////////////
// click for dom show/hide
////////////////////////////////////////////////////////////////////////////////
/* example)
	<label><input type="checkbox" class="js-switch" data-target="xxx"></label>
	<button type="button" class="js-switch"  data-target="xxx"
	 data-delay="300"
	 data-hide-val="show it" data-show-val="hide it" data-negative="1">msg</button>
*/
(function(){
	function toggle($obj, init) {
		if ($obj[0].tagName == 'A') return true;	// link click

		// append switch icon
		if (init && $obj[0].tagName != 'INPUT' && $obj[0].tagName != 'BUTTON') {
			const $span = $('<span>');
			$span.addClass('ui-icon switch-icon');
			$obj.prepend($span).addClass('sw-show');
		}

		const type = $obj[0].tagName == 'INPUT' && $obj[0].type;
		let   tar  = $obj.data('target');
		if (!tar) {
			// $obj is children
			$obj = $obj.parentsOne(".js-switch");
			if (!$obj.length) return;
			tar = $obj.data('target');
		}
		const $target = $(tar);
		if (!$target.length) return false;

		// save switch status
		const storage = $obj.existsData('save') ? this.Storage : null;

		// get current state
		const id = $obj.attr('id') || $obj.attr('name') || tar;
		let flag;
		if (init && storage && storage.defined(id)) {
			flag = storage.getInt(id) ? true : false;
			if (type == 'checkbox' || type == 'radio') $obj.prop("checked", flag);
		} else if (type == 'checkbox' || type == 'radio') {
			flag = $obj.prop("checked");
		} else if (init && $obj.data('default') == 'show') {
			flag = true;
		} else if (init && $obj.data('default') == 'hide') {
			flag = false;
		} else {
			flag = init ? !$target.is(':hidden') : $target.is(':hidden');
		}
		if ($obj.data('negative')) flag = !flag;

		// show speed
		let delay = $obj.data('delay');
		if (delay === undefined || delay === '') delay = this.DefaultShowSpeed;

		// fast mode
		if ($obj.data('fast')) {
			const css_id = '--css--' + id.replace(/[^\w\-]/g, '-');
			let   $css   = $('#' + css_id);
			if (!$css.length) {
				$css = $('<style>').attr('id', css_id);
				$('head').append($css);
			}
			$css.text( flag ? '' : tar + '{ display: none; }' );
			return true;
		}

		// set state
		if (flag) {
			$obj.addClass('sw-show');
			$obj.removeClass('sw-hide');
			if (init) $target.show();
			     else $target.show(delay);
			if (storage) storage.set(id, '1');
		
		} else {
			$obj.addClass('sw-hide');
			$obj.removeClass('sw-show');
			if (init) $target.hide();
			     else $target.hide(delay);
			if (storage) storage.set(id, '0');
		}
		if (type == 'button') {
			const val = flag ? $obj.data('show-val') : $obj.data('hide-val');
			if (val != undefined) $obj.val( val );
		}
		return true;
	}

	$$.dom_init( function($R){
		const self = this;
		const func = function(evt){
			const $obj = $(evt.target);
			if ($obj[0].type != "radio")
				return toggle.call(self, $obj);

			const name = $obj.attr('name');
			$('input.js-switch[name=\"' + name + '"]').each(function(idx, dom){
				 toggle.call(self, $(dom));
			});
		}

		$R.findx('.js-switch').each( function(idx,dom) {
			const $obj = $(dom);
			const f    = toggle.call(self, $obj, true);	// init=true
			if (f) 	// initalize success
				$obj.on(dom.tagName == 'INPUT' ? 'change' : 'click', func);
		} );
	});
})();

////////////////////////////////////////////////////////////////////////////////
// accordion
////////////////////////////////////////////////////////////////////////////////
$$.dom_init(function($R){
	const $accordion = $R.findx('.js-accordion');
	if (!$accordion.length) return;
	$accordion.adiaryAccordion();
});

