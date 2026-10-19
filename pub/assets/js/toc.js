// 記事の目次（[*toc]）より下までスクロールしたら、本文の枠の右上に「目次」のボタンを出し、押すと目次を開く
//   画面の幅によらず同じ動き。ボタンは本文の枠（.article-main）の中で追従する（site.css の .toc-float）
//   目次の中身は、本文の目次を写して使う。JavaScript が無いときは出さない
'use strict';
(function () {
	var main = document.querySelector('.article-main');
	var source = main && main.querySelector('.article-body .toc');
	if (!source || !window.IntersectionObserver) return;
	var root = document.documentElement;

	var bar = document.createElement('div');
	bar.className = 'toc-float';
	var button = document.createElement('button');
	button.type = 'button';
	button.className = 'toc-float-button';
	button.setAttribute('aria-controls', 'toc-float-panel');
	button.setAttribute('aria-expanded', 'false');
	button.innerHTML = '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16"/></svg>目次';
	var panel = document.createElement('nav');
	panel.className = 'toc-float-panel';
	panel.id = 'toc-float-panel';
	panel.setAttribute('aria-label', '目次');
	panel.hidden = true;
	panel.appendChild(source.cloneNode(true));
	bar.appendChild(button);
	bar.appendChild(panel);
	main.insertBefore(bar, main.firstChild);

	// 管理者のメニュー（上に貼り付く）があれば、その下に出す
	var adminBar = document.querySelector('.admin-bar');
	function updateTop() {
		root.style.setProperty('--toc-float-top', (adminBar ? adminBar.offsetHeight : 0) + 'px');
	}
	updateTop();
	window.addEventListener('resize', updateTop);

	function close(restoreFocus) {
		if (panel.hidden) return;
		panel.hidden = true;
		button.setAttribute('aria-expanded', 'false');
		if (restoreFocus) button.focus();
	}
	function open() {
		panel.hidden = false;
		button.setAttribute('aria-expanded', 'true');
	}
	button.addEventListener('click', function () {
		if (panel.hidden) open();
		else close(false);
	});
	// 目次のリンクで移ったら閉じる
	panel.addEventListener('click', function (evt) {
		if (evt.target.closest('a')) close(false);
	});
	document.addEventListener('click', function (evt) {
		if (!bar.contains(evt.target)) close(false);
	});
	document.addEventListener('keydown', function (evt) {
		if (evt.key === 'Escape' && !panel.hidden) close(true);
	});

	// 本文の目次が画面の上へ抜けたら見せ、戻ってきたら隠す（下にあって、まだ見えていないときも隠す）
	new IntersectionObserver(function (entries) {
		var entry = entries[entries.length - 1];
		var passed = !entry.isIntersecting && entry.boundingClientRect.bottom < 0;
		bar.classList.toggle('is-shown', passed);
		if (!passed) close(false);
	}).observe(source);
})();
