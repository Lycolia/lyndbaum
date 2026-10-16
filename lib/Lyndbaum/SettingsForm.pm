package Lyndbaum::SettingsForm;
# 管理画面の設定の項目（settingsテーブルに保存する）を読む共通の部品
#   項目は { key, type, default, label, help, min, max, check } の並び（Lyndbaum::CommentSettings など）
#
#   型
#     bool   0か1
#     int    整数（min以上max以下）
#     lines  1行に1つの一覧。checkで1行ずつ書き方を確かめる
#     text   1行の文字。前後の空白を除く。required なら空にできない。max は文字数の上限。check で書き方を確かめる
#            media が真なら、画面に「ファイル一覧から選択」を出す（添付ファイルの中のパスを入れる）
use strict;
use warnings;
use utf8;

sub defaults {
	my ($class, $fields) = @_;
	return map { $_->{key} => $_->{default} } @$fields;
}

# フォームの値を確かめて、保存する値にする
#   $getは項目名からフォームの値を返す関数
#   戻り値は(\%values, \@errors)。errorsは { key, message } の並び
sub parse {
	my ($class, $fields, $get) = @_;
	my (%values, @errors);
	for my $field (@$fields) {
		my $key = $field->{key};
		my $raw = $get->($key) // '';
		if ($field->{type} eq 'bool') {
			$values{$key} = $raw eq '1' ? 1 : 0;
		} elsif ($field->{type} eq 'int') {
			$raw =~ s/\A\s+|\s+\z//g;
			$values{$key} = $raw;
			if ($raw !~ /\A\d{1,9}\z/ || $raw < $field->{min} || $raw > $field->{max}) {
				push @errors, { key => $key, message => "$field->{label}は、$field->{min}から$field->{max}までの整数で書いてください。" };
			} else {
				$values{$key} = 0 + $raw;
			}
		} elsif ($field->{type} eq 'text') {
			(my $text = $raw) =~ s/\A\s+|\s+\z//g;
			$text =~ s/[\r\n]+/ /g;
			$values{$key} = $text;
			if ($field->{required} && $text eq '') {
				push @errors, { key => $key, message => "$field->{label}を書いてください。" };
			} elsif ($field->{max} && length $text > $field->{max}) {
				push @errors, { key => $key, message => "$field->{label}は$field->{max}文字までにしてください。" };
			} elsif ($text ne '' && $field->{check} && !$field->{check}->($text)) {
				push @errors, { key => $key, message => "$field->{label}の書き方が正しくありません。" };
			}
		} else {
			my @lines = grep { $_ ne '' } map { s/\A\s+|\s+\z//gr } split /\r?\n/, $raw;
			my %seen;
			@lines = grep { !$seen{$_}++ } @lines;
			$values{$key} = join "\n", @lines;
			if ($field->{check}) {
				for my $line (grep { !$field->{check}->($_) } @lines) {
					push @errors, { key => $key, message => "$field->{label}の「$line」は、書き方が正しくありません。" };
				}
			}
		}
	}
	return (\%values, \@errors);
}

1;
