//##############################################################################
// run init
//##############################################################################
// 初期化は、DOMContentLoaded の後の別の回（setTimeout）に動かす。順番は次のとおり。
//	1. 公開画面の初期化（adiary.js。DOMContentLoaded のとき）
//	2. asys の初期化（下の boot。window.adiary を asys に置き換える）
//	3. ready で登録した処理を、登録した順に（admin.js、画面のJS。動いている間に足したもの
//	   （<script-defer> の実行）は最後に動く）
// asys.min.js は defer で読む。defer のファイルを実行するときは、readyState はもう interactive。
// 後ろの defer のファイル（adiary.js、admin.js、画面のJS）は、どれも DOMContentLoaded の前に
// 実行し終わるので、DOMContentLoaded を待つ（すぐに動かすと、後ろのファイルより先に動くことがある）
(function(){
	const queue = [];
	let   done;

	// 初期化の後に動かす（初期化の後に登録したときは、すぐ動かす）
	$$.ready = function(func) {
		if (done) return func.call(this);
		queue.push(func);
	};

	function boot() {
		(function() {
			const vars = document.getElementById('asys-vars');
			if (vars) {
				const json = vars.innerHTML.replace(/^[\s\S]*?{/, '{').replace(/}[\s\S]*?$/, '}');
				const data = JSON.parse(json);
				const ary  = ['name', 'Initialize', 'myself', 'myself2', 'Basepath'];
				for(var i=0; i<ary.length; i++) {
					if (ary[i] in data)
						this[ary[i]] = data[ary[i]];
				}
				this.asys_vars = data;
			}
			this.load_msg('#asys-msgs');

			// PrefixStorage
			this.Storage = new PrefixStorage( this.myself || '/' );

			// global export
			window[this.name] = this;

			// initalize
			if (this.Initialize !== false) this.init();
		}).call($$);

		while(queue.length) {
			const func = queue.shift();
			try {
				func.call($$);
			} catch(e) {
				console.error(e);
			}
		}
		done = true;
	}
	let started;
	function start() {
		if (started) return;
		started = true;
		setTimeout(boot, 0);
	}
	if (document.readyState !== 'complete') {
		document.addEventListener('DOMContentLoaded', start);
		window.addEventListener('load', start);		// DOMContentLoaded の後に読み込まれたとき
	} else
		start();
})();
