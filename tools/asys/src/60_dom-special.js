//##############################################################################
// dom special extentions
//##############################################################################
// dom_init(func) で登録した処理は、範囲の要素（初めは document.body）を受け取る。
// 画面のJSが dom_init(要素) を呼ぶと、その中の部品を初期化する
(function(){
	const ary = [];
	let   initialized;

	$$.dom_init = function(func, priority) {
		if (typeof(func) == 'function') {
			if (initialized) {
				if (priority) console.warn('dom_init() initialized, but priority set', priority);
				func.call(this, document.body);
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

		const root = (func instanceof Node) ? func : document.body;
		for(var i=0; i<ary.length; i++)
			ary[i].func.call(this, root);

		initialized = true;
	};

	$$.init($$.dom_init);
})();

////////////////////////////////////////////////////////////////////////////////
// submit の処理を、決めた順に動かす（今までの onSequence）
////////////////////////////////////////////////////////////////////////////////
// どれかが false を返したら、そこで止めて、送らない
const submit_funcs = new WeakMap();
function on_submit(form, priority, func) {
	if (!submit_funcs.has(form)) {
		submit_funcs.set(form, []);
		form.addEventListener('submit', function(evt){
			for(const x of submit_funcs.get(form)) {
				if (x.func(evt)) continue;
				evt.preventDefault();
				evt.stopPropagation();
				return;
			}
		});
	}
	const list = submit_funcs.get(form);
	list.push({ priority: priority, func: func });
	list.sort(function(a,b){ return a.priority - b.priority });
}
// フォームの部品の状態（今までの jQuery の .data() に持っていたもの）
const form_state = new WeakMap();
function state_of(dom) {
	if (!form_state.has(dom)) form_state.set(dom, {});
	return form_state.get(dom);
}

////////////////////////////////////////////////////////////////////////////////
// submit checker
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function(R){
	const self=this;

	this.find_all(R, 'button.js-check-form').forEach(function(btn){ btn.addEventListener('click', function(evt){
		const obj  = evt.currentTarget;
		const form = obj.closest('form.js-check-form');
		if (!form) return;
		const st = state_of(form);
		// 今までと同じく、ボタンに無いときは前の値（なければフォームの data-*）のまま
		const confirm = self.data_value(obj, 'confirm');
		const focus   = self.data_value(obj, 'focus');
		if (confirm !== undefined) st.confirm = confirm;
		if (focus   !== undefined) st.focus   = focus;
		st.button = obj;
	}) });

	this.find_all(R, 'form.js-check-form').forEach(function(form){ on_submit(form, 10, function(evt){
		const st     = state_of(form);
		const target = self.data_value(form, 'target');
		let count=0;
		if (target) {
			count = self.rootfind( form, target + ":checked" ).length;
			if (!count) return false;	// no check
		}

		// confirm message
		let confirm = ('confirm' in st) ? st.confirm : self.data_value(form, 'confirm');
		if (!confirm) return true;
  		if (st._confirm_ok) {
  			st._confirm_ok = false;
  			return true;
  		}

		// confirm dialog
		confirm = confirm.toString().replace("%c", count);
		self.confirm({
			html:  confirm,
			focus: ('focus' in st) ? st.focus : self.data_value(form, 'focus')
		}, function(flag) {
			if (!flag) return;
  			st._confirm_ok = true;
			if (st.button) return st.button.click();

			// ふつうのsubmitのイベントを起こして送る
			form.requestSubmit();
		});
		return false;
	}) });
});

////////////////////////////////////////////////////////////////////////////////
// ajax form
////////////////////////////////////////////////////////////////////////////////
// <form class="js-ajax" data-url="送った後に開くURL" data-success="送った後に出すメッセージ" data-overlay="1">
// 送ったときにエラーがあれば、返事の errs の名前の欄に error のクラスを付ける
//
// 今までの jQuery の .serialize() と同じ形にする（ファイルとボタンは入れない、改行は CRLF）
function serialize(form) {
	const ary = [];
	for(const [k, v] of new FormData(form)) {
		if (typeof(v) !== 'string') continue;
		ary.push(encodeURIComponent(k) + '=' + encodeURIComponent(v.replace(/\r?\n/g, "\r\n")));
	}
	return ary.join('&');
}
$$.dom_init( function(R) {
	const self=this;
	const func = function(form){
		form.querySelectorAll('.error').forEach(function(x){ x.classList.remove('error') });

		const data = form.querySelector('input[type="file"]') ? new FormData(form) : serialize(form);

		const st = state_of(form);
		if (st.ajax_stop) return;
		st.ajax_stop = true;
		if (self.data_value(form, 'overlay'))
			st.overlay = self.overlay_show();

		self.send_ajax({
			data:	data,
			success: function(h) {
				const success = self.data_value(form, 'success');
				const url     = self.data_value(form, 'url');
				if (typeof(success) === 'string' && success != '') {
					return self.show_dialog(success, function(){
						if (url) window.location = url;
					});
				}
				if (url) window.location = url;
			},
			error: function(err, h) {
				if (!h || !h.errs) return;
				const e = h.errs;
				for(let k in e) {
					if (k == '_order') continue;

					// with number?
					const ma  = k.match(/^(.*)#(\d+)$/);
					const num = ma ? ma[2] : undefined;
					k = ma ? ma[1] : k;
					try {
						let x = Array.from( form.querySelectorAll('[name="' + k+ '"], [data-name="' + k + '"]') );
						if (num) x = x[num-1] ? [ x[num-1] ] : [];
						x.forEach(function(y){ y.classList.add('error') });
					} catch(e) {
						console.error(e);
					}
				}
			},
			complete: function() {
				st.ajax_stop = false;
				if (st.overlay) st.overlay.remove();
				st.overlay = null;
			}
		});
	};

	R.querySelectorAll('form.js-ajax').forEach(function(form){ on_submit(form, 100, function(evt) {
		func(form);
		return false;
	}) });
});

////////////////////////////////////////////////////////////////////////////////
// auto save form value
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function(R) {
	const self = this;

	this.find_all(R, 'input.js-save, select.js-save').forEach( function(dom) {
		const type = dom.type;

		// 名前が無いときは、今までと同じく "name=undefined"
		let id = type != 'radio' && dom.getAttribute("id");
		if (!id) id = 'name=' + (dom.getAttribute("name") ?? undefined);

		if (type == 'checkbox') {
			self.on_change(dom, function(evt){
				self.Storage.set(id, dom.checked ? 1 : 0);
			});
			if ( self.Storage.defined(id) )
				dom.checked = self.Storage.get(id) != 0;
			return;
		}
		if (type == 'radio') {
			const val = dom.getAttribute('value');
			self.on_change(dom, function(evt){
				self.Storage.set(id, val);
			});
			if ( self.Storage.defined(id) && val == self.Storage.get(id)) {
				dom.checked = true;
			}
			return;
		}
		self.on_change(dom, function(evt){
			if (dom.value == self.js_combo_dummy_val) return;
			self.Storage.set(id, dom.value);
		});
		const val = self.Storage.get(id);
		if (! val) return;
		if (dom.tagName == 'SELECT')
			return self.set_value_on_select( dom, val );

		dom.value = val;
	});
});

////////////////////////////////////////////////////////////////////////////////
// form dom element enable/disable by other form elements
////////////////////////////////////////////////////////////////////////////////
$$.dom_init( function(R){
	const self = this;
	const objs = this.find_all(R, 'input.js-enable, input.js-disable, select.js-enable, select.js-disable');

	let   init;
	const func = function(evt) {
		const btn  = evt.target;
		const tars = self.rootfind( btn, self.data_value(btn, 'target') );
		const type = btn.type;

		// radio button with data-state="0" or "1"
		if (type == 'radio') {
			if (btn.disabled || !btn.checked) return;
			let flag = self.data_value(btn, 'state');
			if (btn.classList.contains('js-enable')) flag=!flag;
			tars.forEach(function(x){ x.disabled = !!flag });
			return;
		}

		let flag;
		if (type == 'checkbox') {
			flag = !btn.disabled && btn.checked;
		} else if (type == 'number' || self.data_value(btn, 'type') == 'int') {
			var val = btn.value;
			flag = val.length && val > 0;
		} else {
			flag = ! (btn.value + '').match(/^\s*$/);
		}

		// change flag?
		const st = state_of(btn);
		if (!init && st._flag === flag) return;
		st._flag = flag;

		// disabled?
		const counter = btn.classList.contains('js-disable') ? '_disable_c' :  '_enable_c';
		const add     = flag ? 1 : (init ? 0 : -1);
		tars.forEach(function(dom){
			const s = state_of(dom);
			s[counter] = (s[counter] || 0) + add;

			const diff = (s._disable_c || 0) - (s._enable_c || 0)
				   + (btn.classList.contains('js-enable') ? 0.1 : 0);

			dom.disabled = diff>0;
		});
	}
	// regist。今までと同じく、初めに1回、asysの部品のchangeの処理を呼ぶ
	objs.forEach(function(x){ self.on_change(x, func) });
	init = true;
	objs.forEach(function(x){ self.fire_change(x) });
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
	// jQueryの:hidden（表示の大きさが無い）
	function hidden(dom) {
		return !(dom.offsetWidth || dom.offsetHeight || dom.getClientRects().length);
	}
	function toggle(obj, init) {
		if (obj.tagName == 'A') return true;	// link click

		// append switch icon
		if (init && obj.tagName != 'INPUT' && obj.tagName != 'BUTTON') {
			const span = document.createElement('span');
			span.className = 'ui-icon switch-icon';
			obj.prepend(span);
			obj.classList.add('sw-show');
		}

		const type = obj.tagName == 'INPUT' && obj.type;
		let   tar  = this.data_value(obj, 'target');
		if (!tar) {
			// obj is children
			obj = obj.parentElement && obj.parentElement.closest(".js-switch");
			if (!obj) return;
			tar = this.data_value(obj, 'target');
		}
		const targets = Array.from( document.querySelectorAll(tar) );
		if (!targets.length) return false;

		// save switch status
		const storage = obj.hasAttribute('data-save') ? this.Storage : null;

		// get current state
		const id = obj.getAttribute('id') || obj.getAttribute('name') || tar;
		let flag;
		if (init && storage && storage.defined(id)) {
			flag = storage.getInt(id) ? true : false;
			if (type == 'checkbox' || type == 'radio') obj.checked = flag;
		} else if (type == 'checkbox' || type == 'radio') {
			flag = obj.checked;
		} else if (init && this.data_value(obj, 'default') == 'show') {
			flag = true;
		} else if (init && this.data_value(obj, 'default') == 'hide') {
			flag = false;
		} else {
			const any_hidden = targets.some(hidden);
			flag = init ? !any_hidden : any_hidden;
		}
		if (this.data_value(obj, 'negative')) flag = !flag;

		// show speed
		let delay = this.data_value(obj, 'delay');
		if (delay === undefined || delay === '') delay = this.DefaultShowSpeed;

		// fast mode
		if (this.data_value(obj, 'fast')) {
			const css_id = '--css--' + id.replace(/[^\w\-]/g, '-');
			let   css    = document.getElementById(css_id);
			if (!css) {
				css = document.createElement('style');
				css.setAttribute('id', css_id);
				document.head.appendChild(css);
			}
			css.textContent = flag ? '' : tar + '{ display: none; }';
			return true;
		}

		// set state
		const self = this;
		if (flag) {
			obj.classList.add('sw-show');
			obj.classList.remove('sw-hide');
			targets.forEach(function(x){ init ? self.show(x) : self.show_delay(x, delay) });
			if (storage) storage.set(id, '1');

		} else {
			obj.classList.add('sw-hide');
			obj.classList.remove('sw-show');
			targets.forEach(function(x){ init ? self.hide(x) : self.hide_delay(x, delay) });
			if (storage) storage.set(id, '0');
		}
		if (type == 'button') {
			const val = flag ? this.data_value(obj, 'show-val') : this.data_value(obj, 'hide-val');
			if (val != undefined) obj.value = val;
		}
		return true;
	}

	$$.dom_init( function(R){
		const self = this;
		// 今までと同じく、押した要素（中の要素のときもある）から探す。false のときは止める
		const func = function(evt){
			const obj = evt.target;
			let ret;
			if (obj.type != "radio") {
				ret = toggle.call(self, obj);
			} else {
				const name = obj.getAttribute('name');
				document.querySelectorAll('input.js-switch[name="' + name + '"]').forEach(function(dom){
					 toggle.call(self, dom);
				});
			}
			if (ret === false) {
				evt.preventDefault();
				evt.stopPropagation();
			}
		}

		this.find_all(R, '.js-switch').forEach( function(dom) {
			const f = toggle.call(self, dom, true);	// init=true
			if (!f) return;		// initalize failed
			if (dom.tagName == 'INPUT') self.on_change(dom, func);
				else		    dom.addEventListener('click', func);
		} );
	});
})();

////////////////////////////////////////////////////////////////////////////////
// accordion
////////////////////////////////////////////////////////////////////////////////
// 見出しを押すと、すぐ後の div を開け閉めする。初めは閉じる
$$.dom_init(function(R){
	const self = this;
	this.find_all(R, '.js-accordion').forEach(function(acc){
		const heads = Array.from(acc.children).filter(function(x){ return x.matches('h1,h2,h3,h4,h5,h6') });
		const next_div = function(x) {
			const n = x.nextElementSibling;
			return (n && n.tagName == 'DIV') ? n : null;
		};
		heads.forEach(function(h){
			h.addEventListener('click', function(evt){
				const div = next_div(evt.target);
				if (!div) return;
				self.toggle_delay(div);
			});
		});
		heads.forEach(function(h){
			const div = next_div(h);
			if (div) self.hide(div);
		});
	});
});
