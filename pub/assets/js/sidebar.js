// サイドバーを引き出しにして、ヘッダーのボタンで開く。1カラムでは左右、2カラムでは左だけ
//   ボタンとサイドバーは layout.html、見た目と切り替わる幅は style.css（48rem 未満と 72rem 未満）
//   JavaScript が無いときはボタンを出さず、サイドバーは本文の下に縦に並ぶ
'use strict';
(function () {
	var buttons = document.querySelectorAll('.sidebar-toggle');
	if (!buttons.length) return;
	var root = document.documentElement;
	var breakpoints = ['(min-width: 48rem)', '(min-width: 72rem)'].map(function (q) { return window.matchMedia(q); });
	var backdrop = document.createElement('div');
	backdrop.className = 'drawer-backdrop';
	backdrop.hidden = true;
	document.body.appendChild(backdrop);
	var current = null;   // 開いているボタン

	function drawerOf(button) { return document.getElementById(button.getAttribute('aria-controls')); }

	function close(restoreFocus) {
		if (!current) return;
		var button = current;
		current = null;
		drawerOf(button).classList.remove('is-open');
		button.setAttribute('aria-expanded', 'false');
		root.classList.remove('drawer-open');
		backdrop.hidden = true;
		if (restoreFocus) button.focus();
	}

	function open(button) {
		close(false);
		var drawer = drawerOf(button);
		current = button;
		drawer.classList.add('is-open');
		button.setAttribute('aria-expanded', 'true');
		root.classList.add('drawer-open');
		backdrop.hidden = false;
		drawer.focus({ preventScroll: true });
	}

	buttons.forEach(function (button) {
		var drawer = drawerOf(button);
		if (!drawer) return;
		drawer.tabIndex = -1;   // 開いたときに、引き出しへフォーカスを移す
		button.hidden = false;
		button.addEventListener('click', function () {
			if (current === button) close(true);
			else open(button);
		});
	});
	root.classList.add('has-drawer');

	backdrop.addEventListener('click', function () { close(true); });
	document.addEventListener('keydown', function (evt) {
		if (evt.key === 'Escape' && current) close(true);
	});
	// カラムの数が変わったら閉じておく（開いていた引き出しが、横に並ぶサイドバーに戻ることがある）
	breakpoints.forEach(function (mq) { mq.addEventListener('change', function () { close(false); }); });
	// 引き出しのリンクで移ってから戻ったとき（bfcache）に、開いたままにしない
	window.addEventListener('pageshow', function (evt) { if (evt.persisted) close(false); });
})();
