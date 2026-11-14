//##############################################################################
// run init
//##############################################################################
// 初期化（と、$(func) で登録した処理）は、DOMContentLoaded の後に動かす。
// asys.min.js は defer で読むので、実行の時にはページの解析が終わっていて、jQuery は
// setTimeout で ready を決める。後ろの defer のファイル（adiary.js、admin.js、画面のJS）の
// 読み込みが遅いと、その合間に初期化が動き、window.adiary がずれてしまう
// （adiary.js が $$ を上書きする、画面のJSを実行する時に window.adiary がもう $$ になっている）。
// defer のファイルは、どれも DOMContentLoaded の前に実行し終わる。
// holdReady は jQuery 3.2 で非推奨だが、3.6 にはある。jQuery を外すときには要らなくなる
if (document.readyState !== 'complete') {
	let held = true;
	const release = function(){
		if (!held) return;
		held = false;
		$.holdReady(false);
	};
	$.holdReady(true);
	document.addEventListener('DOMContentLoaded', release);
	window.addEventListener('load', release);	// DOMContentLoaded の後に読み込まれたとき
}
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
