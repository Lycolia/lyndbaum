# index.cgi を実際にCGIとして起動して、出力の形を確かめる
use strict;
use warnings;
use utf8;
use Test::More;

use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;

use Encode qw(decode_utf8);
use Lyndbaum::DB;
use TestUtil qw(root_dir insert_article);

my $dir     = tempdir(CLEANUP => 1);
my $db_path = File::Spec->catfile($dir, 'test.db');
my $dbh     = Lyndbaum::DB->connect($db_path);
Lyndbaum::DB->migrate($dbh, File::Spec->catdir(root_dir(), 'db', 'migrations'));
insert_article($dbh, id => 7, title => 'こんにちは');
$dbh->disconnect;

my $config = File::Spec->catfile($dir, 'config.json');
open my $fh, '>', $config or die $!;
print $fh encode_json({ db_path => $db_path });
close $fh;

# %env は環境変数。STDIN を渡すと、それを標準入力にする（POST の本文）
sub run_cgi {
	my (%env) = @_;
	my $stdin = delete $env{STDIN} // '';
	my $input = File::Spec->catfile($dir, 'stdin');
	open my $in, '>:raw', $input or die $!;
	print $in $stdin;
	close $in;
	local %ENV = (%ENV, LYNDBAUM_CONFIG => $config, REQUEST_METHOD => 'GET', %env);
	my $cgi = File::Spec->catfile(root_dir(), 'index.cgi');
	return decode_utf8(scalar `$^X $cgi < $input 2>/dev/null`);
}

subtest '記事を表示する' => sub {
	my $out = run_cgi(PATH_INFO => '/07');
	like $out, qr{\AStatus: 200 OK\r\n}, 'ステータス行';
	like $out, qr{^Content-Type: text/html; charset=UTF-8\r$}m, 'Content-Type';
	like $out, qr{\r\n\r\n<!DOCTYPE html>}, 'ヘッダーと本文の区切り';
	like $out, qr{<h1 class="article-title">こんにちは</h1>}, 'UTF-8で出力する';
};

subtest 'POST の本文を標準入力から読む' => sub {
	my $body = 'login=admin&password=wrong';
	my $out = run_cgi(
		PATH_INFO => '/admin/login', REQUEST_METHOD => 'POST', HTTP_HOST => 'blog.example', HTTP_ORIGIN => 'http://blog.example',
		CONTENT_TYPE => 'application/x-www-form-urlencoded', CONTENT_LENGTH => length $body, STDIN => $body,
	);
	like $out, qr{\AStatus: 401 }, '管理者が登録されていないので、ログインできない';
	like $out, qr{name="login" value="admin"}, 'フォームの値を読めている';
};

subtest '例外が起きたら500' => sub {
	my $out = run_cgi(PATH_INFO => '/07', LYNDBAUM_CONFIG => File::Spec->catfile($dir, 'missing.json'));
	like $out, qr{\AStatus: 500 Internal Server Error\r\n};
};

done_testing;
