// 管理画面で共通に使う処理
//   選択肢と「直接入力」の欄で、「直接入力」を選んだときだけ数の欄を出す
//   data-confirm を付けたボタンで送るときに、確かめる（取り消せない操作や、押し間違えやすい操作）
//   文の %c は、フォームで選んだ（チェックを入れた）項目の数に置き換える。1つも選んでいなければ送らない
'use strict';
(function () {
	// 選択肢と「直接入力」の欄（templates/preset_field.html）。「直接入力」を選んだときだけ、数を入れる欄を出す
	document.addEventListener('change', function (evt) {
		var select = evt.target;
		if (!select.classList || !select.classList.contains('preset-select')) return;
		var other = select.nextElementSibling;
		if (!other || !other.classList.contains('preset-other')) return;
		other.hidden = select.value !== 'other';
		if (!other.hidden) other.querySelector('input').focus();
	});

	document.addEventListener('submit', function (evt) {
		var button = evt.submitter;
		if (!button || !button.dataset.confirm) return;
		var message = button.dataset.confirm;
		if (message.indexOf('%c') !== -1) {
			var count = evt.target.querySelectorAll('input[name="id"]:checked').length;
			if (!count) {
				window.alert('記事を選んでください。');
				evt.preventDefault();
				return;
			}
			message = message.replace('%c', count);
		}
		if (!window.confirm(message)) evt.preventDefault();
	});
})();
