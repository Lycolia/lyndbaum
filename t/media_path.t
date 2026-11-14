use strict;
use utf8;
#-------------------------------------------------------------------------------
# メディア管理のパスのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/media_path.t
#
# ファイル名やフォルダ名に .. や / を入れても、メディア管理のフォルダ（pub/attach/）の
# 外のファイルを変えられないことを確かめる。Image::Magickは要らない。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup()->seed();
my $dir = $app->dir;
my $img = "$dir/pub/attach";
my $file = "$AppTest::IMAGE_FOLDER$AppTest::IMAGE_FILE";	# test/a.png

sub json_ret {
	my $r = shift;
	return $r->{json} && defined $r->{json}->{ret} ? $r->{json}->{ret} : undef;
}
sub touch {
	my $f = shift;
	open(my $fh, '>', $f) || die "$f: $!";
	print $fh "x";
	close($fh);
}

#-------------------------------------------------------------------------------
# ファイル名の変更
#-------------------------------------------------------------------------------
subtest 'ファイル名の変更で、フォルダの外を指せない' => sub {
	my $r;
	$r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => 'a.png', name => '../../outside.png' });
	isnt(json_ret($r), '0', '新しい名前に ../ を入れると失敗する');
	ok(-f "$img/$file",            '元のファイルは残る');
	ok(!-e "$dir/outside.png",     'フォルダの外にファイルができない');

	touch("$dir/pub/secret.txt");
	$r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => '../../secret.txt', name => 'got.txt' });
	isnt(json_ret($r), '0', '元の名前に ../ を入れると失敗する');
	ok(-f "$dir/pub/secret.txt",   'フォルダの外のファイルは動かない');
	ok(!-e "$img/test/got.txt",    'メディア管理に持ち込めない');

	$r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => 'a.png', name => '.htaccess' });
	isnt(json_ret($r), '0', '. で始まる名前にはできない');
	ok(-f "$img/$file",            '元のファイルは残る');

	$r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => 'a.png', name => 'b.png' });
	is(json_ret($r), '0', '普通の名前には変えられる');
	$r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => 'b.png', name => 'a.png' });
	is(json_ret($r), '0', '元の名前に戻せる');
	ok(-f "$img/$file",            'ファイルが元の名前で残る');
};

subtest 'ファイル名の変更で、同じ名前のファイルを上書きしない' => sub {
	my $other = "$img/test/c.png";
	my $thumb = "$img/test/.thumbnail/c.png.jpg";
	mkdir("$img/test/.thumbnail");
	touch($other);
	touch($thumb);
	my $size = -s "$img/$file";
	isnt($size, -s $other, '2つのファイルの中身が違う');

	my $r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => 'a.png', name => 'c.png' });
	isnt(json_ret($r), '0', '同じ名前のファイルがあると失敗する');
	is(-s "$img/$file", $size,     '元のファイルは残る');
	is(-s $other, 1,               '変更先のファイルの中身は変わらない');
	ok(-e $thumb,                  '変更先のサムネイルは残る');

	unlink($other, $thumb);
};

subtest 'ファイル名の変更に失敗したら、サムネイルを動かさない' => sub {
	my $thumb = "$img/test/.thumbnail/gone.png.jpg";
	my $moved = "$img/test/.thumbnail/d.png.jpg";
	mkdir("$img/test/.thumbnail");
	touch($thumb);

	my $r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => 'gone.png', name => 'd.png' });
	isnt(json_ret($r), '0', '元のファイルが無いと失敗する');
	ok(-e $thumb,  '元のサムネイルは残る');
	ok(!-e $moved, '変更先にサムネイルができない');

	unlink($thumb);
};

#-------------------------------------------------------------------------------
# ファイルの削除
#-------------------------------------------------------------------------------
subtest 'ファイルの削除で、フォルダの外を消せない' => sub {
	touch("$dir/pub/keep.txt");
	my $r = $app->post('admin', '', { action => 'media/delete_files', folder => 'test/', file_ary => '../../keep.txt' });
	isnt(json_ret($r), '0', '../ を入れると失敗する');
	ok(-f "$dir/pub/keep.txt",     'フォルダの外のファイルは残る');

	touch("$img/test/del.txt");
	$r = $app->post('admin', '', { action => 'media/delete_files', folder => 'test/', file_ary => 'del.txt' });
	is(json_ret($r), '0', '普通のファイルは消せる');
	ok(!-e "$img/test/del.txt",    'ファイルが消える');
};

#-------------------------------------------------------------------------------
# フォルダ名
#-------------------------------------------------------------------------------
subtest 'フォルダ名の .. は取り除かれる' => sub {
	touch("$dir/pub/keep2.txt");
	foreach my $folder ('..', '../', '/..', '..//', './..', '...', '/./../') {
		my $r = $app->post('admin', '', { action => 'media/delete_folder', folder => $folder });
		isnt(json_ret($r), '0', "folder=$folder の削除は失敗する");
		ok(-d $img,                "folder=$folder でメディア管理の根元が残る");
		ok(-f "$dir/pub/keep2.txt", "folder=$folder でメディア管理の外が残る");
	}
	ok(-f "$img/$file",            'メディア管理の中身も残る');

	touch("$dir/pub/keep3.txt");
	my $r = $app->post('admin', '', { action => 'media/delete_files', folder => '..', file_ary => 'keep3.txt' });
	isnt(json_ret($r), '0', 'folder=.. でメディア管理の外のファイルを消せない');
	ok(-f "$dir/pub/keep3.txt",    'メディア管理の外のファイルは残る');

	$r = $app->post('admin', '', { action => 'media/create_folder', folder => '/', name => 'tmpdir' });
	is(json_ret($r), '0', 'フォルダを作れる');
	$r = $app->post('admin', '', { action => 'media/delete_folder', folder => 'tmpdir/' });
	is(json_ret($r), '0', '普通のフォルダは消せる');
	ok(!-e "$img/tmpdir",          'フォルダが消える');
};

#-------------------------------------------------------------------------------
# アップロードするファイルの名前
#-------------------------------------------------------------------------------
subtest 'アップロードした名前の使えない文字は _ になる' => sub {
	my $png = do {
		open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/default-icon.png") || die $!;
		local $/; <$fh>;
	};
	foreach (['a:b.png', 'a_b.png'], ['q?x.png', 'q_x.png'], ["t\tb.png", 't_b.png'], ['a*b<c>.png', 'a_b_c_.png']) {
		my ($name, $saved) = @$_;
		my $label = $name =~ s/\t/\\t/r;
		my $r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/',
			file_ary => { filename => $name, content => $png, type => 'image/png' } ]);
		like($r->{body}, qr/^ret=0$/m, "$label をアップロードできる");
		ok(!-e "$img/test/$name",  "$label の名前では保存しない");
		ok(-f "$img/test/$saved",  "$saved で保存する");

		$r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => $saved, name => 'renamed.png' });
		is(json_ret($r), '0', "$saved の名前を変えられる");
		$r = $app->post('admin', '', { action => 'media/delete_files', folder => 'test/', file_ary => 'renamed.png' });
		is(json_ret($r), '0', '消せる');
		ok(!-e "$img/test/renamed.png", 'ファイルが消える');
	}
};

#-------------------------------------------------------------------------------
# 許可していない拡張子
#-------------------------------------------------------------------------------
subtest 'ファイル名の変更で、許可していない拡張子にできない' => sub {
	touch("$img/test/ext.txt");
	foreach my $name ('x.html', 'x.php', 'X.HTML', 'x.html.', 'x.php.', 'x.php..png', 'x.html.png', 'x..#20260101-000000php') {
		my $r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => 'ext.txt', name => $name });
		is(json_ret($r), '-1',       "$name には変えられない");
		ok(-f "$img/test/ext.txt",   "$name: 元のファイルは残る");
		ok(!-e "$img/test/$name",    "$name: ファイルができない");
	}
	foreach my $name ('y.txt', 'a.tar.gz', 'noext', 'ext.txt') {
		my $old = (grep { -e "$img/test/$_" } qw(ext.txt y.txt a.tar.gz noext))[0];
		my $r = $app->post('admin', '', { action => 'media/rename_file', folder => 'test/', old => $old, name => $name });
		is(json_ret($r), '0',        "$name には変えられる");
		ok(-f "$img/test/$name",     "$name: 名前が変わる");
	}
	unlink("$img/test/ext.txt");
};

subtest 'フォルダ名を、許可していない拡張子にできない' => sub {
	my $r;
	foreach my $name ('x.php', 'x.php/', 'x.html.') {
		$r = $app->post('admin', '', { action => 'media/create_folder', folder => '/', name => $name });
		is(json_ret($r), '-1',       "$name は作れない");
		ok(!-e "$img/$name",         "$name: フォルダができない");
	}
	$r = $app->post('admin', '', { action => 'media/create_folder', folder => '/', name => '2025.06' });
	is(json_ret($r), '0',            '数字の部分はフォルダ名に使える');

	foreach my $name ('x.php', 'x.php/') {
		$r = $app->post('admin', '', { action => 'media/rename_folder', folder => '/', old => '2025.06', name => $name });
		is(json_ret($r), '-1',       "$name には変えられない");
		ok(-d "$img/2025.06",        "$name: 元のフォルダは残る");
	}
	$r = $app->post('admin', '', { action => 'media/rename_folder', folder => '/', old => '2025.06', name => 'renamed/' });
	is(json_ret($r), '0',            '普通の名前には変えられる');
	$r = $app->post('admin', '', { action => 'media/delete_folder', folder => 'renamed/' });
	is(json_ret($r), '0',            '消せる');
};

subtest 'ゴミ箱から戻して、許可していない拡張子にできない' => sub {
	my $trash = "$img/.trashbox";
	mkdir($trash);
	foreach (['x..#20260101-000000php', 'x.php'], ['y.p.#20260101-000000hp', 'y.php'], ['z.html.#20260101-000000', 'z.html']) {
		my ($name, $des) = @$_;
		touch("$trash/$name");
		my $r = $app->post('admin', '', { action => 'media/move_files', from => '.trashbox/', to => 'test/', file_ary => $name });
		is(json_ret($r), '1',        "$name は戻せない");
		ok(-f "$trash/$name",        "$name: ゴミ箱に残る");
		ok(!-e "$img/test/$des",     "$des ができない");
		unlink("$trash/$name");
	}

	# ゴミ箱の中どうしで動かしても、日付は外れない
	mkdir("$trash/sub");
	touch("$trash/inner.txt.#20260101-000000");
	my $r = $app->post('admin', '', { action => 'media/move_files', from => '.trashbox/', to => '.trashbox/sub/', file_ary => 'inner.txt.#20260101-000000' });
	is(json_ret($r), '0',            'ゴミ箱の中で動かせる');
	ok(-f "$trash/sub/inner.txt.#20260101-000000", '名前は変わらない');

	# 普通のファイルは行き来できる
	touch("$img/test/normal.txt");
	$r = $app->post('admin', '', { action => 'media/move_files', from => 'test/', to => '.trashbox/', file_ary => 'normal.txt' });
	is(json_ret($r), '0',            '普通のファイルをゴミ箱へ入れられる');
	my ($stamped) = map { s!.*/!!r } glob("$trash/normal.*");
	$r = $app->post('admin', '', { action => 'media/move_files', from => '.trashbox/', to => 'test/', file_ary => $stamped });
	is(json_ret($r), '0',            'ゴミ箱から戻せる');
	ok(-f "$img/test/normal.txt",    '元の名前に戻る');
	unlink("$img/test/normal.txt");
};

subtest 'アップロードで、空の拡張子を使った名前を通さない' => sub {
	my $png = do {
		open(my $fh, '<:raw', "$FindBin::Bin/../pub/assets/dist/default-icon.png") || die $!;
		local $/; <$fh>;
	};
	my $r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/',
		file_ary => { filename => 'x.php..png', content => $png, type => 'image/png' } ]);
	like($r->{body}, qr/^ret=0$/m,   'x.php..png は名前を直してアップロードする');
	ok(!-e "$img/test/x.php..png",   'その名前では保存しない');
	ok(-f "$img/test/x_php_.png",    '. を _ にして保存する');
	unlink("$img/test/x_php_.png");

	$r = $app->post('admin', '', [ action => 'media/upload_form', folder => 'test/',
		file_ary => { filename => 'x.html.', content => 'x', type => 'text/plain' } ]);
	ok(!-e "$img/test/x.html.",      'x.html. は保存しない');
};

done_testing();
