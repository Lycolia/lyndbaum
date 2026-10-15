# ファイルを送るフォームの本文（Lyndbaum::Multipart、Lyndbaum::Request->uploads）
use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(encode_utf8);
use Lyndbaum::Multipart;
use Lyndbaum::Request;
use TestUtil ();

my $B = 'XyZ123';
# 1つの欄。$value はバイト列（ファイルの中身）か文字列（UTF-8 にする）
sub part {
	my ($name, $value, %opt) = @_;
	my $disposition = qq{form-data; name="$name"} . (defined $opt{filename} ? qq{; filename="$opt{filename}"} : '');
	my $head = "--$B\r\nContent-Disposition: $disposition\r\n" . (defined $opt{type} ? "Content-Type: $opt{type}\r\n" : '') . "\r\n";
	return encode_utf8($head) . (utf8::is_utf8($value) ? encode_utf8($value) : $value) . "\r\n";
}
my $JPEG = "\xFF\xD8\xFF\r\n--not-boundary\r\nbinary";
utf8::downgrade($JPEG);
# ブラウザはファイル名の " を %22 にして送る
my $body = part(csrf_token => 'tok') . part(title => '題名')
	. part(file => $JPEG, filename => '写真 %221%22.jpg', type => 'image/jpeg')
	. part(file => 'PNG', filename => 'b.png', type => 'image/png')
	. part(file => '', filename => '') . "--$B--\r\n";

subtest 'boundary' => sub {
	is(Lyndbaum::Multipart->boundary_of("multipart/form-data; boundary=$B"), $B);
	is(Lyndbaum::Multipart->boundary_of('multipart/form-data; boundary="a b"'), 'a b');
	is(Lyndbaum::Multipart->boundary_of('application/x-www-form-urlencoded'), undef);
};

subtest '分ける' => sub {
	my ($params, $files) = Lyndbaum::Multipart->parse($body, $B);
	is_deeply $params, { csrf_token => ['tok'], title => ['題名'] }, '値は UTF-8 として読む';
	is scalar @{ $files->{file} }, 2, 'ファイルを選ばずに送られた欄は除く';
	is $files->{file}[0]{filename}, '写真 "1".jpg';
	is $files->{file}[0]{type}, 'image/jpeg';
	is $files->{file}[0]{data}, $JPEG, '中身に改行や -- があってもよい';
	ok !utf8::is_utf8($files->{file}[0]{data}), '中身はバイト列';
	eval { Lyndbaum::Multipart->parse("garbage", $B) };
	like $@, qr{正しくありません};
};

subtest 'Request' => sub {
	my $request = sub {
		my ($max) = @_;
		open my $in, '<', \$body or die;
		return Lyndbaum::Request->new({ REQUEST_METHOD => 'POST', CONTENT_TYPE => "multipart/form-data; boundary=$B",
			CONTENT_LENGTH => length $body }, input => $in, max_upload => $max);
	};
	my $req = $request->(1024);
	is $req->body_param('title'), '題名';
	is_deeply [ map { $_->{filename} } $req->uploads('file') ], ['写真 "1".jpg', 'b.png'];
	ok !$req->body_too_large;

	$req = $request->(10);
	ok $req->body_too_large, '上限より大きければ読まない';
	is $req->body_param('csrf_token'), undef;
	is_deeply [ $req->uploads('file') ], [];
};

done_testing;
