package Lyndbaum::SettingsForm;
# 管理画面の設定の項目（settingsテーブルに保存する）を読む共通の部品
#   項目は { key, type, default, label, help, min, max, check } の並び（Lyndbaum::CommentSettings など）
#
#   型
#     bool   0か1
#     int    整数（min以上max以下）
#            presets（数の配列）があれば、選択肢と「直接入力」で入れる（preset_field）。unitは数の後ろに付ける単位
#            フォームでは、項目名に選んだ数（直接入力ならother）が、「項目名_other」に入れた数が来る
#     lines  1行に1つの一覧。checkで1行ずつ書き方を確かめる
#     text   1行の文字。前後の空白を除く。requiredなら空にできない。maxは文字数の上限。checkで書き方を確かめる
#            media が真なら、画面に「ファイル一覧から選択」を出す（添付ファイルの中のパスを入れる）
#     html   複数行の文字をそのまま（改行は LF にそろえ、前後の空白行だけ除く）。maxは文字数の上限
use strict;
use warnings;
use utf8;

sub defaults {
	my ($class, $fields) = @_;
	return map { $_->{key} => $_->{default} } @$fields;
}

# フォームの値を確かめて、保存する値にする
#   $getは項目名からフォームの値を返す関数
#   戻り値は(\%values, \@errors)。errorsは{ key, message }の並び
sub parse {
	my ($class, $fields, $get) = @_;
	my (%values, @errors);
	for my $field (@$fields) {
		my $key = $field->{key};
		my $raw = $get->($key) // '';
		if ($field->{type} eq 'bool') {
			$values{$key} = $raw eq '1' ? 1 : 0;
		} elsif ($field->{type} eq 'int') {
			$raw = $get->("${key}_other") // '' if $field->{presets} && $raw eq 'other';
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
		} elsif ($field->{type} eq 'html') {
			(my $text = $raw) =~ s/\r\n?/\n/g;
			$text =~ s/\A\s*\n|\s+\z//g;
			$values{$key} = $text;
			if ($field->{max} && length $text > $field->{max}) {
				push @errors, { key => $key, message => "$field->{label}は$field->{max}文字までにしてください。" };
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

# 選択肢と「直接入力」の欄（templates/preset_field.html）に渡す値。$fieldはpresetsのあるintの項目
#   $valueが選択肢にあればそれを選び、無ければ「直接入力」を選んで、入力欄にその値を入れておく
#   %optのnameはフォームの項目名（無ければnameを付けない。フォームで送らず、JavaScriptで読むとき）
sub preset_field {
	my ($class, $field, $value, %opt) = @_;
	my $unit   = $field->{unit} // '';
	my $preset = defined $value && grep { $_ eq $value } @{ $field->{presets} };
	return {
		name    => $opt{name},
		label   => $field->{label},
		unit    => $unit,
		min     => $field->{min},
		max     => $field->{max},
		value   => $value,
		other   => $preset ? 0 : 1,
		options => [
			(map { +{ value => $_, label => "$_$unit", selected => defined $value && $_ eq $value } } @{ $field->{presets} }),
			{ value => 'other', label => '直接入力', selected => !$preset },
		],
	};
}

1;
