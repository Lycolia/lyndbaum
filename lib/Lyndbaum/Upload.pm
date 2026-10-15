package Lyndbaum::Upload;
# 添付ファイル（画像と動画）のアップロード（docs/admin.md の「画像のアップロード」）
#   pub/attachments/posts/年/月/ に置き、画像なら .thumbnail/ファイル名.jpg にサムネイルを作る
#   拡張子と中身（先頭のバイト）の両方で種類を確かめる（CLAUDE.md の「セキュリティ」）
use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use Lyndbaum::Thumbnail;

# 拡張子 => 種類。種類ごとに、中身の先頭がどうなっているべきかを決める
my %KIND_OF_EXT = (
	jpg => 'jpeg', jpeg => 'jpeg', png => 'png', apng => 'png', gif => 'gif', webp => 'webp',
	mp4 => 'mp4', webm => 'webm',
);
my %MAGIC = (
	jpeg => sub { $_[0] =~ /\A\xFF\xD8\xFF/ },
	png  => sub { $_[0] =~ /\A\x89PNG\r\n\x1A\n/ },
	gif  => sub { $_[0] =~ /\AGIF8[79]a/ },
	webp => sub { $_[0] =~ /\ARIFF....WEBP/s },
	mp4  => sub { $_[0] =~ /\A....ftyp/s },
	webm => sub { $_[0] =~ /\A\x1A\x45\xDF\xA3/ },
);
my %IS_IMAGE = map { $_ => 1 } qw(jpeg png gif webp);
my $MAX_NAME = 100;

# 1つのファイルを置く
#   %args
#     dir             添付ファイルの置き場所（ファイルシステムのパス。pub/attachments）
#     filename        送られたファイル名
#     data            中身（バイト列）
#     thumbnail_size  サムネイルの長い辺（px）
#     now             今の時刻（テスト用。フォルダの年月に使う。日本時間）
#   戻り値は { folder => 'posts/2026/10/', name => ファイル名, kind => 種類, image => 画像か, thumbnail => サムネイルを作れたか }
#   置けないときは die する（理由の文）
sub save {
	my ($class, %args) = @_;
	my $name = $class->clean_name($args{filename} // '');
	my ($ext) = $name =~ /\.([^.]+)\z/;
	my $kind = $KIND_OF_EXT{ lc($ext // '') }
		// die "「$args{filename}」は置けない種類のファイルです（置けるのは " . join('、', sort keys %KIND_OF_EXT) . "）。\n";
	die "「$args{filename}」は、拡張子と中身の種類が合いません。\n" if !$MAGIC{$kind}->($args{data} // '');

	my $folder = $class->folder_of($args{now} // time);
	my $dir = File::Spec->catdir($args{dir}, split m{/}, $folder);
	make_path(encode_utf8($dir), { mode => 0755 });
	$name = $class->_unique_name($dir, $name);
	_write(File::Spec->catfile($dir, $name), $args{data});

	my $thumbnail = 0;
	if ($IS_IMAGE{$kind}) {
		my $jpeg = eval { Lyndbaum::Thumbnail->make($args{data}, $kind, $args{thumbnail_size}) };
		warn "サムネイルを作れませんでした: $folder$name: $@" if !defined $jpeg;
		if (defined $jpeg) {
			my $thumb_dir = File::Spec->catdir($dir, '.thumbnail');
			make_path(encode_utf8($thumb_dir), { mode => 0755 });
			_write(File::Spec->catfile($thumb_dir, "$name.jpg"), $jpeg);
			$thumbnail = 1;
		}
	}
	return { folder => $folder, name => $name, kind => $kind, ext => lc $ext, image => $IS_IMAGE{$kind} ? 1 : 0, thumbnail => $thumbnail };
}

# 本文に入れる記法（docs/markdown-syntax.md）。サムネイルが無い画像は、元の画像を出す（L）
sub tag_of {
	my ($class, $file) = @_;
	return $file->{image}
		? sprintf('[image:%s:%s:%s]', $file->{thumbnail} ? 'S' : 'L', $file->{folder}, $file->{name})
		: sprintf('[file:%s:%s:%s]', $file->{ext}, $file->{folder}, $file->{name});
}

# 置くフォルダ（日本時間の年月）
sub folder_of {
	my ($class, $epoch) = @_;
	my (undef, undef, undef, undef, $mon, $year) = gmtime($epoch + 9 * 60 * 60);
	return sprintf 'posts/%04d/%02d/', $year + 1900, $mon + 1;
}

# ファイル名を整える
#   パスの区切りや、記法の区切り（: と ]）、URLで困る文字、空白は _ にする。先頭の . は取る（隠しファイルにしない）
#   名前の中のピリオドも _ にし、拡張子を最後の1つだけにする
#   長すぎれば、拡張子を残して切る
sub clean_name {
	my ($class, $name) = @_;
	$name =~ s{\A.*[/\\]}{};   # ブラウザによってはパスごと送ってくる
	$name =~ s{[\x00-\x1F\x7F/\\:*?"<>|#%&\[\]\s]}{_}g;
	my ($base, $ext) = $name =~ /\A(.*?)((?:\.[^.]*)?)\z/s;
	$base =~ s/\A\.+//;
	# 名前の中のピリオドは _ にする（拡張子を1つにする）。Apache の AddHandler はファイル名の中の拡張子をどれも見るので、
	# shell.php.mp4 のような名前だと、PHP などのスクリプトとして動くおそれがあるため（旧システムに作者が入れた防御と同じ）
	$base =~ tr/./_/;
	$base = substr $base, 0, $MAX_NAME - length $ext if length($base) + length($ext) > $MAX_NAME;
	$base = 'file' if $base eq '';
	return "$base$ext";
}

# 同じ名前のファイルがあれば、名前-2、名前-3 … にする（上書きしない）
sub _unique_name {
	my ($class, $dir, $name) = @_;
	my ($base, $ext) = $name =~ /\A(.*?)((?:\.[^.]*)?)\z/s;
	my $candidate = $name;
	for (my $n = 2; -e encode_utf8(File::Spec->catfile($dir, $candidate)); $n++) {
		$candidate = "$base-$n$ext";
	}
	return $candidate;
}

# 一時ファイルに書いてから置き換える（書きかけのファイルを読ませない）
sub _write {
	my ($file, $data) = @_;
	my $path = encode_utf8($file);
	my (undef, $dir) = File::Spec->splitpath($path);
	my ($fh, $tmp) = tempfile('.upload-XXXXXX', DIR => $dir, UNLINK => 0);
	binmode $fh;
	print {$fh} $data or die "$tmp: $!\n";
	close $fh or die "$tmp: $!\n";
	chmod 0644, $tmp;
	rename $tmp, $path or do { my $error = $!; unlink $tmp; die "$path: $error\n" };
}

1;
