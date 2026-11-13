//##############################################################################
// 記事の本文の編集欄（CodeMirror6）
//##############################################################################
//[TAB=8]
// Chromiumのtextareaは、字数が多い（目安8万字）とIMEでまともに入力できなくなる。
// そこで本文の編集欄をCodeMirror6（codemirror.min.js、tools/codemirror）にする。
//
// textarea#editareaは隠して残し、その要素のvalue、selectionStart、selectionEnd、
// setSelectionRange()、focus()、readOnlyをCodeMirrorにつなぐ。edit.jsとedit-helper.jsは
// 今までどおりtextareaとして読み書きできる。送るとき（new FormData(form)を含む）は、
// formdataイベントで本文を入れ直す。
// 見た目はプレーンテキストのまま（記法の色分けだけ）。Enterは改行だけを入れ、
// 字下げやリストの記号を足さない。URLを貼っても、リンクの記法にしない。
// codemirror.min.jsが読めないときは、textareaのまま。
'use strict';
$(function(){
	const CM = window.CM6;
	const ta = document.getElementById('editarea');
	if (!CM || !ta) return;

	const proto = HTMLTextAreaElement.prototype;
	const ta_value    = Object.getOwnPropertyDescriptor(proto, 'value');
	const ta_readonly = Object.getOwnPropertyDescriptor(proto, 'readOnly');

	const $box = $('<div>').attr('id', 'editarea-cm').addClass('edit-article');
	$(ta).after($box).hide();

	//----------------------------------------------------------------------
	// ●記法の色分け（edit-helper.jsのHelpersと同じ判定）
	//----------------------------------------------------------------------
	// Markdownは、Lyndbaumの記法に合わせて読む（tools/codemirror/lyndbaum-markdown.js）。
	// さつき記法のタグは、サーバーのタグ定義にある名前だけをタグとして色分けする（data-satsuki-tags）
	const $parsel = $('#select-parser');
	const lang    = new CM.Compartment();
	const tag_names = (ta.getAttribute('data-satsuki-tags') || '').split(/\s+/).filter(Boolean);
	function lang_ext() {
		const parser = $parsel.val() || '';
		if (parser.match(/^markdown/i))      return CM.markdown( CM.lyndbaumMarkdown(tag_names) );
		if (parser.match(/^(?:simple|html)/i)) return CM.html({ autoCloseTags: false });
		return [];
	}

	//----------------------------------------------------------------------
	// ●TABで文字のタブを入れる（adiary.jsのtextareaと同じ）
	//----------------------------------------------------------------------
	// フォーカスした直後とESCの後のTABは、次の欄へ移る
	let tab_stop = false;
	const tab_keys = CM.Prec.highest(CM.EditorView.domEventHandlers({
		focus: function() { tab_stop = true; },
		keydown: function(evt, view) {
			if (view.state.readOnly) return false;
			if (evt.keyCode == 27) { tab_stop = true; return false; }
			if (tab_stop) {
				tab_stop = false;
				return false;	// TABはブラウザに任せて次の欄へ（trueを返すと止められる）
			}
			if (evt.shiftKey || evt.keyCode != 9 || evt.ctrlKey || evt.altKey || evt.metaKey) return false;
			evt.preventDefault();
			view.dispatch(view.state.replaceSelection("\t"), { scrollIntoView: true, userEvent: 'input' });
			return true;
		}
	}));

	//----------------------------------------------------------------------
	// ●作る
	//----------------------------------------------------------------------
	const readonly = new CM.Compartment();
	const view = new CM.EditorView({
		parent: $box[0],
		state:  CM.EditorState.create({
			doc: ta_value.get.call(ta),
			extensions: [
				CM.history(),
				CM.EditorView.lineWrapping,
				CM.EditorState.tabSize.of(8),
				tab_keys,
				CM.keymap.of([
					{ key: 'Enter', run: CM.insertNewline },
					...CM.defaultKeymap,
					...CM.historyKeymap
				]),
				CM.syntaxHighlighting(CM.lyndbaumHighlight),
				CM.syntaxHighlighting(CM.defaultHighlightStyle),
				lang.of( lang_ext() ),
				readonly.of( CM.EditorState.readOnly.of( ta_readonly.get.call(ta) ) )
			]
		})
	});
	$box.toggleClass('readonly', ta_readonly.get.call(ta));

	$parsel.on('change', function(){
		view.dispatch({ effects: lang.reconfigure( lang_ext() ) });
	});

	//----------------------------------------------------------------------
	// ●textareaとして読み書きする
	//----------------------------------------------------------------------
	function set_selection(start, end) {
		const len = view.state.doc.length;
		start = Math.max(0, Math.min(len, start|0));
		end   = Math.max(0, Math.min(len, end===undefined ? start : end|0));
		if (end < start) start = end;	// textareaと同じ
		view.dispatch({ selection: { anchor: start, head: end }, scrollIntoView: true });
	}
	Object.defineProperties(ta, {
		value: {
			configurable: true,
			get: function() { return view.state.doc.toString(); },
			set: function(text) {
				text = (text == null) ? '' : String(text);
				view.dispatch({
					changes:   { from: 0, to: view.state.doc.length, insert: text },
					selection: { anchor: text.replace(/\r\n?/g, "\n").length }
				});
			}
		},
		selectionStart: {
			configurable: true,
			get: function() { return view.state.selection.main.from; }
		},
		selectionEnd: {
			configurable: true,
			get: function() { return view.state.selection.main.to; }
		},
		setSelectionRange: {
			configurable: true,
			value: set_selection
		},
		focus: {
			configurable: true,
			value: function() { view.focus(); }
		},
		readOnly: {
			configurable: true,
			get: function() { return view.state.readOnly; },
			set: function(flag) {
				flag = !!flag;
				ta_readonly.set.call(ta, flag);
				$box.toggleClass('readonly', flag);
				view.dispatch({ effects: readonly.reconfigure( CM.EditorState.readOnly.of(flag) ) });
			}
		}
	});

	//----------------------------------------------------------------------
	// ●送るときに本文を入れる
	//----------------------------------------------------------------------
	if (ta.form) ta.form.addEventListener('formdata', function(evt){
		if (ta.disabled || !ta.name) return;
		evt.formData.set(ta.name, view.state.doc.toString());
	});
});
