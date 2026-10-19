// 管理画面の記事の編集
//   - タグの入力：付けたタグを札で並べ、入力に合わせて今あるタグの候補を出す（docs/admin.md の「タグの入力」）
//   - ファイルのアップロード：選ぶ、本文の欄に落とす、貼り付ける。返った記法をカーソルの位置に入れる
//     「ファイル一覧から選択」で、前に上げたファイルを選んで入れる（admin-media.js）
//   - 更新履歴：版を取りに行き、今の本文（編集の欄）との行の差分か全文を出す。版を本文に読み込む（保存するまで確定しない）
//   （「公開する」を押したときの確認は admin.js の data-confirm）
'use strict';
(function () {
	var form = document.querySelector('form.article-edit');
	if (!form) return;

	initRevisions(form);
	initUpload(form);
	initOgp(form);

	//----------------------------------------------------------------------
	// タグの入力
	//----------------------------------------------------------------------
	var editor = form.querySelector('.tag-editor');
	if (!editor) return;
	var tags;   // [{ name: '親::子', count: 使っている記事の数 }, ...]
	try {
		tags = JSON.parse(editor.dataset.tags);
	} catch (e) {
		return;
	}
	tags.forEach(function (t) { t.lc = t.name.toLowerCase(); });
	var names  = {};   // 今あるタグの名前（小文字にしたもの）
	tags.forEach(function (t) { names[t.lc] = true; });
	var chips  = editor.querySelector('.tag-chips');
	var input  = editor.querySelector('.tag-input');
	var list   = editor.querySelector('.tag-candidates');
	var select = editor.querySelector('.tag-select');
	var MAX = 20;

	// 書いた名前を整える（:: の前後の空白を除く）。書き方が正しくなければ null
	function normalize(text) {
		var parts = text.split('::').map(function (s) { return s.trim(); });
		if (parts.some(function (s) { return s === ''; }) || text.indexOf(',') !== -1) return null;
		return parts.join('::');
	}

	// 付けているタグの名前
	function added() {
		var map = {};
		chips.querySelectorAll('input[type="hidden"]').forEach(function (i) { map[i.value] = true; });
		return map;
	}

	// 札を足す。isNew なら新しいタグとして送る（サーバーはこのときだけタグを作る）
	function addChip(name, isNew) {
		if (added()[name]) return;
		var li = document.createElement('li');
		li.className = 'tag-chip' + (isNew ? ' tag-chip-new' : '');
		var hidden = document.createElement('input');
		hidden.type = 'hidden';
		hidden.name = isNew ? 'new_tag' : 'tag';
		hidden.value = name;
		li.appendChild(hidden);
		if (isNew) {
			var mark = document.createElement('span');
			mark.className = 'tag-chip-mark';
			mark.textContent = '新';
			li.appendChild(mark);
		}
		var label = document.createElement('span');
		label.className = 'tag-chip-name';
		label.textContent = name;
		li.appendChild(label);
		var remove = document.createElement('button');
		remove.type = 'button';
		remove.className = 'tag-chip-remove';
		remove.setAttribute('aria-label', '「' + name + '」を外す');
		remove.textContent = '×';
		li.appendChild(remove);
		chips.appendChild(li);
	}

	chips.addEventListener('click', function (evt) {
		var button = evt.target.closest('.tag-chip-remove');
		if (!button) return;
		button.closest('.tag-chip').remove();
		update();
		input.focus();
	});

	// 候補の順位：名前が完全に一致 > どの語も階層のどれかの名前の先頭に一致 > それ以外
	function rank(t, lc, words) {
		if (t.lc === lc) return 2;
		var segs = t.lc.split('::');
		return words.every(function (w) {
			return segs.some(function (s) { return s.indexOf(w) === 0; });
		}) ? 1 : 0;
	}

	// 入力に合わせて候補を作り直す。空白で区切った語をすべて含むタグを、順位、使っている記事の数の順に並べる
	function update() {
		list.textContent = '';
		var text  = input.value.trim();
		var lc    = text.toLowerCase();
		var words = lc.split(/\s+/).filter(function (w) { return w !== ''; });
		if (!words.length) return;
		var now = added();
		var hits = tags.filter(function (t) {
			return !now[t.name] && words.every(function (w) { return t.lc.indexOf(w) !== -1; });
		});
		hits.forEach(function (t) { t.rank = rank(t, lc, words); });
		hits.sort(function (a, b) { return (b.rank - a.rank) || (b.count - a.count); });
		hits.slice(0, MAX).forEach(function (t) {
			var li = candidate(t.name, false);
			var name = document.createElement('span');
			name.textContent = t.name;
			var count = document.createElement('span');
			count.className = 'tag-count';
			count.textContent = t.count;
			li.appendChild(name);
			li.appendChild(count);
			list.appendChild(li);
		});
		// 今あるタグに一致しなければ、新しいタグとして足す候補を最後に出す
		// （大文字と小文字だけが違う名前は、今あるタグとみなして出さない）
		var name = normalize(text);
		if (name !== null && !names[name.toLowerCase()] && !now[name]) {
			var li = candidate(name, true);
			li.className = 'tag-candidate-new';
			li.textContent = '「' + name + '」を新規タグとして追加';
			list.appendChild(li);
		}
		choose(list.firstElementChild);
	}

	function candidate(name, isNew) {
		var li = document.createElement('li');
		li.setAttribute('role', 'option');
		li.dataset.name = name;
		if (isNew) li.dataset.new = '1';
		return li;
	}

	function choose(li) {
		list.querySelectorAll('[aria-selected="true"]').forEach(function (e) { e.setAttribute('aria-selected', 'false'); });
		if (!li) return;
		li.setAttribute('aria-selected', 'true');
		li.scrollIntoView({ block: 'nearest' });
	}

	function move(dir) {
		var items = Array.prototype.slice.call(list.children);
		if (!items.length) return;
		var cur = items.findIndex(function (e) { return e.getAttribute('aria-selected') === 'true'; });
		choose(items[(cur + dir + items.length) % items.length]);
	}

	// 候補を足して、続けて入力できるようにする
	function take(li) {
		if (!li) return;
		addChip(li.dataset.name, li.dataset.new === '1');
		input.value = '';
		update();
		input.focus();
	}

	input.addEventListener('input', update);
	input.addEventListener('keydown', function (evt) {
		if (evt.isComposing || evt.keyCode === 229) return;   // IMEで変換している間は何もしない
		if (evt.key === 'ArrowDown') { move(1); evt.preventDefault(); }
		else if (evt.key === 'ArrowUp') { move(-1); evt.preventDefault(); }
		else if (evt.key === 'Enter') {
			evt.preventDefault();   // フォームを送らない
			take(list.querySelector('[aria-selected="true"]'));
		}
	});
	list.addEventListener('click', function (evt) {
		take(evt.target.closest('li'));
	});
	select.addEventListener('change', function () {
		if (select.value !== '') addChip(select.value, false);
		select.value = '';
		update();
	});

	//----------------------------------------------------------------------
	// 更新履歴
	//----------------------------------------------------------------------
	function initRevisions(form) {
		var box = document.querySelector('.revisions');
		if (!box) return;
		var body    = form.elements.body;
		var view    = box.querySelector('.revision-view');
		var hint    = box.querySelector('.revision-hint');
		var heading = box.querySelector('.revision-heading');
		var text    = box.querySelector('.revision-text');
		var current = null;   // 表示している版 { id, title, body, saved }

		function show() {
			if (!current) return;
			var mode = box.querySelector('input[name="revision_mode"]:checked').value;
			heading.textContent = current.saved + ' の版「' + current.title + '」';
			text.textContent = '';
			if (mode === 'diff') {
				var diff = lineDiff(current.body.split('\n'), body.value.replace(/\r\n?/g, '\n').split('\n'));
				if (diff === null) {
					heading.textContent += '（差分を出すには大きすぎるので、全文を出しています）';
				} else if (!diff.some(function (d) { return d.op !== ' '; })) {
					heading.textContent += '（今の本文と同じです）';
					return;
				} else {
					renderDiff(diff);
					return;
				}
			}
			text.textContent = current.body;
		}

		// 変わった行と、その前後3行だけを出す。- はこの版だけにある行、+ は今の本文だけにある行
		function renderDiff(diff) {
			var CONTEXT = 3;
			var shown = diff.map(function () { return false; });
			diff.forEach(function (d, i) {
				if (d.op === ' ') return;
				for (var k = Math.max(0, i - CONTEXT); k <= Math.min(diff.length - 1, i + CONTEXT); k++) shown[k] = true;
			});
			var skipped = false;
			diff.forEach(function (d, i) {
				if (!shown[i]) {
					if (!skipped) text.appendChild(line('…', 'revision-skip'));
					skipped = true;
					return;
				}
				skipped = false;
				text.appendChild(line(d.op + ' ' + d.text, d.op === '-' ? 'revision-del' : d.op === '+' ? 'revision-add' : ''));
			});
		}
		function line(content, className) {
			var span = document.createElement('span');
			if (className) span.className = className;
			span.textContent = content + '\n';
			return span;
		}

		box.addEventListener('click', function (evt) {
			var item = evt.target.closest('.revision-item');
			if (item) {
				box.querySelectorAll('.revision-item[aria-current]').forEach(function (e) { e.removeAttribute('aria-current'); });
				item.setAttribute('aria-current', 'true');
				fetch(item.dataset.url, { credentials: 'same-origin' })
					.then(function (res) { if (!res.ok) throw new Error(res.status); return res.json(); })
					.then(function (rev) {
						current = rev;
						view.hidden = false;
						hint.hidden = true;
						show();
					})
					.catch(function () { window.alert('履歴を読み込めませんでした。'); });
				return;
			}
			if (evt.target.closest('.revision-load') && current) {
				if (!window.confirm('本文を ' + current.saved + ' の版に置き換えます。保存するまでは確定しません。よろしいですか？')) return;
				body.value = current.body;
				body.focus();
				show();
			}
		});
		box.addEventListener('change', function (evt) {
			if (evt.target.name === 'revision_mode') show();
		});
	}

	// 行の差分（a → b）。[{ op: ' ' | '-' | '+', text }, ...]。大きすぎて計算しないときは null
	//   前後の同じ行を除いてから、最長共通部分列（LCS）で比べる
	function lineDiff(a, b) {
		var MAX_CELLS = 4000000;
		var head = 0;
		while (head < a.length && head < b.length && a[head] === b[head]) head++;
		var tail = 0;
		while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] === b[b.length - 1 - tail]) tail++;
		var A = a.slice(head, a.length - tail), B = b.slice(head, b.length - tail);
		var n = A.length, m = B.length;
		if (n * m > MAX_CELLS) return null;
		var w = m + 1;
		var L = new Uint32Array((n + 1) * w);
		for (var i = n - 1; i >= 0; i--) {
			for (var j = m - 1; j >= 0; j--) {
				L[i * w + j] = A[i] === B[j] ? L[(i + 1) * w + j + 1] + 1 : Math.max(L[(i + 1) * w + j], L[i * w + j + 1]);
			}
		}
		var out = a.slice(0, head).map(function (t) { return { op: ' ', text: t }; });
		i = 0; j = 0;
		while (i < n && j < m) {
			if (A[i] === B[j]) { out.push({ op: ' ', text: A[i] }); i++; j++; }
			else if (L[(i + 1) * w + j] >= L[i * w + j + 1]) { out.push({ op: '-', text: A[i] }); i++; }
			else { out.push({ op: '+', text: B[j] }); j++; }
		}
		for (; i < n; i++) out.push({ op: '-', text: A[i] });
		for (; j < m; j++) out.push({ op: '+', text: B[j] });
		return out.concat(a.slice(a.length - tail).map(function (t) { return { op: ' ', text: t }; }));
	}

	//----------------------------------------------------------------------
	// ファイルのアップロード
	//----------------------------------------------------------------------
	function initUpload(form) {
		var bar = form.querySelector('.upload-bar');
		if (!bar) return;
		var body   = form.elements.body;
		var input  = bar.querySelector('.upload-input');
		var status = bar.querySelector('.upload-status');
		var busy   = false;

		// カーソルの位置（選んでいる範囲）に入れる。行の途中なら前後に改行を足す
		function insert(text) {
			var start = body.selectionStart, end = body.selectionEnd, value = body.value;
			var before = value.slice(0, start), after = value.slice(end);
			if (before !== '' && !/\n$/.test(before)) text = '\n' + text;
			if (after !== '' && !/^\n/.test(after)) text += '\n';
			body.value = before + text + after;
			body.selectionStart = body.selectionEnd = before.length + text.length;
			body.focus();
		}

		function send(files) {
			if (!files.length || busy) return;
			busy = true;
			status.textContent = files.length + '件のファイルを上げています…';
			var data = new FormData();
			data.append('csrf_token', form.elements.csrf_token.value);
			files.forEach(function (f) { data.append('file', f, f.name); });
			fetch(bar.dataset.uploadUrl, { method: 'POST', body: data, credentials: 'same-origin' })
				.then(function (res) {
					return res.json().catch(function () { return { files: [], errors: ['上げられませんでした（' + res.status + '）。'] }; });
				})
				.then(function (result) {
					if (result.files.length) insert(result.files.map(function (f) { return f.tag; }).join('\n'));
					status.textContent = result.files.length + '件を上げました。';
					if (result.errors.length) window.alert(result.errors.join('\n'));
				})
				.catch(function () { status.textContent = ''; window.alert('上げられませんでした。'); })
				.then(function () { busy = false; });
		}

		// 貼り付けた画像には、日時から名前を付ける（クリップボードの画像は image.png などの同じ名前になるため）
		function pasteName(file) {
			var d = new Date(), pad = function (n, w) { return String(n).padStart(w || 2, '0'); };
			var ext = (file.type.split('/')[1] || 'png').replace('jpeg', 'jpg');
			return 'paste-image-' + d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + '_'
				+ pad(d.getHours()) + '-' + pad(d.getMinutes()) + '-' + pad(d.getSeconds()) + '-' + pad(d.getMilliseconds(), 3) + '.' + ext;
		}

		// 前に上げたファイルを、メディアの一覧から選んで入れる（admin-media.js）
		var media = bar.querySelector('.media-open');
		if (media && window.LyndbaumMedia) {
			media.addEventListener('click', function () {
				window.LyndbaumMedia.pick({
					base: media.dataset.base,
					csrf: form.elements.csrf_token.value,
					actions: [
						// 複数を選んでいれば、1ファイル1行で入れる
						{ label: '本文に入れる', multiple: true, when: function (f) { return !!f.tag; }, run: function (files) { insert(files.map(function (f) { return f.tag; }).join('\n')); } },
					],
				});
			});
		} else if (media) {
			media.hidden = true;
		}

		input.addEventListener('change', function () {
			send(Array.prototype.slice.call(input.files));
			input.value = '';
		});
		body.addEventListener('dragover', function (evt) {
			if (evt.dataTransfer && Array.prototype.indexOf.call(evt.dataTransfer.types, 'Files') !== -1) evt.preventDefault();
		});
		body.addEventListener('drop', function (evt) {
			var files = evt.dataTransfer ? Array.prototype.slice.call(evt.dataTransfer.files) : [];
			if (!files.length) return;
			evt.preventDefault();
			send(files);
		});
		body.addEventListener('paste', function (evt) {
			var files = evt.clipboardData ? Array.prototype.slice.call(evt.clipboardData.files) : [];
			if (!files.length) return;
			evt.preventDefault();
			// 画像でないもの（ファイルの画面でコピーした PDF など）は、もとの名前のまま上げる
			send(files.map(function (f) { return f.type.indexOf('image/') === 0 ? new File([f], pasteName(f), { type: f.type }) : f; }));
		});
	}

	//----------------------------------------------------------------------
	// アイキャッチ（docs/ogp.md）
	//----------------------------------------------------------------------
	function initOgp(form) {
		var box = form.querySelector('.eyecatch-box');
		if (!box) return;
		var preview = box.querySelector('.eyecatch-preview');
		var note    = box.querySelector('.eyecatch-note');
		var actions = box.querySelector('.eyecatch-actions');
		var pickButton   = box.querySelector('.eyecatch-pick');
		var removeButton = box.querySelector('.eyecatch-remove');
		var hidden  = form.elements.eyecatch;
		var chosenUrl = null;   // 選んだ画像の URL（今の画面で選んだもの）

		// 選んだ画像があればそれを、無ければ本文の最初の画像、それも無ければブログの画像を見せる
		function show() {
			var chosen = hidden.value !== '';
			var url = chosen ? (chosenUrl || attachmentUrl(hidden.value)) : (preview.dataset.auto || preview.dataset.blog);
			preview.textContent = '';
			if (url) {
				var img = document.createElement('img');
				img.src = url;
				img.alt = 'アイキャッチ';
				if (chosen) {
					// 選んだ画像は押すと選び直せる（WordPress と同じ）
					var change = document.createElement('button');
					change.type = 'button';
					change.className = 'eyecatch-change';
					change.title = '画像を変更';
					change.appendChild(img);
					preview.appendChild(change);
				} else {
					preview.appendChild(img);
				}
			}
			note.textContent = noteOf(chosen);
			// メディアの窓が無ければ選べないので、選ぶためのボタンは出さない（削除はできる）
			pickButton.hidden = chosen || !window.LyndbaumMedia;
			removeButton.hidden = !chosen;
		}
		// 画像の下の説明（AdminArticle.pm の _eyecatch と同じ文）
		function noteOf(chosen) {
			return chosen ? '画像を押すと変更できます。'
				: preview.dataset.auto ? '設定しなければ、本文の最初の画像を使います。'
				: preview.dataset.blog ? '設定しなければ、ブログの画像を使います。' : '画像はありません。';
		}
		// 添付ファイルの中のパスから URL を作る（頭は設定の attachment_path）
		function attachmentUrl(path) {
			return preview.dataset.attachments + path.split('/').map(encodeURIComponent).join('/');
		}

		function choose(f) {
			hidden.value = f.folder + f.name;
			chosenUrl = f.thumbnail || f.url;
			show();
		}
		removeButton.addEventListener('click', function () {
			hidden.value = '';
			chosenUrl = null;
			show();
		});
		if (window.LyndbaumMedia) {
			var pick = function () {
				window.LyndbaumMedia.pick({
					base: actions.dataset.base,
					csrf: form.elements.csrf_token.value,
					actions: [{ label: 'アイキャッチ画像に設定', when: function (f) { return f.kind === 'image'; }, run: choose }],
				});
			};
			pickButton.addEventListener('click', pick);
			preview.addEventListener('click', function (evt) { if (evt.target.closest('.eyecatch-change')) pick(); });
		}
		show();
	}
})();
