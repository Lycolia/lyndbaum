////////////////////////////////////////////////////////////////////////////////
// "script-defer" and "css-defer"
////////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const self=this;

	// css-defer
	document.querySelectorAll('link.css-defer').forEach(function(x){ x.setAttribute('rel', 'stylesheet') });

	// script-defer。ほかのJSの初期化と、画面のJS（ready で登録したもの）の後に動かす
	this.ready(function(){
		const scripts = document.querySelectorAll('script-defer');
		const line = [];
		scripts.forEach(function(dom, idx) {
			line[idx] = self.get_line_number(dom);
		});
		scripts.forEach(function(dom, idx) {
			const scr     = document.createElement('script');
			scr.innerHTML = "\n".repeat(line[idx]) + dom.innerHTML;
			dom.innerHTML = '';
			dom.appendChild(scr);
		});
	});
});

$$.get_line_number = function(dom) {
	let line = 2;	// before <head> lines
	domloop: while(1) {
		while(!dom.previousSibling) {
			if (!dom.parentElement) break domloop;
			dom = dom.parentElement;
		}
		dom = dom.previousSibling;
		line += (dom.outerHTML || dom.nodeValue || "").split("\n").length -1;
	}
	return line;
}
