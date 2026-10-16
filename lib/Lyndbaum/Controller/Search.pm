package Lyndbaum::Controller::Search;
# 検索（文字列、タグ、年月での絞り込み）
#   /search?q=語&in=範囲&t=親::子&t=…&d=YYYYMM&page=N
#     q    検索語。空白（全角を含む）で区切ると、すべてを含む記事を探す
#     in   範囲。title（タイトル）、source（原文。URLや記法を含む）。省くと本文
#     t    タグ（親を含めた名前を :: でつなぐ）。複数指定するとすべてが付いた記事。空ならタグの無い記事
#     d    年（YYYY）か年月（YYYYMM）。日本時間
# 結果には、タグと年月の絞り込みの候補を件数つきで出す
# 検索語があれば、題名と当たった箇所を強調する。当たった箇所は、本文なら前後の抜粋、原文なら当たった行（行番号つき）
use strict;
use warnings;
use utf8;
use feature 'current_sub';

use Lyndbaum::Controller qw(page_number);
use Lyndbaum::Highlight;
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Search;
use Lyndbaum::Model::Tag;
use Lyndbaum::Parser::Common;
use Lyndbaum::View;

my %SCOPES = (text => '本文', title => 'タイトル', source => '原文');

# 検索語の数の上限。多すぎるとSQLの条件が長くなるため
my $MAX_WORDS = 10;

sub index {
	my ($class, $app, $req) = @_;
	my $cond = $class->_conditions($app, $req) or return $app->not_found;

	my $form = $class->form($cond->{q}, $cond->{in});
	if (!@{ $cond->{words} } && !@{ $cond->{tags} } && !$cond->{untagged} && !$cond->{d}) {
		return $app->render('search', { title => '検索', form => $form }, req => $req);
	}

	my $search = Lyndbaum::Model::Search->new($app->db,
		words    => $cond->{words},
		scope    => $cond->{in},
		tag_ids  => [ map { $_->{id} } @{ $cond->{tags} } ],
		untagged => $cond->{untagged},
		($cond->{d} ? (from => $cond->{from}, to => $cond->{to}) : ()),
	);

	my $per_page = $app->settings->{per_page};
	my $pager = Lyndbaum::View->pager(
		page     => page_number($req),
		per_page => $per_page,
		total    => $search->count,
		url_of   => sub { $class->_url($app, $cond, page => $_[0]) },
	) or return $app->not_found;
	my $articles = $search->list(limit => $per_page, offset => ($pager->{page} - 1) * $per_page);

	# 題名は、検索語があれば検索語、無ければ絞り込みの条件（タグの一覧として使うとき）
	my $selected = $class->_selected($app, $cond);
	return $app->render('search', {
		title      => @{ $cond->{words} } ? "「$cond->{q}」の検索結果" : join(' / ', map { $_->{label} } @$selected),
		form       => $form,
		selected   => $selected,
		tag_facet  => $class->_tag_facet($app, $cond, $search),
		date_facet => $class->_date_facet($app, $cond, $search),
		articles   => $class->_results($app, $cond, $articles),
		pager      => $pager,
	}, req => $req);
}

# 検索フォーム（templates/search_form.html）に渡す値
sub form {
	my ($class, $q, $in) = @_;
	return {
		q      => $q // '',
		scopes => [ map { +{ value => $_, label => $SCOPES{$_}, selected => $_ eq ($in // 'text') } } qw(text title source) ],
	};
}

# 検索結果の記事。検索語があれば、題名を強調し、当たった箇所を添える
#   範囲が本文なら前後の文章の抜粋、原文なら当たった行（行番号つき）
sub _results {
	my ($class, $app, $cond, $articles) = @_;
	my $views = Lyndbaum::View->articles($app, $articles);
	my $words = $cond->{words};
	return $views if !@$words;
	for my $i (0 .. $#$articles) {
		my ($article, $view) = ($articles->[$i], $views->[$i]);
		$view->{title_html} = Lyndbaum::Highlight->mark($article->{title}, $words);
		if ($cond->{in} eq 'text') {
			$view->{snippets} = Lyndbaum::Highlight->snippets(
				Lyndbaum::Parser::Common::plain_text($article->{body_html} // ''), $words);
		} elsif ($cond->{in} eq 'source') {
			my ($lines, $omitted) = Lyndbaum::Highlight->lines($article->{body_src}, $words);
			$view->{source_lines}   = $lines;
			$view->{omitted_lines}  = $omitted;
		}
	}
	return $views;
}

# クエリから検索の条件を読む。存在しないタグを指定したら undef（404にする）
sub _conditions {
	my ($class, $app, $req) = @_;
	my $q = $req->param('q') // '';
	my %seen;
	my @words = grep { $_ ne '' && !$seen{$_}++ }
		split /\s+/, Lyndbaum::Parser::Common::normalize_for_search($q);
	splice @words, $MAX_WORDS if @words > $MAX_WORDS;

	my $in = $req->param('in') // '';
	$in = 'text' if !$SCOPES{$in};

	my (@tags, $untagged, %tag_seen);
	for my $name ($req->params('t')) {
		if ($name eq '') {
			$untagged = 1;
			next;
		}
		my $tag = Lyndbaum::Model::Tag->find_by_path($app->tags, split /::/, $name) or return undef;
		push @tags, $tag if !$tag_seen{ $tag->{id} }++;
	}

	# 年（YYYY）か年月（YYYYMM）。それ以外は無視する（旧システムと同じ）
	my (%date, $d);
	if (($req->param('d') // '') =~ /\A(\d{4})(0[1-9]|1[0-2])?\z/) {
		$d = $1 . ($2 // '');
		%date = (year => 0 + $1, month => defined $2 ? 0 + $2 : undef);
		@date{qw(from to)} = Lyndbaum::Model::Search->date_range($date{year}, $date{month});
	}

	return {
		q        => $q,
		words    => \@words,
		in       => $in,
		tags     => \@tags,
		untagged => $untagged,
		d        => $d,
		%date,
	};
}

# 今の条件に変更を加えた検索のURL
#   %change は q、in、tags（タグの配列）、untagged、d、page
sub _url {
	my ($class, $app, $cond, %change) = @_;
	my %c = (%$cond, %change);
	return $app->url->search(
		q    => $c{q},
		in   => $c{in},
		t    => [ (map { $_->{path} } @{ $c{tags} }), ($c{untagged} ? [] : ()) ],
		d    => $c{d},
		page => $c{page},
	);
}

# 選んでいる条件と、それを外すリンク
sub _selected {
	my ($class, $app, $cond) = @_;
	my @selected;
	for my $tag (@{ $cond->{tags} }) {
		push @selected, {
			label      => $tag->{full_name},
			remove_url => $class->_url($app, $cond, tags => [ grep { $_->{id} != $tag->{id} } @{ $cond->{tags} } ]),
		};
	}
	push @selected, { label => '(タグなし)', remove_url => $class->_url($app, $cond, untagged => 0) } if $cond->{untagged};
	if ($cond->{d}) {
		push @selected, {
			label      => defined $cond->{month} ? "$cond->{year}年$cond->{month}月" : "$cond->{year}年",
			remove_url => $class->_url($app, $cond, d => undef),
		};
	}
	return \@selected;
}

# タグの絞り込みの候補。選んだタグとその祖先は除く。並びはサイドバーのタグの木と同じ
sub _tag_facet {
	my ($class, $app, $cond, $search) = @_;
	my $counts = $search->tag_counts;
	my %exclude;
	for my $tag (@{ $cond->{tags} }) {
		for (my $t = $tag; $t; $t = defined $t->{parent_id} ? $app->tags->{ $t->{parent_id} } : undef) {
			$exclude{ $t->{id} } = 1;
		}
	}

	my @facet;
	my $walk = sub {
		my ($nodes) = @_;
		for my $node (@$nodes) {
			my $count = $counts->{ $node->{id} };
			push @facet, {
				label => $node->{full_name},
				count => $count,
				url   => $class->_url($app, $cond, tags => [ @{ $cond->{tags} }, $node ], page => undef),
			} if $count && !$exclude{ $node->{id} };
			__SUB__->($node->{children});
		}
	};
	$walk->(Lyndbaum::Model::Tag->public_tree($app->db, $app->tags));

	if (!$cond->{untagged} && (my $untagged = $search->untagged_count)) {
		push @facet, { label => '(タグなし)', count => $untagged, url => $class->_url($app, $cond, untagged => 1, page => undef) };
	}
	return \@facet;
}

# 年月の絞り込みの候補。年を選ぶ前は年ごと、年を選んだら月ごと、月を選んだら出さない
sub _date_facet {
	my ($class, $app, $cond, $search) = @_;
	return [] if defined $cond->{month};
	if (!$cond->{d}) {
		return [ map {
			+{ label => "$_->[0]年", count => $_->[1], url => $class->_url($app, $cond, d => $_->[0], page => undef) }
		} @{ $search->date_counts('year') } ];
	}
	return [ map {
		+{ label => "$_->[0]月", count => $_->[1], url => $class->_url($app, $cond, d => sprintf('%04d%02d', $cond->{year}, $_->[0]), page => undef) }
	} @{ $search->date_counts('month') } ];
}

1;
