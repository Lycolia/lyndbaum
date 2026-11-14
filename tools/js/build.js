// src/*.jsを1本ずつminifyし、pub/assets/js/<name>.min.jsとソースマップを作る
'use strict';
const fs   = require('fs');
const path = require('path');
const { minify } = require('terser');

const SRC = path.join(__dirname, 'src');
const OUT = path.join(__dirname, '../../pub/assets/js');

(async function() {
	const files = fs.readdirSync(SRC).filter(f => f.endsWith('.js')).sort();
	for (const f of files) {
		const name = f.replace(/\.js$/, '');
		const code = fs.readFileSync(path.join(SRC, f), 'utf8');
		const res  = await minify({ [f]: code }, {
			compress: true,
			mangle:   true,
			// 著作権の表記（(C)の行）は残す
			format:    { comments: /\(C\)/ },
			sourceMap: { includeSources: true, url: name + '.min.js.map' }
		});
		fs.writeFileSync(path.join(OUT, name + '.min.js'),     res.code);
		fs.writeFileSync(path.join(OUT, name + '.min.js.map'), res.map);
		console.log(name + '.min.js');
	}
})().catch(e => { console.error(e); process.exit(1); });
