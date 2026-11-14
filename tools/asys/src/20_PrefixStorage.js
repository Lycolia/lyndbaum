//##############################################################################
// Prefix Storage
//							(C)2019-2022 nabe@abk
//##############################################################################
// PrefixStorage's source is MIT License
//
//impliment methods: set(), get(), remove(), clear()
//
window.PrefixStorage = function(path) {
	this.ls     = localStorage;
	this.prefix = String(path) + '::';
}

//------------------------------------------------------------------------------
// member functions
//------------------------------------------------------------------------------
PrefixStorage.prototype.set = function (key,val) {
	this.ls[this.prefix + key] = val;
};
PrefixStorage.prototype.get = function (key) {
	return this.ls[this.prefix + key];
};
PrefixStorage.prototype.getInt = function (key) {
	const v = this.ls[this.prefix + key];
	if (v==undefined) return 0;
	return Number(v);
};
PrefixStorage.prototype.defined = function (key) {
	return (this.ls[this.prefix + key] !== undefined);
};
PrefixStorage.prototype.remove = function(key) {
	this.ls.removeItem(this.prefix + key);
};
PrefixStorage.prototype.allclear = function() {
	this.ls.clear();
};
PrefixStorage.prototype.clear = function(key) {
	const ls  = this.ls;
	const pf  = this.prefix;
	const len = pf.length;

	const ary = [];
	for(let i=0; i<ls.length; i++) {
		const k = ls.key(i);
		if (k.substr(0,len) === pf) ary.push(k);
	}
	// Do not delete in upper loop
	for(var k in ary) {
		delete ls[ary[k]];
	}
};
