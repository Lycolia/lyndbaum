package Lyndbaum::SearchForm;
# サイドバーと検索ページで共用する検索フォーム。検索処理には依存しない
use strict;
use warnings;
use utf8;

my %SCOPES = (text => '本文', title => 'タイトル', source => '原文');

sub scope {
	my ($class, $in) = @_;
	return defined $in && exists $SCOPES{$in} ? $in : 'text';
}

# templates/search_form.html に渡す値
sub values {
	my ($class, $q, $in) = @_;
	return {
		q      => $q // '',
		scopes => [ map { +{ value => $_, label => $SCOPES{$_}, selected => $_ eq ($in // 'text') } } qw(text title source) ],
	};
}

1;
