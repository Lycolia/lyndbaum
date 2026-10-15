package Lyndbaum::DB;
# SQLiteへの接続とマイグレーション
use strict;
use warnings;
use utf8;

use DBI;
use File::Spec;

sub connect {
	my ($class, $path) = @_;
	my $dbh = DBI->connect("dbi:SQLite:dbname=$path", '', '', {
		RaiseError     => 1,
		PrintError     => 0,
		AutoCommit     => 1,
		sqlite_unicode => 1,
	});
	# SQLiteは既定で外部キーの制約を確認しないので、接続ごとに有効にする
	$dbh->do('PRAGMA foreign_keys = ON');
	$dbh->sqlite_busy_timeout(5000);
	return $dbh;
}

# db/migrations/NNNN_*.sql のうち、user_version より新しいものを番号順に流す
# 適用した版の番号のリストを返す
sub migrate {
	my ($class, $dbh, $dir) = @_;
	my $current = $dbh->selectrow_array('PRAGMA user_version');

	opendir my $dh, $dir or die "マイグレーションのディレクトリを開けません: $dir: $!\n";
	my @files = sort grep { /\A\d{4}_.*\.sql\z/ } readdir $dh;
	closedir $dh;

	my @applied;
	for my $file (@files) {
		my ($version) = $file =~ /\A(\d{4})/;
		$version += 0;
		next if $version <= $current;

		open my $fh, '<:encoding(UTF-8)', File::Spec->catfile($dir, $file)
			or die "開けません: $file: $!\n";
		my $sql = do { local $/; <$fh> };
		close $fh;

		$dbh->begin_work;
		eval {
			local $dbh->{sqlite_allow_multiple_statements} = 1;
			$dbh->do($sql);
			# ファイルの中身によらず、ファイル名の番号を版とする
			$dbh->do("PRAGMA user_version = $version");
			$dbh->commit;
			1;
		} or do {
			my $error = $@;
			$dbh->rollback;
			die "マイグレーション $file に失敗しました: $error";
		};
		push @applied, $version;
	}
	return @applied;
}

1;
