#!/usr/bin/env perl
# 管理者のログイン名とパスワードを登録する（すでにいれば置き換える）
#   perl tools/set-password.pl [設定ファイル]
# ログイン名とパスワードは端末で尋ねる。パスワードは画面に出さない
# 今のセッションはすべて消す（ログインし直す）
# Web の初期設定画面は作らない（設定する前に、他人に管理者を登録されないようにするため）
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../extlib";

use Encode qw(decode);
use Lyndbaum::App;
use Lyndbaum::Model::Admin;
use Lyndbaum::Password;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $root = "$FindBin::Bin/..";
my $app  = Lyndbaum::App->new(root => $root, config_file => $ARGV[0] // "$root/config.json");

my $login = ask('ログイン名: ');
die "ログイン名を入れてください\n" if $login eq '';
my $password = ask('パスワード: ', 1);
if (my $error = Lyndbaum::Password->format_error($password)) {
	die "$error\n";
}
die "パスワードが一致しません\n" if ask('もう一度: ', 1) ne $password;

Lyndbaum::Model::Admin->set_password($app->db, $login, $password);
print "管理者「$login」を登録しました（ログイン中のセッションはすべて消したので、ログインし直してください）\n";

# 途中で止めても、入力を画面に出す設定に戻す
$SIG{INT} = sub { exit 130 };
END { system 'stty', 'echo' if -t STDIN }

# 端末から1行読む。$secret なら入力を画面に出さない
sub ask {
	my ($prompt, $secret) = @_;
	print $prompt;
	system 'stty', '-echo' if $secret && -t STDIN;
	my $line = <STDIN>;
	if ($secret && -t STDIN) {
		system 'stty', 'echo';
		print "\n";
	}
	die "入力がありません\n" if !defined $line;
	chomp $line;
	return decode('UTF-8', $line);
}
