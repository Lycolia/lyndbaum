//##############################################################################
// 記事ヘッダ加工用
//							(C)2015 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';

(function(func) {
	if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', func);
	else func();
})(function() {
	document.querySelectorAll('#main-first article.article').forEach(function(art){
		const h1   = art.querySelector('h1');
		const head = art.querySelector('div.body-header');
		if (h1 && head) {
			const date = h1.querySelector('a.date');
			if (date) h1.appendChild(date);
			h1.appendChild(head);
		}
		const bookmark = h1 && h1.querySelector('a.http-bookmark');
		if (bookmark) {
			h1.appendChild(bookmark);
		}
	});
});
