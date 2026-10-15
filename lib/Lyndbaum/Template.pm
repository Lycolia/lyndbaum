package Lyndbaum::Template;
# 小さなテンプレートエンジン
#
#   {{ a.b.c }}                    値を出す（HTMLエスケープする）
#   {{ raw a.b }}                  値をエスケープせずに出す。使う箇所には理由をコメントで残す
#   {{# if a.b }} … {{# else }} … {{/ if }}
#   {{# if not a.b }} … {{/ if }}
#   {{# for item in a.list }} … {{/ for }}
#                                  中では loop.index（0から）、loop.number（1から）、loop.first、loop.last が使える
#   {{> name }}                    部品（templates/name.html）を読み込む
#   {{! コメント }}                 何も出さない
#
# ブロックの印（#, /, >, !）だけの行は、行ごと出力から除く
# テンプレートは構文木にしてから、それをたどって出力する（Perlのコードには変換しない）
use strict;
use warnings;
use utf8;

use File::Spec;
use Lyndbaum::HTML qw(escape_html);

my $MAX_INCLUDE_DEPTH = 20;

sub new {
	my ($class, %args) = @_;
	return bless {
		dir   => $args{dir},
		cache => {},
	}, $class;
}

# テンプレートファイル（name.html）を出力する
sub render {
	my ($self, $name, $vars) = @_;
	return $self->_render_nodes($self->_load($name), [ $vars // {} ], 0);
}

# 文字列のテンプレートを出力する（テスト用）
sub render_string {
	my ($self, $source, $vars) = @_;
	return $self->_render_nodes($self->parse($source, '(文字列)'), [ $vars // {} ], 0);
}

sub _load {
	my ($self, $name) = @_;
	die "テンプレート名が不正です: $name\n" if $name !~ m{\A[\w\-]+(?:/[\w\-]+)*\z};
	return $self->{cache}{$name} //= do {
		my $file = File::Spec->catfile($self->{dir}, "$name.html");
		open my $fh, '<:encoding(UTF-8)', $file or die "テンプレートを開けません: $file: $!\n";
		my $source = do { local $/; <$fh> };
		close $fh;
		$self->parse($source, "$name.html");
	};
}

#----------------------------------------------------------------------
# 構文解析
#   ノードは次の形の配列
#     [text => 文字列]
#     [var => 式, raw か]
#     [if => 式, then のノード列, else のノード列]
#     [for => 変数名, 式, 本体のノード列]
#     [include => 名前]
#   式は [否定か, 名前の列]
#----------------------------------------------------------------------

sub parse {
	my ($self, $source, $name) = @_;
	my $root = [];
	my @stack = ({ type => 'root', nodes => $root });
	my $line = 1;
	my $at_line_start = 1;
	my $fail = sub { die "テンプレート $name の $line 行目: $_[0]\n" };

	my $add = sub { push @{ $stack[-1]{in_else} ? $stack[-1]{else} : $stack[-1]{nodes} }, $_[0] };

	pos($source) = 0;
	while ($source =~ /\G(.*?)\{\{(.*?)\}\}/gcs) {
		my ($text, $inner) = ($1, $2);
		# $line は誤りを知らせるときに使うので、タグのある行にしておく
		$line += ($text =~ tr/\n//);
		my $next_line = $line + ($inner =~ tr/\n//);
		my $is_block = $inner =~ /\A\s*[#\/>!]/;

		# ブロックの印だけの行は、前の字下げと後ろの改行ごと除く
		if ($is_block
			&& ($text =~ /\n[ \t]*\z/ || ($at_line_start && $text =~ /\A[ \t]*\z/))
			&& $source =~ /\G[ \t]*(?:\n|\z)/gc
		) {
			$text =~ s/[ \t]*\z//;
			$at_line_start = 1;
			$next_line++;
		} else {
			$at_line_start = 0;
		}
		$add->([ text => $text ]) if $text ne '';

		local $_ = $inner;
		if (/\A\s*!/s) {
			# コメント
		} elsif (/\A\s*#\s*if\s+(.+?)\s*\z/s) {
			my $node = [ if => _parse_expr($1, $fail), [], [] ];
			$add->($node);
			push @stack, { type => 'if', nodes => $node->[2], else => $node->[3], line => $line };
		} elsif (/\A\s*#\s*else\s*\z/s) {
			$fail->('対応する if のない else があります') if $stack[-1]{type} ne 'if' || $stack[-1]{in_else};
			$stack[-1]{in_else} = 1;
		} elsif (/\A\s*#\s*for\s+(\w+)\s+in\s+(.+?)\s*\z/s) {
			my $node = [ for => $1, _parse_expr($2, $fail), [] ];
			$fail->("for の変数名に loop は使えません") if $1 eq 'loop';
			$add->($node);
			push @stack, { type => 'for', nodes => $node->[3], line => $line };
		} elsif (/\A\s*\/\s*(\w+)\s*\z/s) {
			my $type = $1;
			$fail->("対応する開始のない {{/ $type }} があります") if $stack[-1]{type} ne $type;
			pop @stack;
		} elsif (/\A\s*>\s*([\w\-\/]+)\s*\z/s) {
			$add->([ include => $1 ]);
		} elsif (/\A\s*raw\s+(.+?)\s*\z/s) {
			$add->([ var => _parse_expr($1, $fail), 1 ]);
		} elsif (/\A\s*#/s) {
			$fail->("知らないブロックです: {{$inner}}");
		} else {
			$add->([ var => _parse_expr($_, $fail), 0 ]);
		}
		$line = $next_line;
	}
	my $rest = substr($source, pos($source) // 0);
	$fail->('閉じていない {{ があります') if $rest =~ /\{\{/;
	$add->([ text => $rest ]) if $rest ne '';

	if (@stack > 1) {
		$line = $stack[-1]{line};
		$fail->("{{# $stack[-1]{type} }} が閉じていません");
	}
	return $root;
}

sub _parse_expr {
	my ($expr, $fail) = @_;
	$expr =~ s/\A\s+|\s+\z//g;
	my $negate = $expr =~ s/\Anot\s+//;
	$fail->("式が不正です: $expr") if $expr !~ /\A\w+(?:\.\w+)*\z/;
	return [ $negate ? 1 : 0, [ split /\./, $expr ] ];
}

#----------------------------------------------------------------------
# 出力
#----------------------------------------------------------------------

sub _render_nodes {
	my ($self, $nodes, $scopes, $depth) = @_;
	my $out = '';
	for my $node (@$nodes) {
		my $type = $node->[0];
		if ($type eq 'text') {
			$out .= $node->[1];
		} elsif ($type eq 'var') {
			my $value = _eval_expr($node->[1], $scopes);
			$value = '' if !defined $value;
			$out .= $node->[2] ? $value : escape_html($value);
		} elsif ($type eq 'if') {
			my $branch = _truthy(_eval_expr($node->[1], $scopes)) ? $node->[2] : $node->[3];
			$out .= $self->_render_nodes($branch, $scopes, $depth);
		} elsif ($type eq 'for') {
			my (undef, $var, $expr, $body) = @$node;
			my $list = _eval_expr($expr, $scopes);
			next if !$list;
			die "for に配列でない値が渡されました\n" if ref $list ne 'ARRAY';
			my $last = $#$list;
			for my $i (0 .. $last) {
				my $loop = { index => $i, number => $i + 1, first => $i == 0, last => $i == $last };
				$out .= $self->_render_nodes($body, [ @$scopes, { $var => $list->[$i], loop => $loop } ], $depth);
			}
		} elsif ($type eq 'include') {
			die "部品の読み込みが深すぎます（循環していませんか）: $node->[1]\n" if $depth >= $MAX_INCLUDE_DEPTH;
			$out .= $self->_render_nodes($self->_load($node->[1]), $scopes, $depth + 1);
		}
	}
	return $out;
}

# 名前の先頭は、内側のスコープから順に探す
sub _eval_expr {
	my ($expr, $scopes) = @_;
	my ($negate, $path) = @$expr;
	my ($head, @rest) = @$path;

	my $value;
	for my $scope (reverse @$scopes) {
		if (exists $scope->{$head}) {
			$value = $scope->{$head};
			last;
		}
	}
	for my $key (@rest) {
		last if !defined $value;
		if (ref $value eq 'HASH') {
			$value = $value->{$key};
		} elsif (ref $value eq 'ARRAY' && $key =~ /\A\d+\z/) {
			$value = $value->[$key];
		} else {
			$value = undef;
		}
	}
	return $negate ? !_truthy($value) : $value;
}

# 空の配列も偽とする
sub _truthy {
	my ($value) = @_;
	return ref $value eq 'ARRAY' ? scalar @$value : !!$value;
}

1;
