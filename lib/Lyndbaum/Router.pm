package Lyndbaum::Router;
# URLとHTTPメソッドから、処理するコントローラとアクションを決める
use strict;
use warnings;
use utf8;

# 引数は [メソッド, パスの正規表現, コントローラのクラス, アクション名] の並び
sub new {
	my ($class, @routes) = @_;
	return bless { routes => \@routes }, $class;
}

# 一致したら (クラス, アクション, 正規表現の捕捉...) を返す。一致しなければ空リスト
sub match {
	my ($self, $method, $path) = @_;
	$method = 'GET' if $method eq 'HEAD';

	for my $route (@{ $self->{routes} }) {
		my ($route_method, $pattern, $class, $action) = @$route;
		next if $route_method ne $method;
		return ($class, $action, @{^CAPTURE}) if $path =~ $pattern;
	}
	return;
}

1;
