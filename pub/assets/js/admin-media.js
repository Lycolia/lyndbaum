// 管理画面のメディア（添付ファイルの一覧とゴミ箱。docs/admin.md の「メディア」）
//   LyndbaumMedia.mount(要素, 設定) で一覧を組む。中身は /admin/media/… の JSON から作る
//     設定：base（/admin/media）、csrf（CSRFトークン）、mode（page＝メディアの画面、picker＝選ぶための窓）、
//           actions（選んだファイルに対してできること [{ label, when(ファイル), run(ファイル) }]。窓で「本文に入れる」など）
//   どちらでも、ゴミ箱へ移す、ゴミ箱を見る（戻す、完全に削除）ができる
//   LyndbaumMedia.pick(設定) で、選ぶための窓（<dialog>）を開く（編集の画面の「ファイル一覧から選択」）
'use strict';
(function () {
	function el(tag, attrs, children) {
		var e = document.createElement(tag);
		Object.keys(attrs || {}).forEach(function (k) {
			if (k === 'text') e.textContent = attrs[k];
			else if (k === 'class') e.className = attrs[k];
			else if (k.indexOf('on') === 0) e.addEventListener(k.slice(2), attrs[k]);
			else if (attrs[k] !== null && attrs[k] !== undefined && attrs[k] !== false) e.setAttribute(k, attrs[k] === true ? '' : attrs[k]);
		});
		(children || []).forEach(function (c) { if (c) e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c); });
		return e;
	}
	function size(bytes) {
		return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + 'MB' : bytes >= 1024 ? Math.round(bytes / 1024) + 'KB' : bytes + 'B';
	}
	function getJSON(url) {
		return fetch(url, { credentials: 'same-origin' }).then(function (res) {
			return res.json().then(function (data) { if (!res.ok) throw new Error((data.errors || []).join('\n') || res.status); return data; });
		});
	}
	function postJSON(url, csrf, pairs) {
		var body = new URLSearchParams();
		body.append('csrf_token', csrf);
		pairs.forEach(function (p) { body.append(p[0], p[1]); });
		return fetch(url, { method: 'POST', body: body, credentials: 'same-origin' }).then(function (res) {
			return res.json().then(function (data) { if (!res.ok) throw new Error((data.errors || []).join('\n') || res.status); return data; });
		});
	}
	function showErrors(result) {
		if (result.errors && result.errors.length) window.alert(result.errors.join('\n'));
	}

	function mount(root, opt) {
		var page = opt.mode !== 'picker';
		var state = { folder: null, files: [], selected: {}, detail: null, trash: false, expanded: {} };
		root.textContent = '';
		root.classList.add('media');
		var nav     = el('nav', { class: 'media-folders', 'aria-label': 'フォルダ' });
		var title   = el('h2', { class: 'media-title' });
		var filter  = el('input', { type: 'search', class: 'media-filter', placeholder: '名前で絞り込み', 'aria-label': '名前で絞り込み', oninput: renderFiles });
		var bulk    = el('button', { type: 'button', onclick: trashSelected, text: '選んだものをゴミ箱へ移動' });
		var toolbar = el('div', { class: 'media-toolbar' }, [title, filter, bulk]);
		var grid    = el('ul', { class: 'media-grid' });
		var detail  = el('aside', { class: 'media-detail', hidden: true, 'aria-live': 'polite' });
		var main    = el('div', { class: 'media-main' }, [toolbar, grid]);
		[nav, main, detail].forEach(function (e) { root.appendChild(e); });

		function loadFolders(open) {
			return getJSON(opt.base + '/folders').then(function (data) {
				nav.textContent = '';
				var list = el('ul', {});
				(function walk(items, ul, depth) {
					items.forEach(function (f) {
						var button = el('button', {
							type: 'button', class: 'media-folder', 'data-folder': f.folder,
							onclick: function () { openFolder(f.folder); }, text: f.name + '(' + f.total + ')',
						});
						var li = el('li', {});
						if (f.children.length) {
							// 下のフォルダは折りたためる。最初は一番上の階層だけ開く。開け閉めは読み込み直しても保つ
							var sub = el('ul', {});
							walk(f.children, sub, depth + 1);
							var toggle = el('button', {
								type: 'button', class: 'media-folder-toggle', 'aria-label': f.name + 'の下のフォルダ',
								onclick: function () { setExpanded(li, sub.hidden); },
							});
							li.appendChild(toggle);
							li.appendChild(button);
							li.appendChild(sub);
							li.dataset.folder = f.folder;
							setExpanded(li, f.folder in state.expanded ? state.expanded[f.folder] : depth === 0);
						} else {
							li.appendChild(el('span', { class: 'media-folder-toggle', 'aria-hidden': 'true' }));
							li.appendChild(button);
						}
						ul.appendChild(li);
					});
				})(data.folders, list, 0);
				nav.appendChild(list);
				nav.appendChild(el('button', { type: 'button', class: 'media-folder media-trash-button', onclick: openTrash, text: 'ゴミ箱' }));
				// 開くフォルダ：前に開いていたフォルダ、今月のフォルダ、ファイルのある最初のフォルダの順
				var exists = function (folder) { return folder && nav.querySelector('[data-folder="' + CSS.escape(folder) + '"]'); };
				var start = open || state.folder;
				if (!exists(start)) start = exists(data.current) ? data.current : firstWithFiles(data.folders);
				if (start && !state.trash) openFolder(start);
				else markCurrent();
			}).catch(function (e) { window.alert('フォルダを読み込めませんでした。' + e.message); });
		}
		function firstWithFiles(items) {
			for (var i = 0; i < items.length; i++) {
				if (items[i].count) return items[i].folder;
				var child = firstWithFiles(items[i].children);
				if (child) return child;
			}
			return items.length ? items[0].folder : null;
		}
		// フォルダの木の枝（子のある li）を開く、または閉じる
		function setExpanded(li, open) {
			li.querySelector(':scope > ul').hidden = !open;
			li.querySelector(':scope > .media-folder-toggle').setAttribute('aria-expanded', open ? 'true' : 'false');
			state.expanded[li.dataset.folder] = open;
		}
		// 開いたフォルダが見えるよう、上のフォルダを開く
		function expandTo(folder) {
			var button = nav.querySelector('.media-folder[data-folder="' + CSS.escape(folder) + '"]');
			for (var li = button && button.parentNode.parentNode.closest('li'); li && nav.contains(li); li = li.parentNode.closest('li')) {
				setExpanded(li, true);
			}
		}
		function markCurrent() {
			nav.querySelectorAll('.media-folder').forEach(function (b) {
				var current = state.trash ? b.classList.contains('media-trash-button') : b.dataset.folder === state.folder;
				if (current) b.setAttribute('aria-current', 'true'); else b.removeAttribute('aria-current');
			});
		}

		function openFolder(folder) {
			state.trash = false;
			state.folder = folder;
			state.selected = {};
			closeDetail();
			if (bulk) bulk.hidden = false;
			filter.hidden = false;
			markCurrent();
			expandTo(folder);
			title.textContent = folder;
			grid.textContent = '';
			return getJSON(opt.base + '/files?folder=' + encodeURIComponent(folder)).then(function (data) {
				state.files = data.files;
				renderFiles();
			}).catch(function (e) { window.alert('ファイルを読み込めませんでした。' + e.message); });
		}

		function renderFiles() {
			if (state.trash) return;
			grid.textContent = '';
			var word = filter.value.trim().toLowerCase();
			var shown = state.files.filter(function (f) { return word === '' || f.name.toLowerCase().indexOf(word) !== -1; });
			title.textContent = state.folder + '(' + shown.length + '件)';
			shown.forEach(function (f) {
				var preview = f.thumbnail ? el('img', { src: f.thumbnail, alt: '', loading: 'lazy' })
					: el('span', { class: 'media-kind', text: f.kind === 'video' ? '動画' : f.kind === 'image' ? '画像' : 'ファイル' });
				var item = el('button', { type: 'button', class: 'media-item', onclick: function () { showDetail(f); } }, [
					preview, el('span', { class: 'media-name', text: f.name }),
				]);
				var check = el('input', {
					type: 'checkbox', class: 'media-check', 'aria-label': '「' + f.name + '」を選ぶ', checked: !!state.selected[f.name],
					onchange: function (evt) { if (evt.target.checked) state.selected[f.name] = true; else delete state.selected[f.name]; },
				});
				grid.appendChild(el('li', { class: state.detail === f ? 'media-current' : '' }, [check, item]));
			});
			if (!shown.length) grid.appendChild(el('li', { class: 'media-empty', text: 'ファイルはありません。' }));
		}

		function showDetail(f) {
			state.detail = f;
			renderFiles();
			detail.hidden = false;
			detail.textContent = '';
			var preview = f.kind === 'image' ? el('img', { src: f.thumbnail || f.url, alt: '' })
				: f.kind === 'video' ? el('video', { src: f.url, controls: true, preload: 'metadata' }) : null;
			var tag = f.tag ? el('input', { type: 'text', readonly: true, value: f.tag, class: 'media-tag', 'aria-label': '本文に入れる記法' }) : null;
			var usage = el('div', { class: 'media-usage', text: '使っている記事を調べています…' });
			[
				el('h3', { text: f.name }),
				preview,
				el('p', { class: 'media-meta', text: size(f.size) + '　' + f.mtime }),
				el('p', {}, [el('a', { href: f.url, target: '_blank', rel: 'noopener', text: '元のファイルを開く' })]),
				tag,
				tag ? el('p', {}, [el('button', { type: 'button', text: '記法をコピー', onclick: function () { copy(tag); } })]) : null,
				el('div', { class: 'media-actions' }, (opt.actions || []).filter(function (a) { return !a.when || a.when(f); })
					.concat([{ label: 'ゴミ箱へ移動', run: function () { trashFiles([f]); } }])
					.map(function (a) { return el('button', { type: 'button', text: a.label, onclick: function () { a.run(f); } }); })),
				usage,
				el('p', {}, [el('button', { type: 'button', class: 'media-close', text: '閉じる', onclick: closeDetail })]),
			].forEach(function (e) { if (e) detail.appendChild(e); });
			getJSON(opt.base + '/usage?folder=' + encodeURIComponent(f.folder) + '&name=' + encodeURIComponent(f.name)).then(function (data) {
				usage.textContent = '';
				if (!data.articles.length) { usage.textContent = '使っている記事はありません。'; return; }
				usage.appendChild(el('p', { text: '使っている記事：' }));
				usage.appendChild(el('ul', {}, data.articles.map(function (a) {
					return el('li', {}, [el('a', { href: a.edit_url, target: page ? null : '_blank', text: a.title || '（題名なし）' }), a.trashed ? '（ゴミ箱）' : null]);
				})));
			}).catch(function () { usage.textContent = '使っている記事を調べられませんでした。'; });
		}
		function closeDetail() {
			state.detail = null;
			detail.hidden = true;
			detail.textContent = '';
			renderFiles();
		}
		function copy(input) {
			input.select();
			if (navigator.clipboard) navigator.clipboard.writeText(input.value).catch(function () { document.execCommand('copy'); });
			else document.execCommand('copy');
		}

		// ゴミ箱へ移す。使っている記事があれば、その題名を出して確かめる
		function trashSelected() {
			var files = state.files.filter(function (f) { return state.selected[f.name]; });
			if (!files.length) { window.alert('ファイルを選んでください。'); return; }
			trashFiles(files);
		}
		function trashFiles(files) {
			Promise.all(files.map(function (f) {
				return getJSON(opt.base + '/usage?folder=' + encodeURIComponent(f.folder) + '&name=' + encodeURIComponent(f.name))
					.then(function (data) { return data.articles.map(function (a) { return '・' + f.name + '：' + (a.title || '（題名なし）') + (a.trashed ? '（ゴミ箱）' : ''); }); });
			})).then(function (lists) {
				var used = [].concat.apply([], lists);
				var message = files.length + '件のファイルをゴミ箱へ移動しますか？（ゴミ箱から戻せます）';
				if (used.length) message += '\n\n次の記事が使っています。移すと、記事の画像が出なくなります。\n' + used.join('\n');
				if (!window.confirm(message)) return;
				return postJSON(opt.base + '/trash', opt.csrf, [['folder', state.folder]].concat(files.map(function (f) { return ['name', f.name]; })))
					.then(function (result) { showErrors(result); return loadFolders(state.folder); });
			}).catch(function (e) { window.alert('ゴミ箱へ移せませんでした。' + e.message); });
		}

		// ゴミ箱。中身はサムネイルで確かめられる（ゴミ箱は公開のフォルダにある）
		function openTrash() {
			state.trash = true;
			state.selected = {};
			closeDetail();
			markCurrent();
			if (bulk) bulk.hidden = true;
			filter.hidden = true;
			title.textContent = 'ゴミ箱';
			grid.textContent = '';
			getJSON(opt.base + '/trash').then(function (data) {
				grid.textContent = '';
				title.textContent = 'ゴミ箱(' + data.files.length + '件)';
				if (!data.files.length) { grid.appendChild(el('li', { class: 'media-empty', text: 'ゴミ箱は空です。' })); return; }
				var selected = {};
				data.files.forEach(function (f) {
					var preview = f.thumbnail ? el('img', { src: f.thumbnail, alt: '', loading: 'lazy' })
						: el('span', { class: 'media-kind', text: f.kind === 'video' ? '動画' : f.kind === 'image' ? '画像' : 'ファイル' });
					grid.appendChild(el('li', { class: 'media-trash-item' }, [
						el('input', {
							type: 'checkbox', class: 'media-check', 'aria-label': '「' + f.original + '」を選ぶ',
							onchange: function (evt) { if (evt.target.checked) selected[f.item] = true; else delete selected[f.item]; },
						}),
						el('a', { class: 'media-item', href: f.url, target: '_blank', rel: 'noopener' }, [
							preview,
							el('span', { class: 'media-name', text: f.folder + f.original }),
							el('span', { class: 'media-meta', text: '消した日時 ' + f.deleted + '　' + size(f.size) }),
						]),
					]));
				});
				var items = function () { return Object.keys(selected).map(function (i) { return ['item', i]; }); };
				var run = function (path, message, pairs) {
					if (!pairs.length) { window.alert('ファイルを選んでください。'); return; }
					if (!window.confirm(message)) return;
					postJSON(opt.base + path, opt.csrf, pairs).then(function (result) { showErrors(result); return loadFolders(); }).then(openTrash)
						.catch(function (e) { window.alert('操作できませんでした。' + e.message); });
				};
				grid.appendChild(el('li', { class: 'media-trash-actions' }, [
					el('button', { type: 'button', text: '戻す', onclick: function () { run('/trash/restore', '選んだファイルを戻しますか？', items()); } }),
					el('button', { type: 'button', text: '完全に削除', onclick: function () { run('/trash/purge', '選んだファイルを完全に削除しますか？元に戻せません。', items()); } }),
					el('button', { type: 'button', text: 'ゴミ箱を空にする', onclick: function () { run('/trash/purge', 'ゴミ箱を空にしますか？すべてのファイルが完全に削除され、元に戻せません。', [['all', '1']]); } }),
				]));
			}).catch(function (e) { window.alert('ゴミ箱を読み込めませんでした。' + e.message); });
		}

		loadFolders();
		return { reload: function () { return loadFolders(state.folder); } };
	}

	// 選ぶための窓。開くたびにフォルダを読み直す（上げたばかりのファイルも出るように）
	var dialog, explorer;
	function pick(opt) {
		if (!dialog) {
			dialog = el('dialog', { class: 'media-dialog', 'aria-label': 'ファイル一覧から選択' });
			var body = el('div', { class: 'media-dialog-body' });
			dialog.appendChild(el('div', { class: 'media-dialog-head' }, [
				el('h2', { text: 'ファイル一覧から選択' }),
				el('button', { type: 'button', text: '閉じる', onclick: function () { dialog.close(); } }),
			]));
			dialog.appendChild(body);
			document.body.appendChild(dialog);
			dialog.body = body;
		}
		explorer = mount(dialog.body, {
			base: opt.base, csrf: opt.csrf, mode: 'picker',
			actions: opt.actions.map(function (a) {
				return { label: a.label, when: a.when, run: function (f) { a.run(f); if (!a.keepOpen) dialog.close(); } };
			}),
		});
		dialog.showModal();
		return explorer;
	}

	window.LyndbaumMedia = { mount: mount, pick: pick };

	// 設定の画面などの「ファイル一覧から選択」（data-target の欄に、選んだファイルのパス「フォルダ/名前」を入れる）
	document.querySelectorAll('button.media-field[data-target]').forEach(function (button) {
		var form = button.closest('form');
		var input = form && form.elements[button.dataset.target];
		if (!input) return;
		button.addEventListener('click', function () {
			pick({
				base: button.dataset.base,
				csrf: form.elements.csrf_token.value,
				actions: [{ label: 'この画像にする', when: function (f) { return f.kind === 'image'; }, run: function (f) { input.value = f.folder + f.name; } }],
			});
		});
	});

	// メディアの画面
	var root = document.querySelector('.media-page[data-base]');
	if (root) mount(root, { base: root.dataset.base, csrf: root.dataset.csrf, mode: 'page' });
})();
