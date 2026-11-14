////////////////////////////////////////////////////////////////////////////////
// popup for mouseover
////////////////////////////////////////////////////////////////////////////////
// jQueryを使わずに書いてある。選択子に合う要素にマウスを乗せると、少し待ってからポップアップを出す。
// 後から足した要素にも効く（bodyのmouseoverで受ける）。登録ごとにdiv.popup-blockを1つ作る
//	adiary.popup_on(選択子, { show: function(要素, div){…}, hide: function(要素, div){…} })
//	待つ時間は、要素のdata-delayか、adiary.PopupDelayTime
$$.popup_on = function(sel, opt) {
	const self = this;
	opt = opt || {};
	let div;
	const timers = new WeakMap();	// 要素ごとの、出すまでのタイマー
	const bound  = new WeakSet();	// mouseleaveを付けた要素

	document.body.addEventListener('mouseover', function(evt){
		const obj = evt.target.closest && evt.target.closest(sel);
		if (!obj || timers.get(obj)) return;
		if (!div) {
			div = document.createElement('div');
			div.className = 'popup-block';
			document.body.appendChild(div);
		}
		let delay = Number(obj.dataset.delay) || self.PopupDelayTime;
		if (delay<1) delay=1;

		const x = evt.pageX;
		const y = evt.pageY;
		timers.set(obj, setTimeout(function(){
			timers.delete(obj);
			if (self.showing(div)) return;		// 出している途中
			if (opt.show) opt.show(obj, div);
			div.style.left = (self.SP ? 0 : (x + self.PopupOffsetX)) + 'px';
			div.style.top  = (y + self.PopupOffsetY) + 'px';
			self.show_delay(div);
		}, delay));

		if (bound.has(obj)) return;
		bound.add(obj);
		obj.addEventListener('mouseleave', function(){
			clearTimeout(timers.get(obj));
			timers.delete(obj);
			if (!div) return;
			self.hide(div);
			if (opt.hide) opt.hide(obj, div);
		});
	});
};
