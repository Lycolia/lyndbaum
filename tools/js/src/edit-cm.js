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
// CodeMirrorは見えている行の付近だけをDOMにするので、ブラウザのページ内検索は
// 画面外の行に届かない。編集欄の中のCtrl+Fか「検索」ボタン（#edit-search、スマホ向け）で、
// CodeMirrorの検索・置換の欄を出す。
// codemirror.min.jsが読めないときは、textareaのまま。
'use strict';
adiary.ready(function(){
	const CM = window.CM6;
	const ta = document.getElementById('editarea');
	if (!CM || !ta) return;

	const proto = HTMLTextAreaElement.prototype;
	const ta_value    = Object.getOwnPropertyDescriptor(proto, 'value');
	const ta_readonly = Object.getOwnPropertyDescriptor(proto, 'readOnly');

	const box = document.createElement('div');
	box.id        = 'editarea-cm';
	box.className = 'edit-article';
	ta.after(box);
	ta.style.display = 'none';

	//----------------------------------------------------------------------
	// ●記法の色分け（edit-helper.jsのHelpersと同じ判定）
	//----------------------------------------------------------------------
	// Markdownは、Lyndbaumの記法に合わせて読む（tools/codemirror/lyndbaum-markdown.js）。
	// さつき記法のタグは、サーバーのタグ定義にある名前だけをタグとして色分けする（data-satsuki-tags）
	const parsel  = adiary.secure('#select-parser');
	const lang    = new CM.Compartment();
	const tag_names = (ta.getAttribute('data-satsuki-tags') || '').split(/\s+/).filter(Boolean);
	function lang_ext() {
		const parser = parsel && parsel.value || '';
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
	// ●検索・置換
	//----------------------------------------------------------------------
	// キーは検索に関わるものだけ（Ctrl+F、F3/Ctrl+G、Shift+F3/Shift+Ctrl+G、ESC）。
	// Ctrl+D（次の一致を選ぶ）、Ctrl+Alt+G（行へ移る）、Ctrl+Shift+Lは入れない
	const search_keys = CM.searchKeymap.filter(function(k){
		return k.key.match(/^(?:Mod-f|F3|Mod-g|Escape)$/);
	});
	const search_phrases = CM.EditorState.phrases.of({
		'Find':				'検索',
		'Replace':			'置換',
		'next':				'次へ',
		'previous':			'前へ',
		'all':				'すべて選択',
		'match case':			'大文字と小文字を区別',
		'regexp':			'正規表現',
		'by word':			'単語単位',
		'replace':			'置換',
		'replace all':			'すべて置換',
		'close':			'閉じる',
		'current match':		'現在の一致',
		'on line':			'行',
		'replaced match on line $':	'$行目を置換しました',
		'replaced $ matches':		'$件を置換しました'
	});

	//----------------------------------------------------------------------
	// ●作る
	//----------------------------------------------------------------------
	const readonly = new CM.Compartment();
	const view = new CM.EditorView({
		parent: box,
		state:  CM.EditorState.create({
			doc: ta_value.get.call(ta),
			extensions: [
				CM.history(),
				CM.EditorView.lineWrapping,
				CM.EditorState.tabSize.of(8),
				tab_keys,
				// 単語単位は使わない（ひらがなや漢字も単語の文字なので、文の中の語が見つからない）。
				// チェックボックスはadmin.cssで隠す
				CM.search({ top: true, wholeWord: false }),
				search_phrases,
				CM.keymap.of([
					{ key: 'Enter', run: CM.insertNewline },
					...search_keys,
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
	box.classList.toggle('readonly', ta_readonly.get.call(ta));

	// 「検索」ボタン。開いているときに押すと閉じる
	const search_btn = document.getElementById('edit-search');
	if (search_btn) {
		search_btn.style.display = '';
		search_btn.addEventListener('click', function(){
			if (CM.searchPanelOpen(view.state))
				CM.closeSearchPanel(view);
			else
				CM.openSearchPanel(view);
		});
	}

	if (parsel) parsel.addEventListener('change', function(){
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
				box.classList.toggle('readonly', flag);
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
