# サイトのアイコン（Lyndbaum::SiteIcon、/admin/settings/icon）
use strict;
use warnings;
use utf8;
use Test::More;

use Encode qw(encode_utf8);
use File::Spec;
use Lyndbaum::SiteIcon;
use AdminTest;
use TestUtil qw(root_dir);

plan skip_all => 'GD がありません' if !eval { require GD; 1 };
# 読めない画像の記録（warn と GD の警告）は、テストの出力に混ぜない
local $SIG{__WARN__} = sub { warn @_ if $_[0] !~ /サイトのアイコンを作れませんでした/ };

# 横長の画像。左右の端は赤、真ん中の正方形は青（切り抜いたら青だけが残る）。$alpha なら真ん中を半分透かす
sub wide_image {
	my ($format, $alpha) = @_;
	my $image = GD::Image->new(300, 200, 1);
	$image->alphaBlending(0);
	$image->saveAlpha(1);
	$image->filledRectangle(0, 0, 299, 199, $image->colorAllocate(255, 0, 0));
	$image->filledRectangle(50, 0, 249, 199, $alpha ? $image->colorAllocateAlpha(0, 0, 255, 64) : $image->colorAllocate(0, 0, 255));
	return $format eq 'jpeg' ? $image->jpeg(90) : $image->$format;
}

sub size_of { my ($png) = @_; return [ unpack 'NN', substr($png, 16, 8) ] }
sub read_file { my ($file) = @_; open my $fh, '<:raw', $file or die "$file: $!"; local $/; return <$fh> }

subtest 'ICO' => sub {
	my %files = %{ Lyndbaum::SiteIcon->make(wide_image('png'), 'png') };
	my ($reserved, $type, $count) = unpack 'vvv', $files{'favicon.ico'};
	is_deeply [ $reserved, $type, $count ], [ 0, 1, 2 ], 'アイコンが2つ入った ICO';
	my @entries = map { [ unpack 'CCCCvvVV', substr($files{'favicon.ico'}, 6 + 16 * $_, 16) ] } 0, 1;
	is_deeply [ map { [ @$_[0, 1] ] } @entries ], [ [ 16, 16 ], [ 32, 32 ] ], '16 と 32';
	my ($len, $offset) = @{ $entries[1] }[6, 7];
	is substr($files{'favicon.ico'}, $offset, 8), "\x89PNG\r\n\x1A\n", '中身は PNG';
	is_deeply size_of(substr $files{'favicon.ico'}, $offset, $len), [ 32, 32 ];
	is_deeply { map { $_ => size_of($files{$_}) } grep { /\.png\z/ } keys %files },
		{ 'icon-32.png' => [ 32, 32 ], 'icon-192.png' => [ 192, 192 ], 'apple-touch-icon.png' => [ 180, 180 ] }, '大きさ';

	my $icon = GD::Image->newFromPngData($files{'icon-192.png'}, 1);
	is_deeply [ $icon->rgb($icon->getPixel(2, 96)) ], [ 0, 0, 255 ], '真ん中を正方形に切り抜く（端の赤は入らない）';

	my $default = read_file(File::Spec->catfile(root_dir(), qw(pub assets logo favicon.ico)));
	is_deeply [ unpack 'vvv', $default ], [ 0, 1, 2 ], '既定のロゴの favicon.ico もある';
};

subtest '透明なところ' => sub {
	my %files = %{ Lyndbaum::SiteIcon->make(wide_image('png', 1), 'png') };
	my $icon = GD::Image->newFromPngData($files{'icon-32.png'}, 1);
	ok $icon->alpha($icon->getPixel(16, 16)) > 0, 'icon は透明なところを残す';
	my $apple = GD::Image->newFromPngData($files{'apple-touch-icon.png'}, 1);
	is $apple->alpha($apple->getPixel(90, 90)), 0, 'apple-touch-icon は白に重ねて透かさない';
};

subtest '設定の画面' => sub {
	my $t = AdminTest->new;
	my ($cookie) = $t->login;
	my $csrf = $t->csrf_of($cookie);
	my $dir = Lyndbaum::SiteIcon->dir($t->app);
	my $B = 'BOUNDARY';
	my $post = sub {
		my (%form) = @_;
		my $body = '';
		for my $name (sort keys %form) {
			my ($value, $filename) = ref $form{$name} ? @{ $form{$name} } : ($form{$name});
			$body .= encode_utf8("--$B\r\nContent-Disposition: form-data; name=\"$name\""
				. (defined $filename ? "; filename=\"$filename\"" : '') . "\r\n\r\n") . $value . "\r\n";
		}
		return $t->request(POST => '/admin/settings/icon', cookie => $cookie, raw_body => "$body--$B--\r\n",
			content_type => "multipart/form-data; boundary=$B");
	};
	my $get = sub { $t->request(GET => $_[0], cookie => $cookie)->body };

	my $body = $get->('/admin/settings/blog');
	like $body, qr{<form class="admin-form site-icon-form" method="post" action="/admin/settings/icon" enctype="multipart/form-data">};
	like $body, qr{<img src="/pub/assets/logo/logo-192\.png" width="64" height="64" alt="今のアイコン"> 既定のロゴ};
	unlike $body, qr{value="delete"}, '既定のロゴなら、消すボタンは出さない';
	like $get->('/'), qr{<link rel="icon" href="/pub/assets/logo/logo-32\.png" sizes="32x32">}, '公開側は既定のロゴ';
	like $body, qr{<link rel="apple-touch-icon" href="/pub/assets/logo/logo-180\.png">}, '管理画面も';

	my $res = $post->(csrf_token => $csrf, op => 'upload', file => [ wide_image('jpeg'), '写真.JPG' ]);
	is $res->status, 303, 'JPEG を入れる';
	like AdminTest::header($res, 'Location'), qr{\A/admin/settings/blog\?icon=saved\z};
	ok -f File::Spec->catfile($dir, $_), "$_ を書き出す" for qw(icon-32.png icon-192.png apple-touch-icon.png favicon.ico);
	is substr(read_file(File::Spec->catfile($dir, 'icon-32.png')), 0, 8), "\x89PNG\r\n\x1A\n", 'PNG にする';
	my $version = $t->app->db->selectrow_array(q{SELECT value FROM settings WHERE key = 'site_icon'});
	like $version, qr/\A\d+\z/, '書き出した時刻を設定に入れる';

	$body = $get->('/admin/settings/blog?icon=saved');
	like $body, qr{アイコンを入れ替えました。};
	like $body, qr{<img src="/pub/site-icon/icon-192\.png\?v=$version" width="64" height="64" alt="今のアイコン"> 入れたアイコン};
	like $body, qr{<button type="submit" name="op" value="delete" class="button">消して既定のロゴに戻す</button>};
	like $get->('/'), qr{<link rel="icon" href="/pub/site-icon/icon-32\.png\?v=$version" sizes="32x32">},
		'URLに時刻を付ける（入れ替えたときに、ブラウザに古いアイコンを使わせない）';

	for my $format (qw(webp gif)) {
		is $post->(csrf_token => $csrf, op => 'upload', file => [ wide_image($format), "a.$format" ])->status, 303, "$format も入れられる";
		my $icon = GD::Image->newFromPngData(read_file(File::Spec->catfile($dir, 'icon-192.png')), 1);
		is_deeply [ $icon->rgb($icon->getPixel(2, 96)) ], [ 0, 0, 255 ], "$format から PNG を作る";
	}
	$res = $post->(csrf_token => $csrf, op => 'upload', file => [ "\0\0\0\x18ftypmp42", 'a.mp4' ]);
	is $res->status, 400, '画像でないものは受け付けない';
	like $res->body, qr{アイコンを入れ替えられませんでした。「a\.mp4」は置けない種類のファイルです（置けるのは png、jpg、jpeg、webp、gif）。};
	$res = $post->(csrf_token => $csrf, op => 'upload', file => [ 'not png', 'a.png' ]);
	like $res->body, qr{「a\.png」は、拡張子と中身の種類が合いません。}, '中身も確かめる';
	$res = $post->(csrf_token => $csrf, op => 'upload', file => [ "\x89PNG\r\n\x1A\nbroken", 'a.png' ]);
	is $res->status, 400, '画像として読めない';
	like $res->body, qr{「a\.png」を画像として読めませんでした。};
	like $post->(csrf_token => $csrf, op => 'upload')->body, qr{画像を選んでください。};
	is $post->(csrf_token => 'wrong', op => 'delete')->status, 403, 'CSRFトークンが違う';
	ok -f File::Spec->catfile($dir, 'favicon.ico'), '失敗しても今のアイコンはそのまま';

	$res = $post->(csrf_token => $csrf, op => 'delete');
	is $res->status, 303, '消す';
	like AdminTest::header($res, 'Location'), qr{\?icon=deleted\z};
	ok !-e File::Spec->catfile($dir, $_), "$_ を消す" for qw(icon-32.png icon-192.png apple-touch-icon.png favicon.ico);
	like $get->('/admin/settings/blog?icon=deleted'), qr{アイコンを消して、既定のロゴに戻しました。};
	like $get->('/'), qr{<link rel="icon" href="/pub/assets/logo/logo-32\.png" sizes="32x32">}, '既定のロゴに戻る';
};

done_testing;
