// 管理画面のサイドバーの自由欄で、欄を上下に動かす（保存を押すまで確定しない）
//   JavaScript が無くても、保存と追加はできる（並べ替えだけができない）
'use strict';
(function () {
	var form = document.querySelector('.sidebar-boxes');
	if (!form) return;
	form.querySelectorAll('.sidebar-box-move').forEach(function (p) { p.hidden = false; });
	form.addEventListener('click', function (evt) {
		var button = evt.target.closest('button[data-move]');
		if (!button) return;
		var box = button.closest('.sidebar-box-edit');
		if (button.dataset.move === '-1') {
			var prev = box.previousElementSibling;
			if (prev && prev.classList.contains('sidebar-box-edit')) form.insertBefore(box, prev);
		} else {
			var next = box.nextElementSibling;
			if (next && next.classList.contains('sidebar-box-edit')) form.insertBefore(next, box);
		}
		button.focus();
	});
})();
