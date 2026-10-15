use strict;
use warnings;
use utf8;
use Test::More;

use Lyndbaum::Router;
use TestUtil ();

my $router = Lyndbaum::Router->new(
	[ GET  => qr{\A/\z},      'C::Top',     'index' ],
	[ GET  => qr{\A/(\d+)\z}, 'C::Article', 'show'  ],
	[ POST => qr{\A/(\d+)\z}, 'C::Article', 'save'  ],
);

subtest '捕捉グループのない経路' => sub {
	is_deeply [ $router->match('GET', '/') ], [ 'C::Top', 'index' ];
};

subtest '捕捉した値を引数として返す' => sub {
	is_deeply [ $router->match('GET', '/0123') ], [ 'C::Article', 'show', '0123' ];
};

subtest 'メソッドで振り分ける' => sub {
	is_deeply [ $router->match('POST', '/5') ], [ 'C::Article', 'save', '5' ];
};

subtest 'HEAD は GET と同じ扱い' => sub {
	is_deeply [ $router->match('HEAD', '/') ], [ 'C::Top', 'index' ];
};

subtest '一致しなければ空リスト' => sub {
	is_deeply [ $router->match('GET', '/abc') ], [];
	is_deeply [ $router->match('DELETE', '/1') ], [];
};

done_testing;
