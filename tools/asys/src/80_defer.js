////////////////////////////////////////////////////////////////////////////////
// "script-defer" and "css-defer"
////////////////////////////////////////////////////////////////////////////////
$$.init(function(){
	const self=this;

	// css-defer
	$('link.css-defer').attr('rel', 'stylesheet');

	// script-defer, Run after all js file's $() function
	$(function(){
		const $scripts = $('script-defer');
		const line = [];
		$scripts.each(function(idx, dom) {
			line[idx] = self.get_line_number(dom);
		});
		$scripts.each(function(idx, dom) {
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
