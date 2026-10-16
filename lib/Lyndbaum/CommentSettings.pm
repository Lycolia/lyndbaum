package Lyndbaum::CommentSettings;
# コメントの設定の項目（settingsテーブルに保存する）。決まりはdocs/comments.md
#   項目の書き方は Lyndbaum::SettingsForm
use strict;
use warnings;
use utf8;

use Lyndbaum::SettingsForm;

our @FIELDS = (
	{ key => 'comments_enabled',          type => 'bool', default => 1, label => 'コメントを受け付ける' },
	{ key => 'comments_moderate_all',     type => 'bool', default => 0, label => 'すべてのコメントを承認待ちにする' },
	{ key => 'comments_require_japanese', type => 'bool', default => 1, label => '日本語を含まないコメントを承認待ちにする' },
	{ key => 'comments_js_token',         type => 'bool', default => 1, label => 'フォームのトークンをJavaScriptで入れる',
	  help => 'JavaScriptを動かさないボットをはじけます。その代わり、JavaScriptを切っている人は投稿できません。' },
	{ key => 'comments_rate_limit',       type => 'bool', default => 1, label => '連投を制限する' },
	{ key => 'comments_rate_count',       type => 'int',  default => 3,  min => 1, max => 100, label => '同じIPから投稿できる回数' },
	{ key => 'comments_rate_minutes',     type => 'int',  default => 10, min => 1, max => 1440, label => '連投を数える期間（分）' },
	{ key => 'comments_name_max',         type => 'int',  default => 32,   min => 1, max => 200,   label => '名前の文字数の上限' },
	{ key => 'comments_body_min',         type => 'int',  default => 5,    min => 0, max => 1000,  label => '本文の文字数の下限（文字と数字だけを数える）' },
	{ key => 'comments_body_max',         type => 'int',  default => 3000, min => 1, max => 100000, label => '本文の文字数の上限' },
	{ key => 'comments_body_lines',       type => 'int',  default => 100,  min => 1, max => 10000, label => '本文の行数の上限' },
	{ key => 'comments_ng_words',         type => 'lines', default => '', label => 'NGワード（含むコメントは承認待ち）',
	  help => '1行に1つ。大文字と小文字、全角と半角は区別しません。' },
	{ key => 'comments_block_ips',        type => 'lines', default => '', label => '拒否するIPアドレス',
	  help => '1行に1つ。192.0.2.10、192.0.2.0/24、192.0.2.（前方一致）、2001:db8::/32の形で書きます。',
	  check => sub { require Lyndbaum::AddressMatch; Lyndbaum::AddressMatch->valid_ip_rule($_[0]) } },
	{ key => 'comments_block_hosts',      type => 'lines', default => '', label => '拒否するホスト名',
	  help => '1行に1つ。example.netと書くと、その下のホスト（spam.example.netなど）も拒否します。',
	  check => sub { require Lyndbaum::AddressMatch; Lyndbaum::AddressMatch->valid_host_rule($_[0]) } },
);

my %FIELD = map { $_->{key} => $_ } @FIELDS;

sub fields { \@FIELDS }

sub defaults {
	return Lyndbaum::SettingsForm->defaults(\@FIELDS);
}

# フォームの値を確かめて、保存する値にする（Lyndbaum::SettingsForm->parse に、項目をまたぐ決まりを足す）
sub parse_form {
	my ($class, $get) = @_;
	my ($values, $errors) = Lyndbaum::SettingsForm->parse(\@FIELDS, $get);
	my %values = %$values;
	my @errors = @$errors;
	if (!@errors && $values{comments_body_min} > $values{comments_body_max}) {
		push @errors, { key => 'comments_body_min', message => '本文の文字数の下限は、上限以下にしてください。' };
	}
	return (\%values, \@errors);
}

# 一覧の設定を配列にする
sub lines_of {
	my ($class, $settings, $key) = @_;
	return [ grep { $_ ne '' } split /\n/, $settings->{$key} // '' ];
}

# 一覧の設定に1行足した値（すでにあれば変えない）
sub add_line {
	my ($class, $settings, $key, $line) = @_;
	my $lines = $class->lines_of($settings, $key);
	push @$lines, $line if !grep { $_ eq $line } @$lines;
	return join "\n", @$lines;
}

sub field { $FIELD{ $_[1] } }

1;
