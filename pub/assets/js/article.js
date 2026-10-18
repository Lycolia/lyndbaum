// 公開側のページで、コードの色付け（Prism.js）をする（旧システムと同じ）
//   ライブラリは pub/assets/js/extlib/。読み込みは layout.html（defer で、この順に動く）
//   画像の拡大表示（Lythumb）は、読み込むと自分で動くので、ここでは何もしない
'use strict';
(function () {
	// コードの色付け。Prism は data-manual で自動では動かさず、言語の名前を整えてから動かす
	//   言語の無いコード（class="language-"）は language-none（色は付けず、行番号とコピーのボタンだけ）
	var ALIASES = { sh: 'bash', bat: 'batch', cmd: 'batch', pwsh: 'powershell', ps1: 'powershell', 'c#': 'csharp' };
	document.querySelectorAll('pre > code').forEach(function (code) {
		var match = code.className.match(/(?:^|\s)language-([\w+#-]+)/);
		var name = match ? match[1].toLowerCase() : '';
		var lang = name === '' ? 'none' : ALIASES[name] || name;
		code.className = code.className.replace(/(?:^|\s)language-[\w+#-]*/g, '').trim();
		code.classList.add('language-' + lang);
		code.parentNode.classList.add('line-numbers');
	});
	if (window.Prism) window.Prism.highlightAll();
})();
