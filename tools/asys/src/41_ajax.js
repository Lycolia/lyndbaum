//##############################################################################
// Ajax
//##############################################################################
////////////////////////////////////////////////////////////////////////////////
// send_ajax
////////////////////////////////////////////////////////////////////////////////
$$.send_ajax = function(opt) {
	const self=this;

	function error_default(err, h) {
		if (opt.error) opt.error(err, h);
		if ('dialog' in opt && !opt.dialog) return;

		let msg = '';
		if (h) {
			if (h.ret && h._develop) msg += 'ret = ' + h.ret;
			if (h.msg)    msg += '<p>' + self.tag_esc(h.msg.toString())    + '</p>';
			if (h.errs) {
				const ary = [];
				const e = h.errs;
				const o = e._order || Object.keys(e);
				for(let i in o) {
					if (e[o[i]]=='') continue;
					ary.push(e[o[i]]);
				}
				msg += '<p class="ni">' + ary.join("<br>") + '</p>';
			}
			if (h._debug) msg += '<p class="ni">' + h._debug.replace(/\n/g, '<br>') + '</p>';
		} else {
			msg = '<p>' + self.msg('server_response_error', 'response data error!') + '</p>';
		}
		self.show_error(msg, function(){
			if (opt.error_dialog_callback) opt.error_dialog_callback(err, h)
		});
	}
	// data は、URLエンコードした文字か FormData。今までの$.ajax（contentType: false）と同じく、
	// 文字は text/plain で送る。返事は JSON。success か error の後に complete を呼ぶ
	fetch(opt.url || self.myself || './', {
		method:	'POST',
		body:	opt.data
	}).then(function(res){
		if (!res.ok) throw new Error(res.status + ' ' + res.statusText);
		return res.json();
	}).then(function(h){
		if (h.ret != '0' || h._debug) error_default('', h);
		else if (opt.success) opt.success(h);
	}, function(e){
		error_default(e);
	}).then(function(){
		if (opt.complete) opt.complete();
	});
};
