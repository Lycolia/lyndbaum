//##############################################################################
// run init
//##############################################################################
$(function(){
	(function() {
		this.$head = $('head');
		this.$body = $('body');

		const $vars = $secure('#asys-vars');
		if ($vars.length) {
			const json = $vars.html().replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
			const data = JSON.parse(json);
			const ary  = ['name', 'Initialize', 'myself', 'myself2', 'Basepath'];
			for(var i=0; i<ary.length; i++) {
				if (ary[i] in data)
					this[ary[i]] = data[ary[i]];
			}
			this.asys_vars = data;
		}
		this.load_msg($secure('#asys-msgs'));

		// PrefixStorage
		this.Storage = new PrefixStorage( this.myself || '/' );

		// global export
		window[this.name] = this;

		// initalize
		if (this.Initialize !== false) this.init();
	}).call($$)
});
