package TestUtil;
# テスト用の共通部品
use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(root_dir new_test_app insert_article);

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More ();

use Lyndbaum::App;
use Lyndbaum::Config;
use Lyndbaum::DB;

# テスト名に日本語を使うので、テストの出力をUTF-8にする
binmode Test::More->builder->$_, ':encoding(UTF-8)'
	for qw(output failure_output todo_output);

sub root_dir {
	return File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, File::Spec->updir));
}

# 一時ディレクトリに最新スキーマのDBを作り、それを使うアプリを返す
sub new_test_app {
	my $dir     = tempdir(CLEANUP => 1);
	my $db_path = File::Spec->catfile($dir, 'test.db');
	my $dbh     = Lyndbaum::DB->connect($db_path);
	Lyndbaum::DB->migrate($dbh, File::Spec->catdir(root_dir(), 'db', 'migrations'));
	$dbh->disconnect;

	# RSS とサイトマップとサイトのアイコンは一時ディレクトリに書き出す（リポジトリの pub/ を書き換えないように）
	return Lyndbaum::App->new(
		root   => root_dir(),
		config => Lyndbaum::Config->new(db_path => $db_path, secret_key => 'test-secret',
			feed_file => File::Spec->catfile($dir, 'rss.xml'), sitemap_file => File::Spec->catfile($dir, 'sitemap.xml'),
			site_icon_dir => File::Spec->catdir($dir, 'site-icon')),
	);
}

# 記事を1件入れる。指定しなかった列は公開中の通常の記事にする
sub insert_article {
	my ($dbh, %columns) = @_;
	my $now = time;
	my %row = (
		kind         => 'post',
		title        => '',
		body_src     => '',
		status       => 'published',
		published_at => $now,
		created_at   => $now,
		updated_at   => $now,
		%columns,
	);
	# 旧システムと同じく、slug は「0 + ID」
	$row{slug} //= '0' . ($row{id} // int(rand 1_000_000));
	my @names = sort keys %row;
	$dbh->do(
		sprintf('INSERT INTO articles (%s) VALUES (%s)', join(', ', @names), join(', ', ('?') x @names)),
		undef, @row{@names},
	);
	return $dbh->sqlite_last_insert_rowid;
}

1;
