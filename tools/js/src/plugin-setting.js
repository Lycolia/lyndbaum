//##############################################################################
// プラグイン設定JavaScript
//							(C)2013 nabe@abk
//##############################################################################
//[TAB=8]
'use strict';
adiary_public.ready(function(){
	// 設定画面を送るフォームのひな形。開くたびに写して使う
	// （閉じた後に、前に開いたときのイベントなどが残らないように）
	const form_tmpl = adiary.secure('#ajax-form');
	if (!form_tmpl) return;
	form_tmpl.remove();

	document.querySelectorAll('button.setting').forEach(function(btn){
		btn.addEventListener('click', function(evt){
			module_setting(evt.currentTarget);
		});
	});

////////////////////////////////////////////////////////////////////////////////
// ●サブルーチン
////////////////////////////////////////////////////////////////////////////////
function create(tag, cls) {
	const dom = document.createElement(tag);
	if (cls) dom.className = cls;
	return dom;
}
function html_of(id) {
	const dom = document.getElementById(id);
	return dom ? dom.innerHTML : '';
}
function text_of(id) {
	const dom = document.getElementById(id);
	return dom ? dom.textContent : '';
}

// 読み込んだHTMLの<script>を取り出し、目印に置き換える。開いた後に run_scripts() で動かす
// （今まではjQueryが、文書に入れたときに動かしていた）
const ScriptType = /^$|^module$|\/(?:java|ecma)script/i;	// jQueryと同じ
function take_scripts(dom) {
	const ary = [];
	dom.querySelectorAll('script').forEach(function(scr){
		if (!ScriptType.test(scr.getAttribute('type') || '')) return;	// text/template などは、そのまま残す
		const mark = document.createComment('script');
		scr.replaceWith(mark);
		ary.push({ mark: mark, script: scr });
	});
	return ary;
}
function run_scripts(ary) {
	for(const x of ary) {
		const scr = document.createElement('script');
		for(const a of x.script.attributes) scr.setAttribute(a.name, a.value);
		scr.textContent = x.script.textContent;
		x.mark.replaceWith(scr);
	}
}

////////////////////////////////////////////////////////////////////////////////
// ●モジュールの設定を変更する
////////////////////////////////////////////////////////////////////////////////
function module_setting(obj) {
	const name = obj.dataset.moduleName;
	const url  = obj.dataset.url;

	const formdiv  = create('div');
	const form     = form_tmpl.cloneNode(true);
	const formbody = create('div', 'body');
	form.appendChild( formbody );
	formdiv.appendChild( form );

	// エラー表示用
	const errdiv = create('div', 'error-message');
	const errmsg = create('strong', 'error');
	errmsg.style.display = 'block';
	const erradd = create('div');
	errdiv.append(errmsg, erradd);

	function on_error(text) {
		errmsg.innerHTML = html_of('msg-ajax-error');
		errmsg.setAttribute('title', text);
	}

	const buttons = {};
	buttons[ text_of('btn-ok') ] = function(){
		// disabled要素も送信する
		form.querySelectorAll('[disabled]').forEach(function(x){ x.removeAttribute('disabled') });

		const data = new URLSearchParams();
		for(const [k, v] of new FormData(form)) {
			if (typeof(v) === 'string') data.append(k, v);	// ファイルは送らない（今までの serialize と同じ）
		}
		// 今すぐ保存
		fetch(form.getAttribute('action'), { method: 'POST', body: data }).then(function(res){
			return res.text().then(function(text){
				if (!res.ok) return on_error(text);

				const ma = text.match(/ret=(-?\d+)(?:\n|)$/);
				if (!ma) {
					errmsg.innerHTML = html_of('msg-save-error');
				} else if (ma[1] != '0') {
					errmsg.innerHTML = html_of('msg-save-error') +'(ret='+ ma[1] +')';
				} else {
					//成功
					dialog.close();
					// モジュールHTMLをサーバからロード？
					if (obj.dataset.loadModuleHtml) load_module_html( obj );
					return ;
				}
				errmsg.setAttribute('title', text);
				const msg = text.match(/\nmsg=([\s\S]*)$/);
				if (msg) erradd.innerHTML = msg[1];
			});
		}).catch(function(e){
			on_error(String(e));
		});
	};
	buttons[ adiary.msg('cancel') ] = function(){
		dialog.close();
	};

	// ダイアログの設定
	const dialog = adiary.dialog(formdiv, {
		autoOpen: false,
		modal: true,
		width:  adiary.DialogWidth,
		minHeight: 100,
		maxHeight: document.documentElement.clientHeight,
		title:   obj.dataset.title.replace('%n', obj.dataset.title),
		buttons: buttons
	});

	// フォーム本体をロード。読み込めなくても開く（今までの .load() と同じ）
	fetch(url).then(function(res){
		return res.ok ? res.text() : '';
	}).catch(function(){
		return '';
	}).then(function(html){
		formbody.innerHTML = html;
		const scripts = take_scripts(formbody);

		adiary.dom_init( formdiv );
		formbody.appendChild( errdiv );
		dialog.open();
		run_scripts(scripts);

		const inp = create('input');
		inp.setAttribute('type',  'hidden');
		inp.setAttribute('name',  'module_name');
		inp.setAttribute('value', name);
		formbody.appendChild( inp );
	});
}

////////////////////////////////////////////////////////////////////////////////
});
