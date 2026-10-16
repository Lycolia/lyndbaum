package Lyndbaum::Model::Admin;
# 管理者（単一ユーザーなので1行だけ）と、ログインの失敗の制限
use strict;
use warnings;
use utf8;

use Lyndbaum::Password;

# ログインの失敗の制限：$WINDOW秒の間に$MAX_FAILURES回失敗したら、そのIPからは受け付けない
#   最後の失敗から$WINDOW秒たてば、また受け付ける
our $MAX_FAILURES = 5;
our $WINDOW       = 15 * 60;

sub find {
	my ($class, $dbh) = @_;
	return $dbh->selectrow_hashref('SELECT id, login, password_hash, updated_at FROM admin WHERE id = 1');
}

# 管理者を登録する（すでにいれば、ログイン名とパスワードを置き換える）
#   今のセッションはすべて消す（盗まれたセッションが、パスワードを変えた後も使えないように）
#   %optはLyndbaum::Password->hashに渡す
sub set_password {
	my ($class, $dbh, $login, $password, %opt) = @_;
	if (my $error = Lyndbaum::Password->format_error($password)) {
		die "$error\n";
	}
	my $hash = Lyndbaum::Password->hash($password, %opt);
	$dbh->begin_work;
	eval {
		$dbh->do('INSERT OR REPLACE INTO admin (id, login, password_hash, updated_at) VALUES (1, ?, ?, ?)', undef, $login, $hash, time);
		$dbh->do('DELETE FROM sessions');
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
}

# ログイン名とパスワードが合えば真
#   パスワードの決まり（Lyndbaum::Password->format_error）に合わなければ、bcrypt をかけずに偽を返す
#   （長いパスワードで重い計算をさせられないように。決まりは公開しているので、早く返しても漏れるものは無い）
sub authenticate {
	my ($class, $dbh, $login, $password) = @_;
	return 0 if Lyndbaum::Password->format_error($password);
	my $admin = $class->find($dbh);
	if (!$admin || !Lyndbaum::Password::equal($login, $admin->{login})) {
		return Lyndbaum::Password->waste_time($password);
	}
	return Lyndbaum::Password->verify($password, $admin->{password_hash});
}

# このIPからのログインを、今は受け付けないなら真
sub locked_out {
	my ($class, $dbh, $ip, $now) = @_;
	my $count = $dbh->selectrow_array('SELECT COUNT(*) FROM login_failures WHERE ip = ? AND failed_at > ?',
		undef, $ip, ($now // time) - $WINDOW);
	return $count >= $MAX_FAILURES;
}

sub record_failure {
	my ($class, $dbh, $ip, $now) = @_;
	$now //= time;
	$dbh->do('DELETE FROM login_failures WHERE failed_at <= ?', undef, $now - $WINDOW);
	$dbh->do('INSERT INTO login_failures (ip, failed_at) VALUES (?, ?)', undef, $ip, $now);
}

sub clear_failures {
	my ($class, $dbh, $ip) = @_;
	$dbh->do('DELETE FROM login_failures WHERE ip = ?', undef, $ip);
}

1;
