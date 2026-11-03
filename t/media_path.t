use strict;
use utf8;
#-------------------------------------------------------------------------------
# メディア管理のパスのテスト
#-------------------------------------------------------------------------------
# 実行: prove t/media_path.t
#
# ファイル名やフォルダ名に .. や / を入れても、アルバムのフォルダ（pub/attachments/）の
# 外のファイルを変えられないことを確かめる。Image::Magickは要らない。
#
use FindBin;
BEGIN { push(@INC, "$FindBin::Bin/lib", "$FindBin::Bin/../lib"); }
use Test::More;
use AppTest;

binmode(Test::More->builder->$_, ':utf8') foreach (qw(output failure_output todo_output));

my $app = AppTest->new()->setup()->seed();
my $dir = $app->dir;
my $img = "$dir/pub/attachments";
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
	$r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => 'a.png', name => '../../outside.png' });
	isnt(json_ret($r), '0', '新しい名前に ../ を入れると失敗する');
	ok(-f "$img/$file",            '元のファイルは残る');
	ok(!-e "$dir/outside.png",     'フォルダの外にファイルができない');

	touch("$dir/pub/secret.txt");
	$r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => '../../secret.txt', name => 'got.txt' });
	isnt(json_ret($r), '0', '元の名前に ../ を入れると失敗する');
	ok(-f "$dir/pub/secret.txt",   'フォルダの外のファイルは動かない');
	ok(!-e "$img/test/got.txt",    'アルバムに持ち込めない');

	$r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => 'a.png', name => '.htaccess' });
	isnt(json_ret($r), '0', '. で始まる名前にはできない');
	ok(-f "$img/$file",            '元のファイルは残る');

	$r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => 'a.png', name => 'b.png' });
	is(json_ret($r), '0', '普通の名前には変えられる');
	$r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => 'b.png', name => 'a.png' });
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

	my $r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => 'a.png', name => 'c.png' });
	isnt(json_ret($r), '0', '同じ名前のファイルがあると失敗する');
	is(-s "$img/$file", $size,     '元のファイルは残る');
	is(-s $other, 1,               '変更先のファイルの中身は変わらない');
	ok(-e $thumb,                  '変更先のサムネイルは残る');

	unlink($other, $thumb);
};

#-------------------------------------------------------------------------------
# ファイルの削除
#-------------------------------------------------------------------------------
subtest 'ファイルの削除で、フォルダの外を消せない' => sub {
	touch("$dir/pub/keep.txt");
	my $r = $app->post('editor', '', { action => 'media/delete_files', folder => 'test/', file_ary => '../../keep.txt' });
	isnt(json_ret($r), '0', '../ を入れると失敗する');
	ok(-f "$dir/pub/keep.txt",     'フォルダの外のファイルは残る');

	touch("$img/test/del.txt");
	$r = $app->post('editor', '', { action => 'media/delete_files', folder => 'test/', file_ary => 'del.txt' });
	is(json_ret($r), '0', '普通のファイルは消せる');
	ok(!-e "$img/test/del.txt",    'ファイルが消える');
};

#-------------------------------------------------------------------------------
# フォルダ名
#-------------------------------------------------------------------------------
subtest 'フォルダ名の .. は取り除かれる' => sub {
	touch("$dir/pub/keep2.txt");
	foreach my $folder ('..', '../', '/..', '..//', './..', '...', '/./../') {
		my $r = $app->post('editor', '', { action => 'media/delete_folder', folder => $folder });
		isnt(json_ret($r), '0', "folder=$folder の削除は失敗する");
		ok(-d $img,                "folder=$folder でアルバムの根元が残る");
		ok(-f "$dir/pub/keep2.txt", "folder=$folder でアルバムの外が残る");
	}
	ok(-f "$img/$file",            'アルバムの中身も残る');

	touch("$dir/pub/keep3.txt");
	my $r = $app->post('editor', '', { action => 'media/delete_files', folder => '..', file_ary => 'keep3.txt' });
	isnt(json_ret($r), '0', 'folder=.. でアルバムの外のファイルを消せない');
	ok(-f "$dir/pub/keep3.txt",    'アルバムの外のファイルは残る');

	$r = $app->post('editor', '', { action => 'media/create_folder', folder => '/', name => 'tmpdir' });
	is(json_ret($r), '0', 'フォルダを作れる');
	$r = $app->post('editor', '', { action => 'media/delete_folder', folder => 'tmpdir/' });
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
		my $r = $app->post('editor', '', [ action => 'media/upload_form', folder => 'test/',
			file_ary => { filename => $name, content => $png, type => 'image/png' } ]);
		like($r->{body}, qr/^ret=0$/m, "$label をアップロードできる");
		ok(!-e "$img/test/$name",  "$label の名前では保存しない");
		ok(-f "$img/test/$saved",  "$saved で保存する");

		$r = $app->post('editor', '', { action => 'media/rename_file', folder => 'test/', old => $saved, name => 'renamed.png' });
		is(json_ret($r), '0', "$saved の名前を変えられる");
		$r = $app->post('editor', '', { action => 'media/delete_files', folder => 'test/', file_ary => 'renamed.png' });
		is(json_ret($r), '0', '消せる');
		ok(!-e "$img/test/renamed.png", 'ファイルが消える');
	}
};

done_testing();
