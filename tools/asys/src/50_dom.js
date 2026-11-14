//##############################################################################
// dom extentions
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// popup-help
////////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const self = this;
	this.popup_on('.help[data-help]', {
		show: function(obj, div){
			const text = self.tag_esc_br( obj.dataset.help );
			div.classList.add('popup', 'popup-help');
			div.innerHTML = text;
		}
	});
});

////////////////////////////////////////////////////////////////////////////////
// no enter submit
////////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	document.body.addEventListener('keypress', function(evt){
		if (evt.which !== 13) return;
		if (!evt.target.closest || !evt.target.closest('input.no-enter-submit, form.no-enter-submit input')) return;
		evt.preventDefault();
		evt.stopPropagation();
	});
});

////////////////////////////////////////////////////////////////////////////////
// file upload button
////////////////////////////////////////////////////////////////////////////////
// <button class="js-file-btn" data-target="#fileup">
// <input type="file" id="fileup" style="display:none" data-target="#file-list">
// <span id="file-list"></span>
//
$$.init(function(){
	const self = this;
	const registered = new WeakSet();
	document.body.addEventListener('click', function(evt) {
		const obj = evt.target.closest && evt.target.closest('button.js-file-btn');
		if (!obj) return;
		const sel = self.data_value(obj, 'target');
		const tar = sel && document.querySelector(sel);
		if (!tar) return;

		if (self.data_value(tar, 'target') && !registered.has(tar)) {
			registered.add(tar);
			tar.addEventListener('change', function(evt){
				const file = tar.value.replace(/^.*?([^\\\/]*)$/, "$1");
				self.rootfind( tar, self.data_value(tar, 'target') ).forEach(function(x){ x.textContent = file });
			});
		}
		tar.click();
	});
});

////////////////////////////////////////////////////////////////////////////////
// check all
////////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const self = this;
	document.body.addEventListener('change', function(evt){
		const obj = evt.target.closest && evt.target.closest('input.js-checked');
		if (!obj) return;
		const checked = obj.checked;
		document.querySelectorAll( self.data_value(obj, 'target') ).forEach(function(x){ x.checked = checked });
	});
});

////////////////////////////////////////////////////////////////////////////////
// combo box
////////////////////////////////////////////////////////////////////////////////
// used by select.js-save
// select に値を入れる。無い値のときは option を足す。入れた後に change を起こす
$$.js_combo_dummy_val  = "\e\e\e\e\e\n\n";
$$.set_value_on_select = function(select, val) {
	select.value = val;
	if (select.value != val) {
		const format = this.data_value(select, 'format') || '%v';
		const text = format.replace(/%v/g, val);
		const opt  = document.createElement('option');
		opt.setAttribute('value', val);
		opt.textContent = text;
		select.appendChild( opt );
		select.value = val;
	}
	select.dispatchEvent(new Event('change', { bubbles: true }));
}

$$.init(function(){
	const self    = this;
	const dummy   = this.js_combo_dummy_val;
	const current = new WeakMap();

	function change_select(evt) {
		const select = evt.target;
		const val    = select.value;

		if (val !== dummy)
			return current.set(select, val);
		select.value = current.get(select);

		const src = document.querySelector( self.data_value(select, 'target') );
		if (!src) return;
		const target = src.cloneNode(true);
		target.removeAttribute('id');
		target.querySelectorAll('input').forEach(function(x){ x.setAttribute('name', 'data') });

		self.form_dialog({
			title: self.data_value(target, 'title'),
			elements: [
				{ type: '*', html: target }
			],
			callback: function(h) {
				const val = h.data;
				if (val == '' || select.value == val) return;

				self.set_value_on_select( select, val );
				current.set(select, val);
			}
		});
	}

	// initalize（初めて focus したときに「その他」を足す）
	document.body.addEventListener('focusin', function(evt){
		const obj = evt.target.closest && evt.target.closest('select.js-combo');
		if (!obj) return;
		current.set(obj, obj.value);

		if (Array.from(obj.options).some(function(x){ return x.value === dummy })) return;
		// add other option
		const opt = document.createElement('option');
		opt.setAttribute('value', dummy);
		opt.textContent = self.msg('other');
		obj.appendChild( opt );

		obj.addEventListener('change', change_select );
	});
})
