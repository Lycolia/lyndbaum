use strict;
use warnings;
use utf8;
use Test::More;

use File::Spec;
use File::Temp qw(tempdir);

use Lyndbaum::DB;
use TestUtil qw(root_dir insert_article);

my $migrations = File::Spec->catdir(root_dir(), 'db', 'migrations');

sub new_dbh {
	return Lyndbaum::DB->connect(File::Spec->catfile(tempdir(CLEANUP => 1), 'test.db'));
}

subtest '接続ごとに外部キーの制約が有効' => sub {
	my $dbh = new_dbh();
	is $dbh->selectrow_array('PRAGMA foreign_keys'), 1;
};

subtest 'マイグレーションを流すと user_version が上がる' => sub {
	my $dbh = new_dbh();
	is $dbh->selectrow_array('PRAGMA user_version'), 0;

	my @applied = Lyndbaum::DB->migrate($dbh, $migrations);
	my @files = glob File::Spec->catfile($migrations, '*.sql');
	is_deeply \@applied, [ 1 .. @files ], 'すべてのマイグレーションを番号順に流す';
	is $dbh->selectrow_array('PRAGMA user_version'), scalar @files;

	my @tables = sort @{ $dbh->selectcol_arrayref(
		q{SELECT name FROM sqlite_master WHERE type = 'table'}
	) };
	is_deeply \@tables, [ sort qw(
		articles article_search tags tag_paths article_tags comments
		revisions url_cache settings admin sessions login_failures sequences
	) ];
};

subtest '2回目は何もしない' => sub {
	my $dbh = new_dbh();
	Lyndbaum::DB->migrate($dbh, $migrations);
	is_deeply [ Lyndbaum::DB->migrate($dbh, $migrations) ], [];
};

subtest '失敗したマイグレーションは巻き戻す' => sub {
	my $dir = tempdir(CLEANUP => 1);
	open my $fh, '>', File::Spec->catfile($dir, '0001_broken.sql') or die $!;
	print $fh "CREATE TABLE ok_table (id INTEGER);\nTHIS IS NOT SQL;\n";
	close $fh;

	my $dbh = new_dbh();
	eval { Lyndbaum::DB->migrate($dbh, $dir) };
	like $@, qr/0001_broken\.sql/;
	is $dbh->selectrow_array('PRAGMA user_version'), 0;
	is $dbh->selectrow_array(q{SELECT COUNT(*) FROM sqlite_master WHERE name = 'ok_table'}), 0;
};

subtest '日本語を文字列として読み書きできる' => sub {
	my $dbh = new_dbh();
	Lyndbaum::DB->migrate($dbh, $migrations);
	my $id = insert_article($dbh, title => '日本語のタイトル');
	my $title = $dbh->selectrow_array('SELECT title FROM articles WHERE id = ?', undef, $id);
	is $title, '日本語のタイトル';
	ok utf8::is_utf8($title), '文字列として返る';
};

done_testing;
