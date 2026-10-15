// コメントのフォームに、署名つきのトークンを入れる
//   JavaScriptを動かさないボットをはじくため。サーバーは、このトークンが無い投稿を受け付けない
'use strict';
(function () {
	var form = document.getElementById('comment-form');
	if (!form || !form.dataset.token) return;
	form.elements.token.value = form.dataset.token;
})();
