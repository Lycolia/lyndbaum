package Lyndbaum::CommentPolicy;
# コメントの投稿の決まり（docs/comments.md の「投稿」）
#   DBやリクエストには触らず、渡された値だけで判断する（テストしやすくするため）
use strict;
use warnings;
use utf8;

use Unicode::Normalize qw(NFKC);
use Lyndbaum::AddressMatch;
use Lyndbaum::CommentSettings;

# 名前と本文をそろえる：改行を LF にし、前後の空白を取り除く
sub normalize {
	my ($class, $text) = @_;
	$text //= '';
	$text =~ s/\r\n?/\n/g;
	$text =~ s/\A\s+|\s+\z//g;
	return $text;
}

# 長さの決まりに合わないときの、理由の一覧（人に見せる）
#   %opt
#     admin  真なら本文の下限を見ない
sub length_errors {
	my ($class, $settings, $name, $body, %opt) = @_;
	my @errors;
	if ($name eq '') {
		push @errors, '名前を書いてください。';
	} elsif (length $name > $settings->{comments_name_max}) {
		push @errors, "名前は$settings->{comments_name_max}文字以内で書いてください。";
	}
	if ($body eq '') {
		push @errors, '本文を書いてください。';
	} else {
		my $letters = () = $body =~ /[\p{L}\p{N}]/g;
		push @errors, "本文は$settings->{comments_body_min}文字以上で書いてください（空白と記号は数えません）。"
			if !$opt{admin} && $letters < $settings->{comments_body_min};
		push @errors, "本文は$settings->{comments_body_max}文字以内で書いてください。"
			if length $body > $settings->{comments_body_max};
		my $lines = 1 + ($body =~ tr/\n//);
		push @errors, "本文は$settings->{comments_body_lines}行以内で書いてください。"
			if $lines > $settings->{comments_body_lines};
	}
	return \@errors;
}

# 理由を返さずにはじくなら、その理由（記録用。人には見せない）。はじかないなら undef
#   %args
#     ip, host          投稿した人のIPアドレスとホスト名
#     name              そろえた名前
#     admin_names       管理者の名前の一覧（なりすましを見るため）
#     recent_count      その IP から、連投を数える期間に投稿された件数
sub reject_reason {
	my ($class, $settings, %args) = @_;
	return 'blocked_ip'
		if Lyndbaum::AddressMatch->ip_matches($args{ip}, Lyndbaum::CommentSettings->lines_of($settings, 'comments_block_ips'));
	return 'blocked_host'
		if Lyndbaum::AddressMatch->host_matches($args{host}, Lyndbaum::CommentSettings->lines_of($settings, 'comments_block_hosts'));
	my $name = _fold($args{name});
	return 'admin_name' if grep { _fold($_) eq $name } @{ $args{admin_names} // [] };
	return 'rate_limit' if $settings->{comments_rate_limit} && ($args{recent_count} // 0) >= $settings->{comments_rate_count};
	return undef;
}

# 承認待ちにするなら、その理由の一覧（記録用）。空なら公開する
sub hold_reasons {
	my ($class, $settings, $name, $body) = @_;
	my @reasons;
	push @reasons, 'moderate_all' if $settings->{comments_moderate_all};
	push @reasons, 'url' if $body =~ m{h?ttps?://}i || "$name" =~ m{h?ttps?://}i;
	my $folded = _fold("$name\n$body");
	push @reasons, 'ng_word'
		if grep { index($folded, _fold($_)) >= 0 } @{ Lyndbaum::CommentSettings->lines_of($settings, 'comments_ng_words') };
	push @reasons, 'not_japanese'
		if $settings->{comments_require_japanese} && $body !~ /[\p{Hiragana}\p{Katakana}\p{Han}]/;
	return \@reasons;
}

# 比べるための形：全角と半角をそろえ（NFKC）、小文字にし、空白を除く
sub _fold {
	my ($text) = @_;
	my $folded = lc NFKC($text // '');
	$folded =~ s/\s+//g;
	return $folded;
}

1;
