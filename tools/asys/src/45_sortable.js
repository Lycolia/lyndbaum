//##############################################################################
// sortable（今までのjQuery UIのsortableの代わり）
//##############################################################################
// jQueryを使わずに書いてある。デザイン編集（iframeの中）と、モジュールの設定画面（情報、リンク集）が使う。
// つかんだものがマウスについて動き、入る所に空き（ui-sortable-placeholder）を開ける。
// マウスとペンだけ（今までのjQuery UIと同じく、タッチでは並べ替えない）。ESCで元に戻す。
//
//	adiary.sortable(入れ物の配列, opt)
//	opt.items	並べ替えるもの（入れ物からの選択子。">"で始まるものは直下。既定は"> *"）
//	opt.connectWith	行き来できる入れ物（配列）
//	opt.cancel	ここをつかんだときは始めない（closestで見る）
//	opt.update	並びが変わったときに呼ぶ
//	adiary.sorting()	並べ替えている（つかんで動かし始めた）間か
{
const registry = new WeakMap();		// 文書ごとの並べ替えの一覧
let   drag;				// 動かしている間の情報
const ScrollSensitivity = 20;		// jQuery UIの既定と同じ
const ScrollSpeed       = 20;

// jQueryの.height()、.width()（CSSの値。決まらないときは表示の大きさ）
function css_size(dom, dim) {
	const cs  = dom.ownerDocument.defaultView.getComputedStyle(dom);
	const val = cs[dim];
	const ary = dim === 'width' ? ['Left', 'Right'] : ['Top', 'Bottom'];
	let   pb  = 0;
	for(const s of ary)
		pb += (parseFloat(cs['padding' + s]) || 0) + (parseFloat(cs['border' + s + 'Width']) || 0);
	if (val === 'auto' || isNaN(parseFloat(val)))
		return (dim === 'width' ? dom.offsetWidth : dom.offsetHeight) - pb;
	const x = parseFloat(val);
	return cs.boxSizing === 'border-box' ? x - pb : x;
}
// jQuery UIの.scrollParent()
function scroll_parent(el) {
	const win = el.ownerDocument.defaultView;
	for(let p = el.parentElement; p; p = p.parentElement) {
		if (/^(?:html|body)$/i.test(p.tagName)) break;
		const c = win.getComputedStyle(p);
		if (/(auto|scroll)/.test(c.overflow + c.overflowY + c.overflowX)) return p;
	}
	return null;	// 文書（窓）
}

$$.sortable = function(containers, opt) {
	opt = opt || {};
	for(const el of containers) {
		const doc = el.ownerDocument;
		if (!registry.has(doc)) registry.set(doc, []);
		const s = {
			el:	 el,
			doc:	 doc,
			items:	 (opt.items || '> *').split(',').map(function(x){ x = x.trim(); return x.substr(0,1) == '>' ? ':scope ' + x : x }).join(', '),
			connect: opt.connectWith || [],
			cancel:	 opt.cancel || 'input, textarea, button, select, option',
			update:	 opt.update
		};
		registry.get(doc).push(s);
		el.classList.add('ui-sortable');
		// jQuery UIと同じく、中のui-sortable-handleをいったん外してから、自分のものに付ける
		el.querySelectorAll('.ui-sortable-handle').forEach(function(x){ x.classList.remove('ui-sortable-handle') });
		items_of(s).forEach(function(x){ x.classList.add('ui-sortable-handle') });
		el.addEventListener('pointerdown', function(evt){ sort_down(s, evt) });
	}
};
// 並べ替えている（つかんで動かし始めた）間か
$$.sorting = function() {
	return !!(drag && drag.started);
};
function items_of(s) {
	return Array.from(s.el.querySelectorAll(s.items));
}
function group_of(s) {	// 入れられる並べ替え（自分と、つないだ入れ物）
	return (registry.get(s.doc) || []).filter(function(x){ return x === s || s.connect.indexOf(x.el) >= 0 });
}
function sort_down(s, evt) {
	if (evt._sort_handled || drag) return;		// 内側の並べ替えが受けた
	if (evt.pointerType === 'touch' || evt.button !== 0) return;
	if (evt.target.closest(s.cancel)) return;

	// つかんだもの（この並べ替えのもの）
	const items = items_of(s);
	let item = evt.target;
	while(item && item !== s.el && items.indexOf(item) < 0) item = item.parentElement;
	if (!item || item === s.el) return;
	evt._sort_handled = true;

	const doc = s.doc;
	drag = { s: s, doc: doc, item: item, x0: evt.pageX, y0: evt.pageY, started: false, id: evt.pointerId };
	doc.addEventListener('pointermove',   sort_move);
	doc.addEventListener('pointerup',     sort_up);
	doc.addEventListener('pointercancel', sort_cancel);
	doc.addEventListener('keydown',       sort_key);
}
// 空き（同じタグ、同じクラス。表の行は、jQuery UIと同じく、元の行の数だけtdを入れる）
function make_placeholder(item) {
	const doc  = item.ownerDocument;
	const name = item.nodeName.toLowerCase();
	const ph   = doc.createElement(name);
	ph.className = 'ui-sortable-placeholder ' + item.className;
	ph.classList.remove('ui-sortable-helper');
	const tr_ph = function(src, tr) {
		for(const c of src.children) {
			const td = doc.createElement('td');
			td.innerHTML = '&#160;';
			td.setAttribute('colspan', c.getAttribute('colspan') || 1);
			tr.appendChild(td);
		}
	};
	if (name === 'tbody') {
		const tr  = doc.createElement('tr');
		const src = item.querySelector('tr');
		if (src) tr_ph(src, tr);
		ph.appendChild(tr);
	} else if (name === 'tr') {
		tr_ph(item, ph);
	} else if (name === 'img') {
		ph.setAttribute('src', item.getAttribute('src'));
	}
	ph.style.visibility = 'hidden';
	return ph;
}
function sort_start() {
	const doc  = drag.doc;
	const item = drag.item;
	const win  = doc.defaultView;
	const r    = item.getBoundingClientRect();
	drag.style  = item.getAttribute('style');
	drag.parent = item.parentNode;
	drag.next   = item.nextSibling;

	// 空き。大きさは、jQuery UIと同じく、CSSで大きさが決まらないときだけ入れる
	// （デザイン編集の.design-module-editはmin-heightがあるので、高さは入らない）
	const w  = css_size(item, 'width');
	const h  = css_size(item, 'height');
	const ph = make_placeholder(item);
	item.after(ph);
	if (!css_size(ph, 'height')) ph.style.height = h + 'px';
	if (!css_size(ph, 'width'))  ph.style.width  = w + 'px';
	drag.ph = ph;

	// つかんだものを、元の所に浮かせる
	item.classList.add('ui-sortable-helper');
	item.style.width  = w + 'px';
	item.style.height = h + 'px';
	item.style.position = 'absolute';
	item.style.zIndex   = 1000;
	item.style.pointerEvents = 'none';	// 下にあるものを見つけるため
	const op  = item.offsetParent || doc.documentElement;
	const opr = op.getBoundingClientRect();
	const ocs = win.getComputedStyle(op);
	const ics = win.getComputedStyle(item);
	drag.left0 = r.left - opr.left - (parseFloat(ocs.borderLeftWidth) || 0) + op.scrollLeft - (parseFloat(ics.marginLeft) || 0);
	drag.top0  = r.top  - opr.top  - (parseFloat(ocs.borderTopWidth)  || 0) + op.scrollTop  - (parseFloat(ics.marginTop)  || 0);
	item.style.left = drag.left0 + 'px';
	item.style.top  = drag.top0  + 'px';

	// 端に来たらスクロールするもの（jQuery UIと同じく、空きのscrollParent）
	drag.sp  = scroll_parent(ph);
	drag.sp0 = drag.sp ? drag.sp.scrollTop : 0;
	drag.sp_in = drag.sp && drag.sp.contains(op) && drag.sp !== op;	// 浮かせたものが、一緒に動くか

	drag.select = doc.body.style.userSelect;
	doc.body.style.userSelect = 'none';
	drag.started = true;
}
function sort_move(evt) {
	if (!drag || evt.pointerId !== drag.id) return;
	if (!drag.started) {
		if (Math.max(Math.abs(evt.pageX - drag.x0), Math.abs(evt.pageY - drag.y0)) < 1) return;
		sort_start();
	}
	evt.preventDefault();
	const item = drag.item;
	const win  = drag.doc.defaultView;
	const sp   = drag.sp;

	// 端に近づいたらスクロールする
	if (sp) {
		const r = sp.getBoundingClientRect();
		if (r.top + sp.offsetHeight - evt.clientY < ScrollSensitivity)	sp.scrollTop += ScrollSpeed;
		else if (evt.clientY - r.top < ScrollSensitivity)		sp.scrollTop -= ScrollSpeed;
	} else {
		if (evt.clientY < ScrollSensitivity)				win.scrollBy(0, -ScrollSpeed);
		else if (win.innerHeight - evt.clientY < ScrollSensitivity)	win.scrollBy(0,  ScrollSpeed);
	}
	const dy = drag.sp_in ? sp.scrollTop - drag.sp0 : 0;
	item.style.left = (drag.left0 + evt.pageX - drag.x0) + 'px';
	item.style.top  = (drag.top0  + evt.pageY - drag.y0 + dy) + 'px';

	place(evt.clientX, evt.clientY);
}
// マウスの下に空きを動かす
function place(x, y) {
	const ph    = drag.ph;
	const item  = drag.item;
	const group = group_of(drag.s);
	const under = drag.doc.elementFromPoint(x, y);
	if (!under) return;

	// 入れられるもの
	let cands = [];
	for(const g of group) cands = cands.concat( items_of(g) );
	cands = cands.filter(function(c){ return c !== item && !item.contains(c) && c !== ph });

	// マウスの下のもの
	let el = under;
	while(el && cands.indexOf(el) < 0) el = el.parentElement;
	if (el) {
		const r = el.getBoundingClientRect();
		if (y < r.top + r.height/2) { if (el.previousElementSibling !== ph) el.before(ph); }
		else			    { if (el.nextElementSibling !== ph)     el.after(ph);  }
		return;
	}
	// マウスの下の入れ物（いちばん内側）
	let box = under;
	while(box && !group.some(function(g){ return g.el === box })) box = box.parentElement;
	if (!box) return;
	const s  = group.find(function(g){ return g.el === box });
	const in_box = cands.filter(function(c){ return items_of(s).indexOf(c) >= 0 });
	if (!in_box.length) {
		if (ph.parentNode !== box) box.appendChild(ph);
		return;
	}
	// 入れ物の中の、いちばん近いものの前か後ろ
	let near, dist;
	for(const c of in_box) {
		const r = c.getBoundingClientRect();
		const d = y < r.top ? r.top - y : (y > r.bottom ? y - r.bottom : 0);
		if (near === undefined || d < dist) { near = c; dist = d; }
	}
	const r = near.getBoundingClientRect();
	if (y < r.top + r.height/2) { if (near.previousElementSibling !== ph) near.before(ph); }
	else			    { if (near.nextElementSibling !== ph)     near.after(ph);  }
}
function sort_end(cancel) {
	const d = drag;
	drag = null;
	if (!d) return;
	const doc = d.doc;
	doc.removeEventListener('pointermove',   sort_move);
	doc.removeEventListener('pointerup',     sort_up);
	doc.removeEventListener('pointercancel', sort_cancel);
	doc.removeEventListener('keydown',       sort_key);
	if (!d.started) return;

	const item = d.item;
	if (cancel) d.ph.remove();
	       else d.ph.replaceWith(item);
	if (cancel) d.parent.insertBefore(item, d.next);
	item.classList.remove('ui-sortable-helper');
	if (d.style === null) item.removeAttribute('style');
		else	      item.setAttribute('style', d.style);
	doc.body.style.userSelect = d.select;

	// ドラッグの直後のクリック（離したときに起きる）は止める（今までのjQuery UIと同じ）。
	// クリックはpointerupと同じ流れで起きるので、その後には外す
	const stop = function(evt){
		evt.stopPropagation();
		evt.preventDefault();
	};
	doc.addEventListener('click', stop, true);
	setTimeout(function(){ doc.removeEventListener('click', stop, true) }, 0);

	if (cancel) return;
	const moved = item.parentNode !== d.parent || item.nextSibling !== d.next;
	if (!moved) return;
	for(const g of group_of(d.s)) {
		if (!g.update) continue;
		if (g.el.contains(item) || g.el.contains(d.parent)) g.update();
	}
}
function sort_up(evt)     { if (drag && evt.pointerId === drag.id) sort_end(false) }
function sort_cancel(evt) { if (drag && evt.pointerId === drag.id) sort_end(true)  }
function sort_key(evt)    { if (evt.keyCode == 27) sort_end(true) }
}
