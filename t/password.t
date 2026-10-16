# パスワードのハッシュ（Lyndbaum::Password）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Password;
use TestUtil ();

# bcrypt の試験値（OpenBSD の bcrypt のテストにある値。$2a$ と $2b$ は、短い ASCII のパスワードなら同じ結果になる）
my $vector = '$2b$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW';
ok(Lyndbaum::Password->verify('U*U', $vector), '試験値と合う');
ok(!Lyndbaum::Password->verify('U*V', $vector), '試験値と違う');

my $hash = Lyndbaum::Password->hash('パスワード', cost => 4);
like $hash, qr{\A\$2b\$04\$[./A-Za-z0-9]{53}\z}, '保存する形';
ok(Lyndbaum::Password->verify('パスワード', $hash), '合う');
ok(!Lyndbaum::Password->verify('パスワート', $hash), '違う');
isnt(Lyndbaum::Password->hash('パスワード', cost => 4), $hash, 'ソルトは毎回変わる');
like(Lyndbaum::Password->hash('x', cost => 4), qr{\A\$2b\$04\$}, 'コストを変えられる');
ok(Lyndbaum::Password->verify("\x{30CF}\x{309A}スワード", Lyndbaum::Password->hash("\x{30D1}スワード", cost => 4)), 'NFC にそろえて比べる');
ok(!Lyndbaum::Password->verify('x', $_), "壊れたハッシュ：$_")
	for '', 'md5$1$a$b', 'pbkdf2-sha256$1000$a$b', '$2b$05$CCCC', '$2b$03$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW';

is Lyndbaum::Password::_bcrypt_base64("\0" x 16), '.' x 22, 'bcrypt の base64';

ok(Lyndbaum::Password::equal('abc', 'abc'));
ok(!Lyndbaum::Password::equal('abc', 'abd'));
ok(!Lyndbaum::Password::equal('abc', 'ab'));

# パスワードの決まり
is(Lyndbaum::Password->format_error('correct horse battery'), undef, 'ASCII の英数字と記号、空白');
is(Lyndbaum::Password->format_error('!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~'), undef, '印字できる記号はすべて使える');
is(Lyndbaum::Password->format_error('パスワードパスワードパスワード'), undef, 'ASCII でない文字も使える');
is(Lyndbaum::Password->format_error("tab\tinside-password"), undef, '制御文字も使える');
is(Lyndbaum::Password->format_error('a' x 72), undef, '72バイトまで');
like(Lyndbaum::Password->format_error('a' x 73), qr{72バイトまで}, '73バイトは長すぎる');
is(Lyndbaum::Password->format_error('あ' x 24), undef, '日本語なら24文字（72バイト）まで');
like(Lyndbaum::Password->format_error('あ' x 23 . 'abcd'), qr{72バイトまで}, '日本語を混ぜて73バイト');
like(Lyndbaum::Password->format_error('a' x 11), qr{12文字以上}, '11文字は短すぎる');
like(Lyndbaum::Password->format_error("nul\0inside-password"), qr{NUL}, 'NUL は使えない');
like(Lyndbaum::Password->format_error(''), qr{入れてください});

done_testing;
