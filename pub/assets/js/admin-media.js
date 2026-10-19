// 管理画面のメディア（添付ファイルの一覧とゴミ箱。docs/admin.md の「メディア」）
//   LyndbaumMedia.mount(要素, 設定) で一覧を組む。中身は /admin/media/… の JSON から作る
//     設定：base（/admin/media）、csrf（CSRFトークン）、mode（page＝メディアの画面、picker＝選ぶための窓）、
//           upload（/admin/upload。メディアの画面だけ。開いているフォルダへファイルを上げる）、
//           actions（選んだファイルに対してできること [{ label, when(ファイル), run(ファイル), multiple }]。窓で「本文に入れる」など。
//                    multiple が真なら、選んだすべてのファイルが when に合うときに出し、run にはファイルの配列（選んだ順）を渡す。
//                    偽なら、1つだけ選んでいるときに出す）
//           single（真なら1つしか選べない。ほかのファイルを押すと、そのファイルに選び直す）
//   ファイルは押すたびに選ぶ・選ぶのをやめるを切り替え、続けて押すと選ぶものを足していく。まとめて選ぶのをやめる操作は作らない
//   （間違えて押すと選び直すのが手間なため。作者の判断）。Shift を押しながら押すと、前に押したファイルからの範囲を選ぶ。
//   画像をダブルクリック（ダブルタップ）すると、Lythumb で拡大して出す
//   どちらでも、フォルダを作る、ほかのフォルダへ移す（ファイルを左のフォルダへドラッグする）、ゴミ箱へ移す、
//   ゴミ箱を見る（戻す、完全に削除）ができる
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
		// selected は選んだファイルの名前（選んだ順）。anchor は範囲で選ぶときの起点（前に押したファイルの名前）。info はフォルダの木の項目
		var state = { folder: null, files: [], selected: [], anchor: null, trash: false, expanded: {}, info: {} };
		var lastClick = { name: null, time: 0 };   // ダブルクリック（ダブルタップ）を見分けるため
		var dragging = null;   // ドラッグしているファイル（マウスでも指でも）
		var lastPointer = '';  // 最後に押したのがマウスか指か（指ではブラウザのドラッグを使わない）
		root.textContent = '';
		root.classList.add('media');
		var nav     = el('nav', { class: 'media-folders', 'aria-label': 'フォルダ' });
		var title   = el('h2', { class: 'media-title' });
		var filter  = el('input', { type: 'search', class: 'media-filter', placeholder: '名前で絞り込み', 'aria-label': '名前で絞り込み', oninput: renderFiles });
		var newFolder    = el('button', { type: 'button', class: 'media-new-folder', onclick: makeFolder, text: 'フォルダを作成' });
		var renameFolder = el('button', { type: 'button', class: 'media-rename-folder', onclick: renameCurrentFolder, text: 'フォルダ名を変更' });
		var deleteFolder = el('button', { type: 'button', class: 'media-delete-folder', onclick: deleteCurrentFolder, text: 'フォルダを削除' });
		// ファイルを上げる（メディアの画面だけ）。開いているフォルダへ置く。一覧へファイルを落としても上げる
		var uploadInput  = page && opt.upload ? el('input', { type: 'file', multiple: true, onchange: function () { uploadFiles(uploadInput.files); uploadInput.value = ''; } }) : null;
		var uploadButton = uploadInput ? el('label', { class: 'upload-button media-upload' }, ['ファイルを追加', uploadInput]) : null;
		var uploadStatus = uploadInput ? el('span', { class: 'upload-status', 'aria-live': 'polite' }) : null;
		var folderButtons = [newFolder, renameFolder, deleteFolder, uploadButton].filter(Boolean);
		var toolbar = el('div', { class: 'media-toolbar' }, [title, filter].concat(folderButtons, [uploadStatus]));
		var grid    = el('ul', { class: 'media-grid' });
		var detail  = el('aside', { class: 'media-detail', hidden: true, 'aria-live': 'polite' });
		var main    = el('div', { class: 'media-main' }, [toolbar, grid]);
		[nav, main, detail].forEach(function (e) { root.appendChild(e); });

		//------------------------------------------------------------------
		// ドラッグで移す。マウスはブラウザのドラッグ＆ドロップ、指は長押ししてから動かす（touchDrag）。
		// どちらも、フォルダの木の上では hover を、落としたら drop を呼ぶ
		//------------------------------------------------------------------
		var over = null, overTimer = null;   // 重ねているフォルダのボタンと、枝を開くまでの時計
		// 要素から、落とす先のフォルダのボタンを探す（枝の「▸」はそのフォルダとして扱う）
		function folderAt(node) {
			var li = node && node.closest && nav.contains(node) ? node.closest('li') : null;
			if (!li) return null;
			if (!node.closest('.media-folder, .media-folder-toggle')) return null;
			return li.querySelector(':scope > .media-folder[data-folder]');
		}
		function accepts(button) {
			return !!(dragging && button && !state.trash && button.dataset.folder !== state.folder);
		}
		// 重ねているフォルダを変える。落とせるフォルダは枠で囲み、閉じている枝は少し（0.6秒）重ねておくと開く
		function hover(button) {
			if (button === over) return;
			if (over) over.classList.remove('media-drop-target');
			clearTimeout(overTimer);
			over = button;
			if (!button) return;
			if (accepts(button)) button.classList.add('media-drop-target');
			var li = button.parentNode, sub = li.querySelector(':scope > ul');
			if (sub && sub.hidden) overTimer = setTimeout(function () { setExpanded(li, true); }, 600);
		}
		function drop(button) {
			var files = dragging, ok = accepts(button);
			hover(null);
			dragging = null;
			if (ok) moveFiles(files, button.dataset.folder);
		}
		nav.addEventListener('dragover', function (evt) {
			if (!dragging) return;
			var button = folderAt(evt.target);
			hover(button);
			if (!accepts(button)) return;
			evt.preventDefault();
			evt.dataTransfer.dropEffect = 'move';
		});
		nav.addEventListener('dragleave', function (evt) { if (!nav.contains(evt.relatedTarget)) hover(null); });
		nav.addEventListener('drop', function (evt) {
			if (!dragging) return;
			evt.preventDefault();
			drop(folderAt(evt.target));
		});

		// 指で動かす。長押し（0.4秒。ブラウザのメニューが出るより前）で始め、そのまま動かしてフォルダの上で離す。
		// 長押しする前に動かせば、いつもどおりスクロールになる
		function touchDrag(item, f) {
			var timer = null, start = null, ghost = null, y = 0, scroller = null, frame = null, suppressClick = false;
			function end() {
				clearTimeout(timer);
				timer = null;
				cancelAnimationFrame(frame);
				if (ghost) ghost.remove();
				ghost = null;
			}
			// 指が画面の上下の端にあれば、スクロールする（狭い画面では、フォルダの木が一覧の上にあるため）
			function autoScroll() {
				var edge = 48, rect = !scroller.closest('dialog') ? { top: 0, bottom: window.innerHeight } : scroller.getBoundingClientRect();
				var dy = y < rect.top + edge ? -(rect.top + edge - y) / 3 : y > rect.bottom - edge ? (y - rect.bottom + edge) / 3 : 0;
				if (dy) scroller.scrollTop += dy;
				frame = requestAnimationFrame(autoScroll);
			}
			item.addEventListener('touchstart', function (evt) {
				lastPointer = 'touch';
				if (evt.touches.length !== 1) { end(); return; }
				var t = evt.touches[0];
				start = { x: t.clientX, y: t.clientY };
				timer = setTimeout(function () {
					timer = null;
					dragging = state.selected.indexOf(f.name) !== -1 ? selectedFiles() : [f];
					suppressClick = true;
					ghost = el('div', { class: 'media-drag-ghost', text: dragging.length === 1 ? dragging[0].name : dragging.length + '件のファイル' });
					(item.closest('dialog') || document.body).appendChild(ghost);
					ghost.style.left = start.x + 'px';
					ghost.style.top = start.y + 'px';
					y = start.y;
					scroller = item.closest('dialog') || document.scrollingElement || document.documentElement;
					frame = requestAnimationFrame(autoScroll);
				}, 400);
			}, { passive: true });
			item.addEventListener('touchmove', function (evt) {
				var t = evt.touches[0];
				if (!ghost) {
					// 長押しの前に動かしたらスクロール
					if (timer && Math.abs(t.clientX - start.x) + Math.abs(t.clientY - start.y) > 10) end();
					return;
				}
				evt.preventDefault();   // ドラッグしているあいだはスクロールさせない
				ghost.style.left = t.clientX + 'px';
				ghost.style.top = t.clientY + 'px';
				y = t.clientY;
				hover(folderAt(document.elementFromPoint(t.clientX, t.clientY)));
			}, { passive: false });
			item.addEventListener('touchend', function (evt) {
				var dragged = !!ghost;
				end();
				if (!dragged) { dragging = null; return; }
				evt.preventDefault();   // 離したときの click（選ぶ・やめる）を起こさない
				drop(over);
			});
			item.addEventListener('touchcancel', function () { end(); hover(null); dragging = null; });
			// 長押しのメニュー（画像を保存など）を出さない。出ても click で選ぶのを切り替えない
			item.addEventListener('contextmenu', function (evt) { if (dragging || suppressClick) evt.preventDefault(); });
			item.addEventListener('click', function (evt) {
				if (!suppressClick) return;
				suppressClick = false;
				evt.stopImmediatePropagation();
			}, true);
			item.addEventListener('touchstart', function () { suppressClick = false; }, { passive: true, capture: true });
		}

		// フォルダの木を読み直す。treeOnly なら木だけを組み直し、開いているフォルダ（と選んだファイル）はそのままにする
		function loadFolders(open, treeOnly) {
			return getJSON(opt.base + '/folders').then(function (data) {
				nav.textContent = '';
				state.info = {};
				var list = el('ul', {});
				(function walk(items, ul, depth) {
					items.forEach(function (f) {
						state.info[f.folder] = f;
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
				if (treeOnly) { markCurrent(); return; }
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
		// 開いているフォルダの中にフォルダを作る。作ったら木に出す（開いているフォルダと選んだファイルはそのまま。続けて移せるように）
		function makeFolder() {
			var parent = state.folder || '';
			var name = window.prompt('「' + (parent || 'いちばん上') + '」の中に作るフォルダの名前', '');
			if (name === null || name.trim() === '') return;
			postJSON(opt.base + '/folders', opt.csrf, [['parent', parent], ['name', name]]).then(function () {
				if (parent) state.expanded[parent] = true;
				return loadFolders(state.folder, true);
			}).then(function () { if (parent) expandTo(parent); })
				.catch(function (e) { window.alert('フォルダを作れませんでした。' + e.message); });
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

		// フォルダを開く。select を渡せば、そのファイル（名前の配列）を選んだ状態にする（名前を変えた、上げたなど）
		function openFolder(folder, select) {
			state.trash = false;
			state.folder = folder;
			state.selected = [];
			state.anchor = null;
			renderDetail();
			filter.hidden = false;
			folderButtons.forEach(function (b) { b.hidden = false; });
			// いちばん上の posts/ と @system/ は、名前を変えたり消したりできない（Lyndbaum::Media）
			renameFolder.hidden = deleteFolder.hidden = !!(state.info[folder] && state.info[folder].protected);
			markCurrent();
			expandTo(folder);
			title.textContent = folder;
			grid.textContent = '';
			return getJSON(opt.base + '/files?folder=' + encodeURIComponent(folder)).then(function (data) {
				state.files = data.files;
				state.selected = (select || []).filter(function (name) { return data.files.some(function (f) { return f.name === name; }); });
				renderFiles();
				renderDetail();
			}).catch(function (e) { window.alert('ファイルを読み込めませんでした。' + e.message); });
		}

		// 一覧に出しているファイル（名前で絞り込んだもの）
		function shownFiles() {
			var word = filter.value.trim().toLowerCase();
			return state.files.filter(function (f) { return word === '' || f.name.toLowerCase().indexOf(word) !== -1; });
		}
		function renderFiles() {
			if (state.trash) return;
			grid.textContent = '';
			var shown = shownFiles();
			title.textContent = state.folder + '(' + shown.length + '件)';
			shown.forEach(function (f) {
				var preview = f.thumbnail ? el('img', { src: f.thumbnail, alt: '', loading: 'lazy' })
					: el('span', { class: 'media-kind', text: f.kind === 'video' ? '動画' : f.kind === 'image' ? '画像' : 'ファイル' });
				// 選んでいるかは aria-pressed で表す（チェックボックスは置かない。押すのはファイルのどこでもよいため）
				var selected = state.selected.indexOf(f.name) !== -1;
				var item = el('button', {
					type: 'button', class: 'media-item', 'aria-pressed': selected ? 'true' : 'false', draggable: 'true',
					onclick: function (evt) { toggle(f, evt); },
					onpointerdown: function (evt) { lastPointer = evt.pointerType; },
					// 選んでいるファイルをドラッグすれば選んだすべてを、選んでいないファイルならそのファイルだけを移す
					ondragstart: function (evt) {
						// 指のときはブラウザのドラッグを使わない（長押しの touchDrag と重なるため）
						if (lastPointer === 'touch') { evt.preventDefault(); return; }
						dragging = state.selected.indexOf(f.name) !== -1 ? selectedFiles() : [f];
						evt.dataTransfer.effectAllowed = 'move';
						evt.dataTransfer.setData('text/plain', dragging.map(function (x) { return x.folder + x.name; }).join('\n'));
					},
					ondragend: function () { hover(null); dragging = null; },
				}, [
					preview, el('span', { class: 'media-name', text: f.name }),
				]);
				touchDrag(item, f);
				grid.appendChild(el('li', { class: selected ? 'media-selected' : '' }, [item]));
			});
			if (!shown.length) grid.appendChild(el('li', { class: 'media-empty', text: 'ファイルはありません。' }));
		}

		// 押したファイルを選ぶ。選んでいれば選ぶのをやめる。Shift を押していれば、前に押したファイルからの範囲を足す
		// （範囲は選ぶだけで、やめはしない）。同じ画像を続けて2回押せば（ダブルクリック、ダブルタップ）、拡大して出す
		function toggle(f, evt) {
			var shown = shownFiles();
			var from = state.anchor === null ? -1 : shown.map(function (x) { return x.name; }).indexOf(state.anchor);
			var to = shown.indexOf(f);
			if (evt && evt.shiftKey && !opt.single && from !== -1 && to !== -1) {
				var step = from < to ? 1 : -1;
				for (var i = from; i !== to + step; i += step) {
					if (state.selected.indexOf(shown[i].name) === -1) state.selected.push(shown[i].name);
				}
			} else {
				var at = state.selected.indexOf(f.name);
				if (at !== -1) state.selected.splice(at, 1);
				else if (opt.single) state.selected = [f.name];
				else state.selected.push(f.name);
			}
			state.anchor = f.name;
			renderFiles();
			renderDetail();
			var now = Date.now(), twice = lastClick.name === f.name && now - lastClick.time < 400;
			lastClick = twice ? { name: null, time: 0 } : { name: f.name, time: now };
			if (twice && f.kind === 'image' && !(evt && evt.shiftKey)) openViewer(f);
		}

		// 画像を Lythumb で拡大して出す。開いているフォルダの画像（一覧に出しているもの）を、前後にめくれるようにする
		// 選ぶための窓（モーダルの <dialog>）はいちばん上に出て、外側を操作できなくするので、Lythumb は窓の中に出す
		function openViewer(f) {
			if (!window.Lythumb) { window.open(f.url, '_blank', 'noopener'); return; }
			var old = root.querySelector('.media-viewer-links');
			if (old) old.remove();
			var links = el('div', { class: 'media-viewer-links', hidden: true });
			var target = null;
			shownFiles().filter(function (x) { return x.kind === 'image'; }).forEach(function (x) {
				var a = el('a', { href: x.url, 'data-lythumb': 'media', 'data-caption': x.name }, [el('img', { src: x.thumbnail || x.url, alt: '' })]);
				if (x === f) target = a;
				links.appendChild(a);
			});
			root.appendChild(links);
			window.Lythumb.open(target, { container: root.closest('dialog') || document.body });
		}
		// 選んだファイル（選んだ順）。絞り込みで隠れているものも含める
		function selectedFiles() {
			return state.selected.map(function (name) {
				return state.files.filter(function (f) { return f.name === name; })[0];
			}).filter(Boolean);
		}

		// 詳しいことの欄。最後に選んだファイルの詳しいことを出し、操作は選んだすべてのファイルに行う
		function renderDetail() {
			var files = state.trash ? [] : selectedFiles();
			detail.textContent = '';
			detail.hidden = !files.length;
			if (!files.length) return;
			var f = files[files.length - 1];
			var preview = f.kind === 'image' ? el('img', { src: f.thumbnail || f.url, alt: '' })
				: f.kind === 'video' ? el('video', { src: f.url, controls: true, preload: 'metadata' }) : null;
			// 本文に入れる記法。複数なら1ファイル1行（コピーも「本文に入れる」も同じ）
			var tags = files.filter(function (x) { return x.tag; }).map(function (x) { return x.tag; });
			var tag = !tags.length ? null : tags.length === 1
				? el('input', { type: 'text', readonly: true, value: tags[0], class: 'media-tag', 'aria-label': '本文に入れる記法' })
				: el('textarea', { readonly: true, rows: Math.min(tags.length, 6), class: 'media-tag', 'aria-label': '本文に入れる記法' }, [tags.join('\n')]);
			var actions = (opt.actions || []).filter(function (a) {
				return a.multiple ? files.every(function (x) { return !a.when || a.when(x); }) : files.length === 1 && (!a.when || a.when(f));
			});
			var usage = el('div', { class: 'media-usage', text: '使っている記事を調べています…' });
			[
				files.length > 1 ? el('p', { class: 'media-selected-count', text: files.length + '件を選んでいます。下の操作は、選んだすべてのファイルに行います。' }) : null,
				el('h3', { text: f.name }),
				preview,
				el('p', { class: 'media-meta', text: size(f.size) + '　' + f.mtime }),
				el('p', {}, [el('a', { href: f.url, target: '_blank', rel: 'noopener', text: '元のファイルを開く' })]),
				tag,
				tag ? el('p', {}, [el('button', { type: 'button', text: '記法をコピー', onclick: function () { copy(tag); } })]) : null,
				el('div', { class: 'media-actions' }, actions
					.concat(files.length === 1 ? [{ label: '名前を変更', run: renameFile }] : [])
					.concat([{ label: 'ゴミ箱へ移動', multiple: true, run: trashFiles }])
					.map(function (a) { return el('button', { type: 'button', text: a.label, onclick: function () { a.run(a.multiple ? files : f); } }); })),
				el('p', { class: 'admin-help', text: 'Shiftを押しながら押すと、範囲で選べます。画像はダブルクリック（ダブルタップ）で拡大します。ほかのフォルダへ移すには、ファイルを左のフォルダへドラッグします（スマートフォンでは長押ししてから）。' }),
				usage,
			].forEach(function (e) { if (e) detail.appendChild(e); });
			getJSON(opt.base + '/usage?folder=' + encodeURIComponent(f.folder) + '&name=' + encodeURIComponent(f.name)).then(function (data) {
				usage.textContent = '';
				if (!data.articles.length) { usage.textContent = '「' + f.name + '」を使っている記事はありません。'; return; }
				usage.appendChild(el('p', { text: '「' + f.name + '」を使っている記事：' }));
				usage.appendChild(el('ul', {}, data.articles.map(function (a) {
					return el('li', {}, [el('a', { href: a.edit_url, target: page ? null : '_blank', text: a.title || '（題名なし）' }), a.trashed ? '（ゴミ箱）' : null]);
				})));
			}).catch(function () { usage.textContent = '使っている記事を調べられませんでした。'; });
		}
		function copy(input) {
			input.select();
			if (navigator.clipboard) navigator.clipboard.writeText(input.value).catch(function () { document.execCommand('copy'); });
			else document.execCommand('copy');
		}

		// ファイルを使っている記事の一覧（確かめるときに出す「・名前：題名」の行の配列）
		function usedBy(files) {
			return Promise.all(files.map(function (f) {
				return getJSON(opt.base + '/usage?folder=' + encodeURIComponent(f.folder) + '&name=' + encodeURIComponent(f.name))
					.then(function (data) { return data.articles.map(function (a) { return '・' + f.name + '：' + (a.title || '（題名なし）') + (a.trashed ? '（ゴミ箱）' : ''); }); });
			})).then(function (lists) { return [].concat.apply([], lists); });
		}

		// ほかのフォルダへ移す。記事の中のパスは書き換えないので、使っている記事があれば、その題名を出して確かめる
		function moveFiles(files, to) {
			usedBy(files).then(function (used) {
				var message = files.length + '件のファイルを「' + to + '」へ移動しますか？';
				if (used.length) message += '\n\n次の記事が使っています。移すと、記事の画像が出なくなります（記事は書き換えません）。\n' + used.join('\n');
				if (!window.confirm(message)) return;
				return postJSON(opt.base + '/move', opt.csrf, [['folder', state.folder], ['to', to]].concat(files.map(function (f) { return ['name', f.name]; })))
					.then(function (result) { showErrors(result); return loadFolders(state.folder); });
			}).catch(function (e) { window.alert('移動できませんでした。' + e.message); });
		}

		// ファイルの名前を変える（拡張子は変えられない）。記事の中のパスは書き換えないので、使っている記事があれば確かめる
		function renameFile(f) {
			var name = window.prompt('「' + f.name + '」の新しい名前（拡張子は変えられません）', f.name);
			if (name === null || name.trim() === '' || name.trim() === f.name) return;
			usedBy([f]).then(function (used) {
				if (used.length && !window.confirm('次の記事が使っています。名前を変えると、記事の画像が出なくなります（記事は書き換えません）。変えますか？\n' + used.join('\n'))) return;
				return postJSON(opt.base + '/rename', opt.csrf, [['folder', state.folder], ['name', f.name], ['new_name', name]])
					.then(function (result) { return openFolder(state.folder, [result.name]); });
			}).catch(function (e) { window.alert('名前を変えられませんでした。' + e.message); });
		}

		// 開いているフォルダの名前を変える。中のファイルを使っている記事は書き換えない
		function renameCurrentFolder() {
			var folder = state.folder, info = state.info[folder];
			var name = window.prompt('「' + folder + '」の新しい名前（中のファイルを使っている記事は書き換えません）', info ? info.name : '');
			if (name === null || name.trim() === '' || (info && name.trim() === info.name)) return;
			postJSON(opt.base + '/folders/rename', opt.csrf, [['folder', folder], ['name', name]]).then(function (result) {
				if (folder in state.expanded) state.expanded[result.folder] = state.expanded[folder];
				state.folder = result.folder;
				return loadFolders(result.folder);
			}).catch(function (e) { window.alert('フォルダの名前を変えられませんでした。' + e.message); });
		}

		// 開いているフォルダを消す（空のフォルダだけ）。消したら上のフォルダを開く
		function deleteCurrentFolder() {
			var folder = state.folder;
			if (!window.confirm('フォルダ「' + folder + '」を削除しますか？（空のフォルダだけ削除できます）')) return;
			postJSON(opt.base + '/folders/delete', opt.csrf, [['folder', folder]]).then(function () {
				var parent = folder.replace(/[^\/]+\/$/, '');
				state.folder = null;
				return loadFolders(parent || null);
			}).catch(function (e) { window.alert('フォルダを削除できませんでした。' + e.message); });
		}

		// 開いているフォルダへファイルを上げる。サムネイルの大きさは編集の設定の既定。上げたファイルを選んだ状態にする
		function uploadFiles(list) {
			var files = Array.prototype.slice.call(list || []);
			if (!files.length || !uploadInput || state.trash) return;
			var folder = state.folder;
			var data = new FormData();
			data.append('csrf_token', opt.csrf);
			data.append('folder', folder);
			files.forEach(function (f) { data.append('file', f); });
			uploadStatus.textContent = files.length + '件のファイルを上げています…';
			fetch(opt.upload, { method: 'POST', body: data, credentials: 'same-origin' })
				.then(function (res) { return res.json(); })
				.then(function (result) {
					uploadStatus.textContent = (result.files || []).length + '件のファイルを上げました。';
					showErrors(result);
					return loadFolders(folder, true).then(function () {
						if (state.folder === folder && !state.trash) return openFolder(folder, (result.files || []).map(function (f) { return f.name; }));
					});
				})
				.catch(function (e) { uploadStatus.textContent = ''; window.alert('ファイルを上げられませんでした。' + e.message); });
		}
		if (uploadInput) {
			// ほかのアプリから一覧へファイルを落とす（中のファイルのドラッグとは分ける）
			var isFiles = function (evt) { return !dragging && evt.dataTransfer && Array.prototype.indexOf.call(evt.dataTransfer.types || [], 'Files') !== -1; };
			main.addEventListener('dragover', function (evt) {
				if (!isFiles(evt) || state.trash) return;
				evt.preventDefault();
				main.classList.add('media-upload-target');
			});
			main.addEventListener('dragleave', function (evt) { if (!main.contains(evt.relatedTarget)) main.classList.remove('media-upload-target'); });
			main.addEventListener('drop', function (evt) {
				main.classList.remove('media-upload-target');
				if (!isFiles(evt) || state.trash) return;
				evt.preventDefault();
				uploadFiles(evt.dataTransfer.files);
			});
		}

		// ゴミ箱へ移す。使っている記事があれば、その題名を出して確かめる
		function trashFiles(files) {
			usedBy(files).then(function (used) {
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
			state.selected = [];
			renderDetail();
			markCurrent();
			filter.hidden = true;
			folderButtons.forEach(function (b) { b.hidden = true; });
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
			// 窓の外（背景）を押したら閉じる。押し始めと離した所の両方が外のときだけにする
			// （窓の中で範囲選択やドラッグを始めて、外で離したときに閉じないように）
			var outside = function (evt) {
				var r = dialog.getBoundingClientRect();
				return evt.target === dialog && (evt.clientX < r.left || evt.clientX > r.right || evt.clientY < r.top || evt.clientY > r.bottom);
			};
			var downOutside = false;
			dialog.addEventListener('pointerdown', function (evt) { downOutside = outside(evt); });
			dialog.addEventListener('click', function (evt) {
				if (downOutside && outside(evt)) dialog.close();
				downOutside = false;
			});
			document.body.appendChild(dialog);
			dialog.body = body;
		}
		explorer = mount(dialog.body, {
			// 複数のファイルに行える操作が無ければ（「アイキャッチ画像に設定」など）、1つしか選べなくする（WordPress と同じ）
			base: opt.base, csrf: opt.csrf, mode: 'picker', single: !opt.actions.some(function (a) { return a.multiple; }),
			actions: opt.actions.map(function (a) {
				return { label: a.label, when: a.when, multiple: a.multiple, run: function (f) { a.run(f); if (!a.keepOpen) dialog.close(); } };
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
	if (root) mount(root, { base: root.dataset.base, csrf: root.dataset.csrf, upload: root.dataset.upload, mode: 'page' });
})();
