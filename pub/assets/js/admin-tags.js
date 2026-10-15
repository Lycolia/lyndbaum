// 管理画面のタグの管理（docs/admin.md の「タグの管理」）
//   タグの木を画面の上で組み替える。操作だけでは確定せず、「保存」を押したときに木の全体を JSON で送る
//   （サーバーは送られた木を確かめてから、まとめて書き込む）
'use strict';
(function () {
	var form = document.querySelector('form.tag-admin');
	if (!form) return;
	var list;   // [{ id, name, parent_id, sort_order, deleted, count, in_use }, ...]
	try {
		list = JSON.parse(form.dataset.tags);
	} catch (e) {
		return;
	}
	var byId = {};
	list.forEach(function (t) {
		t.orig = { name: t.name, parent_id: t.parent_id, sort_order: t.sort_order, deleted: t.deleted };
		byId[t.id] = t;
	});
	var tree   = form.querySelector('.tag-admin-tree');
	var status = form.querySelector('.tag-admin-status');
	var filter = form.querySelector('.tag-admin-filter');
	var dirty  = false;
	var mover  = null;   // 「移動」で開いている親の選択

	// 同じ親の子（並び順、名前の順）
	function children(parentId) {
		return list.filter(function (t) { return (t.parent_id || null) === (parentId || null); })
			.sort(function (a, b) { return (a.sort_order - b.sort_order) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0); });
	}
	function descendants(id) {
		var out = [];
		children(id).forEach(function (c) { out.push(c.id); out = out.concat(descendants(c.id)); });
		return out;
	}
	function fullName(t) {
		var names = [];
		for (var p = t; p; p = p.parent_id ? byId[p.parent_id] : null) names.unshift(p.name);
		return names.join('::');
	}
	function changed(t) {
		return t.name !== t.orig.name || (t.parent_id || null) !== (t.orig.parent_id || null)
			|| t.sort_order !== t.orig.sort_order || t.deleted !== t.orig.deleted;
	}
	function markDirty() {
		dirty = list.some(changed);
		status.textContent = dirty ? '保存していない変更があります。' : '';
	}
	// 同じ親の子の並び順を 10, 20, … に振り直す（並び順が重なっていて、入れ替えられないとき）
	function renumber(parentId) {
		children(parentId).forEach(function (t, i) { t.sort_order = (i + 1) * 10; });
	}

	function button(label, action, id, aria) {
		var b = document.createElement('button');
		b.type = 'button';
		b.textContent = label;
		b.dataset.action = action;
		b.dataset.id = id;
		if (aria) b.setAttribute('aria-label', aria);
		return b;
	}

	function renderNode(t, siblings, index) {
		var li = document.createElement('li');
		li.dataset.id = t.id;
		var row = document.createElement('div');
		row.className = 'tag-admin-row' + (changed(t) ? ' tag-admin-changed' : '') + (t.deleted ? ' tag-admin-deleted' : '');
		var up = button('▲', 'up', t.id, '「' + t.name + '」を上へ');
		up.disabled = index === 0;
		var down = button('▼', 'down', t.id, '「' + t.name + '」を下へ');
		down.disabled = index === siblings.length - 1;
		var name = document.createElement('input');
		name.type = 'text';
		name.value = t.name;
		name.dataset.id = t.id;
		name.className = 'tag-admin-name';
		name.setAttribute('aria-label', fullName(t) + 'の名前');
		var count = document.createElement('span');
		count.className = 'tag-count';
		count.textContent = t.count;
		count.title = 'このタグを付けた記事の数';
		var move = button('移動', 'move', t.id, '「' + t.name + '」の親を変える');
		var del = document.createElement('label');
		var check = document.createElement('input');
		check.type = 'checkbox';
		check.dataset.action = 'delete';
		check.dataset.id = t.id;
		check.checked = t.deleted;
		var hasChildren = children(t.id).some(function (c) { return !c.deleted; });
		check.disabled = !t.deleted && (t.in_use || hasChildren);
		del.title = t.in_use ? '記事が付いているので消せません' : hasChildren ? '子のタグがあるので消せません' : '';
		del.appendChild(check);
		del.appendChild(document.createTextNode('削除'));
		[up, down, name, count, move, del].forEach(function (e) { row.appendChild(e); });
		li.appendChild(row);
		if (mover === t.id) li.appendChild(renderMover(t));
		var kids = children(t.id);
		if (kids.length) {
			var ul = document.createElement('ul');
			kids.forEach(function (c, i) { ul.appendChild(renderNode(c, kids, i)); });
			li.appendChild(ul);
		}
		return li;
	}

	// 親の選択。自分と子孫、消すタグは選べない
	function renderMover(t) {
		var box = document.createElement('div');
		box.className = 'tag-admin-mover';
		var select = document.createElement('select');
		select.dataset.id = t.id;
		select.setAttribute('aria-label', '「' + t.name + '」の新しい親');
		var none = document.createElement('option');
		none.value = '';
		none.textContent = '（最上位）';
		select.appendChild(none);
		var excluded = {};
		excluded[t.id] = true;
		descendants(t.id).forEach(function (id) { excluded[id] = true; });
		(function walk(parentId, depth) {
			children(parentId).forEach(function (c) {
				if (excluded[c.id]) return;
				if (!c.deleted) {
					var o = document.createElement('option');
					o.value = c.id;
					o.textContent = '　'.repeat(depth) + c.name;
					o.selected = c.id === t.parent_id;
					select.appendChild(o);
				}
				walk(c.id, depth + 1);
			});
		})(null, 0);
		if (!t.parent_id) none.selected = true;
		box.appendChild(select);
		box.appendChild(button('ここへ移す', 'move-ok', t.id));
		box.appendChild(button('やめる', 'move-cancel', t.id));
		return box;
	}

	function render(focus) {
		tree.textContent = '';
		var roots = children(null);
		roots.forEach(function (t, i) { tree.appendChild(renderNode(t, roots, i)); });
		applyFilter();
		markDirty();
		if (focus) {
			var e = tree.querySelector(focus);
			if (e) e.focus();
		}
	}

	// 名前で絞り込む。当たったタグの祖先も出す
	function applyFilter() {
		var word = filter.value.trim().toLowerCase();
		tree.querySelectorAll('li').forEach(function (li) {
			li.hidden = word !== '' && !Array.prototype.some.call(li.querySelectorAll('.tag-admin-name'), function (i) {
				return i.value.toLowerCase().indexOf(word) !== -1;
			});
		});
	}

	tree.addEventListener('input', function (evt) {
		var t = byId[evt.target.dataset.id];
		if (!t || !evt.target.classList.contains('tag-admin-name')) return;
		t.name = evt.target.value;
		evt.target.closest('.tag-admin-row').classList.toggle('tag-admin-changed', changed(t));
		markDirty();
	});
	tree.addEventListener('change', function (evt) {
		if (evt.target.dataset.action !== 'delete') return;
		byId[evt.target.dataset.id].deleted = evt.target.checked;
		render('input[data-action="delete"][data-id="' + evt.target.dataset.id + '"]');
	});
	tree.addEventListener('click', function (evt) {
		var b = evt.target.closest('button[data-action]');
		if (!b) return;
		var t = byId[b.dataset.id];
		var action = b.dataset.action;
		if (action === 'up' || action === 'down') {
			var siblings = children(t.parent_id);
			// 並び順が重なっていると入れ替えても順が変わらないので、そのときだけ振り直す
			var orders = siblings.map(function (c) { return c.sort_order; });
			if (orders.some(function (o, i) { return orders.indexOf(o) !== i; })) {
				renumber(t.parent_id);
				siblings = children(t.parent_id);
			}
			var i = siblings.indexOf(t);
			var other = siblings[action === 'up' ? i - 1 : i + 1];
			if (!other) return;
			var order = t.sort_order;
			t.sort_order = other.sort_order;
			other.sort_order = order;
			render('button[data-action="' + action + '"][data-id="' + t.id + '"]');
		} else if (action === 'move') {
			mover = mover === t.id ? null : t.id;
			render('select[data-id="' + t.id + '"]');
		} else if (action === 'move-cancel') {
			mover = null;
			render('button[data-action="move"][data-id="' + t.id + '"]');
		} else if (action === 'move-ok') {
			var value = tree.querySelector('select[data-id="' + t.id + '"]').value;
			var parentId = value === '' ? null : Number(value);
			if (parentId !== (t.parent_id || null)) {
				var last = children(parentId).reduce(function (m, c) { return Math.max(m, c.sort_order); }, 0);
				t.parent_id = parentId;
				t.sort_order = last + 10;
			}
			mover = null;
			render('button[data-action="move"][data-id="' + t.id + '"]');
		}
	});
	filter.addEventListener('input', applyFilter);
	// 絞り込みの欄で Enter を押しても送らない
	filter.addEventListener('keydown', function (evt) { if (evt.key === 'Enter') evt.preventDefault(); });

	form.addEventListener('submit', function () {
		form.elements.tree.value = JSON.stringify(list.map(function (t) {
			return { id: t.id, name: t.name, parent_id: t.parent_id || null, sort_order: t.sort_order, deleted: t.deleted };
		}));
		dirty = false;
	});
	window.addEventListener('beforeunload', function (evt) {
		if (!dirty) return;
		evt.preventDefault();
		evt.returnValue = '';
	});

	render();
})();
