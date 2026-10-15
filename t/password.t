# パスワードのハッシュ（Lyndbaum::Password）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Password;
use TestUtil ();

# PBKDF2-HMAC-SHA256 の試験値（RFC 7914 の 11 節）
is unpack('H*', Lyndbaum::Password::_pbkdf2('passwd', 'salt', 1)),
	'55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc', 'RFC 7914（反復1回）';
is unpack('H*', Lyndbaum::Password::_pbkdf2('Password', 'NaCl', 80000)),
	'4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56', 'RFC 7914（反復80000回）';

my $hash = Lyndbaum::Password->hash('パスワード', iterations => 1000);
like $hash, qr{\Apbkdf2-sha256\$1000\$[A-Za-z0-9+/=]{24}\$[A-Za-z0-9+/=]{44}\z}, '保存する形';
ok(Lyndbaum::Password->verify('パスワード', $hash), '合う');
ok(!Lyndbaum::Password->verify('パスワート', $hash), '違う');
isnt(Lyndbaum::Password->hash('パスワード', iterations => 1000), $hash, 'ソルトは毎回変わる');
ok(!Lyndbaum::Password->verify('x', $_), "壊れたハッシュ：$_") for '', 'md5$1$a$b', 'pbkdf2-sha256$0$a$b', 'pbkdf2-sha256$1000$a';

ok(Lyndbaum::Password::equal('abc', 'abc'));
ok(!Lyndbaum::Password::equal('abc', 'abd'));
ok(!Lyndbaum::Password::equal('abc', 'ab'));

# パスワードの決まり
is(Lyndbaum::Password->format_error('correct horse battery'), undef, 'ASCII の英数字と記号、空白');
is(Lyndbaum::Password->format_error('!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~'), undef, '印字できる記号はすべて使える');
is(Lyndbaum::Password->format_error('a' x 64), undef, '64文字まで');
like(Lyndbaum::Password->format_error('a' x 65), qr{64文字まで}, '65文字は長すぎる');
like(Lyndbaum::Password->format_error('a' x 11), qr{12文字以上}, '11文字は短すぎる');
like(Lyndbaum::Password->format_error('パスワードパスワードパスワード'), qr{ASCII}, 'ASCII でない文字は使えない');
like(Lyndbaum::Password->format_error("tab\tinside-password"), qr{ASCII}, '制御文字も使えない');
like(Lyndbaum::Password->format_error(''), qr{入れてください});

done_testing;
