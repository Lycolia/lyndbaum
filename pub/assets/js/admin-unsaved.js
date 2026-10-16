// 保存していない変更があるまま画面を離れるとき（タブを閉じる、再読み込み、リンク、戻るなど）に確かめる
//   data-unsaved-warning を付けたフォームが対象。開いたときの中身を覚えておき、離れるときに今の中身と比べる
//   （書き換えても元に戻せば確かめない。タグのチップなど、JavaScript で変えた欄も比べる）
//   data-unsaved-warning="unsaved" なら、開いたときから保存していないものとして扱う（保存できずに戻ってきた画面）
//   このページのフォームを送るときは確かめない。確かめる文言はブラウザーが決める（ページからは変えられない）
'use strict';
(function () {
	var forms = Array.prototype.slice.call(document.querySelectorAll('form[data-unsaved-warning]'));
	if (!forms.length) return;
	var initial = [];
	var submitting = false;

	// 名前のある欄の値を並べたもの。ファイルの欄は比べない
	function snapshot(form) {
		var pairs = [];
		new FormData(form).forEach(function (value, name) {
			if (typeof value === 'string') pairs.push([name, value]);
		});
		return JSON.stringify(pairs);
	}

	function changed() {
		return forms.some(function (form, i) {
			return form.dataset.unsavedWarning === 'unsaved' || snapshot(form) !== initial[i];
		});
	}

	// ほかのスクリプト（defer）が欄を整えた後の中身を覚える
	function remember() { initial = forms.map(snapshot); }
	if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', remember);
	else remember();

	// 送るのを取りやめたとき（data-confirm で「キャンセル」など）は、確かめる対象のまま。
	// document の処理（pub/assets/js/admin.js）の後に見るため、window で受ける
	window.addEventListener('submit', function (evt) {
		if (!evt.defaultPrevented) submitting = true;
	});
	// 送った後に「戻る」で戻ってきたとき（bfcache）は、また確かめる
	window.addEventListener('pageshow', function (evt) {
		if (evt.persisted) submitting = false;
	});
	window.addEventListener('beforeunload', function (evt) {
		if (submitting || !changed()) return;
		evt.preventDefault();
		evt.returnValue = '';
	});
})();
