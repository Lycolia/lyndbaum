// 記事の目次（[*toc]）より下までスクロールしたら、本文の枠の右上に「目次」のボタンを出し、押すと目次を開く
//   画面の幅によらず同じ動き。ボタンは本文の枠（.article-main）の中で追従する（lyndbaum.cssの.toc-float）
//   目次の中身は、本文の目次を写して使う。JavaScriptが無いときは出さない
//   読み込むのは記事のページだけ（theme/lyndbaum/_skel/_article.html）
'use strict';
(function () {
	var main = document.querySelector('.article-main');
	var source = main && main.querySelector('.article-body ul.toc');
	if (!source || !window.IntersectionObserver) return;

	var bar = document.createElement('div');
	bar.className = 'toc-float';
	var button = document.createElement('button');
	button.type = 'button';
	button.className = 'toc-float-button';
	button.setAttribute('aria-controls', 'toc-float-panel');
	button.setAttribute('aria-expanded', 'false');
	button.innerHTML = '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M4 5.333h2.667V8H4zM9.333 5.333H20V8H9.333zM4 10.667h2.667v2.666H4zM9.333 10.667H20v2.666H9.333zM4 16h2.667v2.667H4zM9.333 16H20v2.667H9.333z"/></svg>目次';
	var panel = document.createElement('nav');
	panel.className = 'toc-float-panel';
	panel.id = 'toc-float-panel';
	panel.setAttribute('aria-label', '目次');
	panel.hidden = true;
	panel.appendChild(source.cloneNode(true));
	bar.appendChild(button);
	bar.appendChild(panel);
	main.insertBefore(bar, main.firstChild);

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
