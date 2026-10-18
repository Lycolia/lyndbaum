# 参照元（Lyndbaum::Backlinks）
use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Backlinks;
use Lyndbaum::Model::Article;
use Lyndbaum::Parser;
use TestUtil qw(new_test_app);

my $app = new_test_app();
my $dbh = $app->db;
my %context = $app->parser_context;

# 記事を保存して、POST の終わりと同じく参照元を作り直す。戻り値は保存した記事の ID
sub save {
	my (%v) = @_;
	my $id = delete $v{id};
	my $result = Lyndbaum::Model::Article->save($dbh, {
		title => '題名', body_src => '', status => 'published', comments_open => 1, tags => [], %v,
	}, (defined $id ? (id => $id) : ()), context => \%context);
	die join "\n", @{ $result->{errors} } if $result->{errors};
	Lyndbaum::Backlinks->rebuild($app);
	return $result->{id};
}
sub stored { scalar $dbh->selectrow_array('SELECT backlinks_html FROM articles WHERE id = ?', undef, $_[0]) }
# 参照元に出ている題名（並び順のまま）
sub titles { [ (stored($_[0]) // '') =~ m{<li><a href="[^"]*">([^<]*)</a></li>}g ] }

subtest 'パーサーが集めるリンク' => sub {
	my $links = Lyndbaum::Parser->parse('markdown', join ' ',
		'[a](0756)', '[a2](0756)', '[b](0757#見出し)', '[c](0758?x=1)', '[d](/0759)', '![e](0760)',
		'[f](管理人について/署名情報)', '[g](https://example.com/)', '`[h](0761)`', '[i](#fn)', '[j](./0762)')->{links};
	is_deeply $links, ['0756', '管理人について/署名情報'],
		'[文字](slug) の形だけ。# や ? の付いたもの、/ で始まるもの、画像、コードの中は数えない。重複は1つ';
};

my $target = save(title => 'リンク先');
my $slug   = "0$target";

subtest '参照元に出すもの' => sub {
	is stored($target), '', '参照元が無ければ空';
	my $old   = save(title => '古い記事', body_src => "[1]($slug) と [2]($slug)", published_at => 1000);
	my $new   = save(title => '<新しい記事>', body_src => "[x]($slug)", published_at => 2000);
	my $draft = save(title => '下書き', body_src => "[x]($slug)", status => 'draft');
	save(id => $target, title => 'リンク先', body_src => "[自分]($slug) [無い記事](09999)");
	is_deeply titles($target), ['&lt;新しい記事&gt;', '古い記事'],
		'公開中の記事だけ、新しい順に1回ずつ。題名はエスケープする。自分自身と下書きは出さない';
	like stored($target), qr{<h2 class="backlinks-title">参照元</h2>};
	like stored($target), qr{<a href="/0$old">}, '記事のURLへリンクする';

	save(id => $draft, title => '公開した', body_src => "[x]($slug)", status => 'published', published_at => 3000);
	is_deeply titles($target), ['公開した', '&lt;新しい記事&gt;', '古い記事'], '下書きを公開したら出る';

	save(id => $new, title => '新しい記事', body_src => "[x]($slug#見出し)", published_at => 2000);
	is_deeply titles($target), ['公開した', '古い記事'], 'リンクを消したら出ない（# の付いたリンクは数えない）';

	save(id => $old, title => '古い記事（改題）', body_src => "[1]($slug)", published_at => 1000);
	is_deeply titles($target), ['公開した', '古い記事（改題）'], 'リンク元の題名を変えたら作り直す';

	Lyndbaum::Model::Article->move_to_trash($dbh, [$draft]);
	Lyndbaum::Backlinks->rebuild($app);
	is_deeply titles($target), ['古い記事（改題）'], 'ゴミ箱に入れたら出ない';
	Lyndbaum::Model::Article->restore($dbh, [$draft]);
	Lyndbaum::Backlinks->rebuild($app);
	is_deeply titles($target), ['公開した', '古い記事（改題）'], '戻したら出る';
	Lyndbaum::Model::Article->move_to_trash($dbh, [$draft]);
	Lyndbaum::Model::Article->purge($dbh, [$draft]);
	Lyndbaum::Backlinks->rebuild($app);
	is_deeply titles($target), ['古い記事（改題）'], '完全に削除したら出ない';
	is $dbh->selectrow_array('SELECT COUNT(*) FROM article_links WHERE source_id = ?', undef, $draft), 0, 'リンクも消える';
};

subtest 'コンテンツページ' => sub {
	my $source = save(title => 'ページへのリンク', body_src => '[about](about) [新しい名前](profile)');
	my $page = save(title => '自己紹介', kind => 'page', page_name => 'about');
	is_deeply titles($page), ['ページへのリンク'], '先にリンクがあれば、後で作ったページにも出る';
	save(id => $page, title => '自己紹介', page_name => 'profile');
	is_deeply titles($page), ['ページへのリンク'], 'ページの名前を変えたら、新しい slug へのリンクで作り直す';
	save(id => $source, title => 'ページへのリンク', body_src => '[about](about)');
	is_deeply titles($page), [], '新しい slug へのリンクが無くなったら出ない';
};

subtest '作り直し' => sub {
	my $before = stored($target);
	$dbh->do('UPDATE articles SET backlinks_html = ? WHERE id = ?', undef, '古いHTML', $target);
	is(Lyndbaum::Backlinks->rebuild($app), 0, '印の無い記事は作り直さない');
	is stored($target), '古いHTML';
	Lyndbaum::Backlinks->rebuild($app, all => 1);
	is stored($target), $before, '再構築では全記事の分を作り直す（テンプレートを変えたときのため）';

	$dbh->do('UPDATE articles SET backlinks_html = NULL WHERE id = ?', undef, $target);
	is(Lyndbaum::Backlinks->html($app, { id => $target, slug => $slug }), $before, '作っていなければ、表示のときに作る');
	is stored($target), $before, '作ったものは保存する';

	{
		no warnings 'redefine';
		local *Lyndbaum::Template::render = sub { die '描画した' };
		is(Lyndbaum::Backlinks->html($app, { id => $target, slug => $slug }), $before, '表示のときは保存したものを読むだけ');
	}
};

subtest '記事のページ' => sub {
	my $res = $app->handle({ REQUEST_METHOD => 'GET', PATH_INFO => "/$slug" });
	is $res->status, 200;
	like $res->body, qr{</div>\s*<section class="backlinks">.*?参照元.*?</section>}s, '本文の後に出す';
	my $other = save(title => '参照元の無い記事');
	$res = $app->handle({ REQUEST_METHOD => 'GET', PATH_INFO => "/0$other" });
	unlike $res->body, qr{class="backlinks"}, '参照元が無ければ出さない';
};

done_testing;
