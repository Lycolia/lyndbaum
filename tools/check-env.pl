#!/usr/bin/env perl
# 動かす環境を確かめる（docs/deploy.md）。サーバーに置いたら、最初に実行する
#   perl tools/check-env.pl [設定ファイル]
# 足りないものがあれば「NG」と出し、終了コードを 1 にする。「注意」は動くが確かめてほしいもの
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../extlib";
use Cwd qw(abs_path);
use File::Spec;

binmode STDOUT, ':encoding(UTF-8)';
my $root = abs_path("$FindBin::Bin/..");
my $ng = 0;
sub ok   { printf "OK    %s\n", join ' ', @_ }
sub ng   { printf "NG    %s\n", join ' ', @_; $ng = 1 }
sub warn_ { printf "注意  %s\n", join ' ', @_ }

print "== Perl\n";
$] >= 5.032001 ? ok("Perl $^V（$^X）") : ng("Perl $^V。5.32.1 以上が要る");

print "== モジュール\n";
my @modules = (
	# 名前, 無いときに困ること（空なら必須）
	[ 'DBI' ], [ 'DBD::SQLite' ], [ 'JSON::PP' ], [ 'Encode' ], [ 'Digest::SHA' ], [ 'HTTP::Tiny' ],
	[ 'File::Temp' ], [ 'File::Path' ], [ 'File::Copy' ], [ 'Time::Local' ], [ 'URI' ], [ 'HTML::Entities' ],
	[ 'Unicode::Normalize' ], [ 'IO::Socket::IP' ],
	[ 'GD', 'サムネイルを作れない（画像は元の大きさで出す）' ],
	[ 'IO::Socket::SSL', '[&URL] のページのタイトルを https で取れない' ],
	[ 'Mozilla::CA', 'OS の証明書で https を確かめる（下の「https」が OK なら困らない）' ],
);
for my $m (@modules) {
	my ($name, $optional) = @$m;
	(my $file = "$name.pm") =~ s{::}{/}g;
	if (eval { require $file; 1 }) {
		ok($name, $name->VERSION // '');
	} elsif ($optional) {
		warn_("$name が無い：$optional");
	} else {
		ng("$name が無い");
	}
}

print "== SQLite\n";
if (eval { require DBI; require DBD::SQLite; 1 }) {
	my $dbh = DBI->connect('dbi:SQLite:dbname=:memory:', '', '', { RaiseError => 1, PrintError => 0 });
	my $version = $dbh->{sqlite_version};
	# 使っている機能：再帰の CTE（タグの閉包テーブル、ページの子孫）、ALTER TABLE ADD COLUMN、WITHOUT ROWID、IS（NULL を等しいとみなす比較）
	my @checks = (
		[ '再帰の CTE', 'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 3) SELECT COUNT(*) FROM n' ],
		[ 'WITHOUT ROWID', 'CREATE TABLE t (k TEXT PRIMARY KEY) WITHOUT ROWID' ],
		[ 'ALTER TABLE ADD COLUMN', q{ALTER TABLE t ADD COLUMN v TEXT NOT NULL DEFAULT '' CHECK (v IN ('', 'a'))} ],
		[ 'IS による比較', 'SELECT NULL IS NULL' ],
	);
	my @failed = grep { !eval { $dbh->do($_->[1]); 1 } } @checks;
	@failed ? ng("SQLite $version：" . join('、', map { $_->[0] } @failed) . 'が使えない') : ok("SQLite $version");
}

print "== GD\n";
if (eval { require GD; 1 }) {
	for my $kind (qw(Jpeg Png Gif Webp)) {
		GD::Image->can("newFrom${kind}Data") ? ok("GD は $kind を読める")
			: warn_("GD は $kind を読めない（その種類の画像はサムネイルを作らない）");
	}
	my $image = GD::Image->new(2, 2, 1);
	eval { $image->jpeg(85); 1 } ? ok('GD は JPEG を書ける（サムネイル）') : ng('GD は JPEG を書けない');
}

print "== パスワード\n";
# 管理者のパスワードは、OS の crypt(3) の bcrypt でハッシュにする（Lyndbaum::Password）
my $bcrypt = '$2b$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW';
(crypt('U*U', $bcrypt) // '') eq $bcrypt ? ok('crypt(3) は bcrypt（$2b$）に対応している')
	: ng('crypt(3) が bcrypt（$2b$）に対応していない（管理者のパスワードを登録できない）');

print "== https\n";
require HTTP::Tiny;
my ($can_ssl, $why) = HTTP::Tiny->can_ssl;
$can_ssl ? ok('HTTP::Tiny は https を使える') : warn_("HTTP::Tiny は https を使えない：$why");

print "== 設定\n";
my $config_file = $ARGV[0] // "$root/config.json";
my $config;
if (!-f $config_file) {
	ng("$config_file が無い（config.sample.json を写して作る）");
} else {
	require Lyndbaum::Config;
	$config = eval { Lyndbaum::Config->load($config_file) };
	if (!$config) {
		ng("$config_file を読めない：$@");
	} else {
		ok($config_file);
		my $mode = (stat $config_file)[2] & 07777;
		$mode & 077 ? warn_(sprintf '%s の権限が %04o。ほかの人に読ませないよう 600 にする', $config_file, $mode) : ok(sprintf '%s の権限 %04o', $config_file, $mode);
		($config->get('site_url') // '') =~ m{\Ahttps?://[^/]+} ? ok('site_url', $config->get('site_url')) : ng('site_url が無い（例：https://blog.example.jp）');
		length($config->get('secret_key') // '') >= 32 ? ok('secret_key') : warn_('secret_key が無いか短い（コメントのフォームを出さない。作り方は docs/deploy.md）');
		ng('cookie_secure が false（https で動かすなら消すか true にする）') if defined $config->get('cookie_secure') && !$config->get('cookie_secure');
	}
}

print "== ファイルとフォルダ\n";
my $cgi = "$root/index.cgi";
my $cgi_mode = (stat $cgi)[2] & 07777;
!-x $cgi ? ng("$cgi に実行の権限が無い（755 にする）")
	: $cgi_mode & 022 ? ng(sprintf '%s の権限が %04o。グループやほかの人が書き込めると動かない（755 にする）', $cgi, $cgi_mode)
	: ok(sprintf '%s の権限 %04o', $cgi, $cgi_mode);
-f "$root/.htaccess" ? ok("$root/.htaccess") : ng("$root/.htaccess が無い（index.cgi に振り分けられず、config.json などが見えてしまう）");
for my $dir ("$root/var", "$root/pub", "$root/pub/attachments") {
	if (!-d $dir) {
		ng("$dir が無い（作る）");
		next;
	}
	-w $dir ? ok("$dir に書き込める") : ng("$dir に書き込めない");
}
my $var_mode = -d "$root/var" ? (stat "$root/var")[2] & 07777 : 0;
warn_(sprintf '%s/var の権限が %04o。ほかの人に読ませないよう 700 にする', $root, $var_mode) if $var_mode & 077;

if ($config) {
	require Lyndbaum::DB;
	my $db = $config->path_of('db_path', $root);
	if (-f $db) {
		my $dbh = eval { Lyndbaum::DB->connect($db) };
		my @files = glob "$root/db/migrations/*.sql";
		my $version = $dbh ? $dbh->selectrow_array('PRAGMA user_version') : -1;
		$version == @files ? ok("DB $db（スキーマは最新）") : ng("DB $db のスキーマが古い（perl tools/migrate.pl を実行する）");
		my $admin = $dbh ? $dbh->selectrow_array('SELECT COUNT(*) FROM admin') : 0;
		$admin ? ok('管理者が登録されている') : ng('管理者が登録されていない（perl tools/set-password.pl を実行する）');
	} else {
		ng("DB $db が無い（perl tools/migrate.pl を実行する）");
	}
}

print $ng ? "\n足りないものがあります（NG）。\n" : "\n動かせます。\n";
exit($ng ? 1 : 0);
