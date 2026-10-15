package Lyndbaum::Media;
# 添付ファイルの一覧とゴミ箱（docs/admin.md の「メディア」）
#   ファイルは DB に持たず、フォルダ（pub/attachments）の中身を読んで出す（docs/db-schema.md）
#   消したファイルは、添付ファイルの置き場所の .trashbox に移す（旧システムと同じく、名前に消した日時を入れる）
#
# フォルダは「posts/2026/10/」のように、/ で終わる相対パスで表す（いちばん上は空の文字列）
# . で始まるフォルダとファイル（.thumbnail など）は出さない
use strict;
use warnings;
use utf8;
use feature 'current_sub';

use Encode qw(decode_utf8 encode_utf8);
use File::Copy qw(move);
use File::Path qw(make_path);
use File::Spec;

# ゴミ箱のフォルダの名前（添付ファイルの置き場所の中）
our $TRASH = '.trashbox';

my %KIND_OF_EXT = (
	jpg => 'image', jpeg => 'image', png => 'image', apng => 'image', gif => 'image', webp => 'image',
	mp4 => 'video', webm => 'video',
);

# %args：dir（添付ファイルの置き場所）、trash_dir（ゴミ箱）
sub new {
	my ($class, %args) = @_;
	return bless { dir => $args{dir}, trash_dir => $args{trash_dir} }, $class;
}

# フォルダの書き方が正しいか（.. や . で始まる区切り、空の区切りを含まない）。正しければ / で終わる形にして返す
sub clean_folder {
	my ($class, $folder) = @_;
	$folder //= '';
	return '' if $folder eq '' || $folder eq '/';
	$folder .= '/' if $folder !~ m{/\z};
	return undef if $folder =~ m{\A/} || grep { $_ eq '' || /\A\./ || /[\\\x00-\x1F]/ } split m{/}, $folder;
	return $folder;
}

# ファイル名の書き方が正しいか（区切りを含まず、. で始まらない）
sub valid_name {
	my ($class, $name) = @_;
	return defined $name && $name ne '' && $name !~ m{[/\\\x00-\x1F]} && $name !~ /\A\./;
}

sub _path {
	my ($self, $base, $folder, $name) = @_;
	return encode_utf8(File::Spec->catfile($base, (split m{/}, $folder), defined $name ? $name : ()));
}

# フォルダの木 [ { folder => 'posts/', name => 'posts', count => ファイルの数, children => [...] }, ... ]
#   名前の逆順（新しい年月を先に）
sub folders {
	my ($self) = @_;
	my $walk = sub {
		my ($folder) = @_;
		my $path = $self->_path($self->{dir}, $folder);
		opendir my $dh, $path or return [];
		my @names = sort { $b cmp $a } grep { !/\A\./ && -d "$path/$_" } readdir $dh;
		return [ map {
			my $name = decode_utf8($_);
			my $child = "$folder$name/";
			+{ folder => $child, name => $name, count => scalar @{ $self->files($child) }, children => __SUB__->($child) }
		} @names ];
	};
	return $walk->('');
}

# フォルダの中のファイル（新しい順）[ { name, size, mtime, kind, thumbnail（サムネイルがあるか） }, ... ]
sub files {
	my ($self, $folder) = @_;
	my $path = $self->_path($self->{dir}, $folder);
	opendir my $dh, $path or return [];
	my @files;
	for my $raw (grep { !/\A\./ } readdir $dh) {
		my @stat = stat "$path/$raw";
		next if !@stat || !-f _;
		my $name = decode_utf8($raw);
		my ($ext) = $name =~ /\.([^.]+)\z/;
		push @files, {
			name      => $name,
			size      => $stat[7],
			mtime     => $stat[9],
			kind      => $KIND_OF_EXT{ lc($ext // '') } // 'other',
			ext       => lc($ext // ''),
			thumbnail => -f "$path/.thumbnail/$raw.jpg" ? 1 : 0,
		};
	}
	return [ sort { $b->{mtime} <=> $a->{mtime} || $a->{name} cmp $b->{name} } @files ];
}

# そのファイルを使っている記事（ゴミ箱の中を含む）[ { id, title, deleted_at }, ... ]
#   本文の記法（[image:S:フォルダ/:名前]）、URL や旧システムのパス（フォルダ/名前）、OGP の画像（og_image）から探す
#   SQL で候補を絞ってから、名前の直後が区切り（記法の : や ]、URL の後ろの空白や " ) など）かを確かめる
#   （「a.jpg」を探して「a.jpg.bak」を使っている記事が当たらないように）
sub usage {
	my ($self, $dbh, $folder, $name) = @_;
	my $rows = $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, "$folder:$name", "$folder$name", "$folder$name");
SELECT id, title, deleted_at, body_src, og_image FROM articles
WHERE instr(body_src, ?) > 0 OR instr(body_src, ?) > 0 OR og_image = ?
ORDER BY id DESC
SQL
	my $re = qr{(?:\Q$folder:$name\E(?=[:\]])|\Q$folder$name\E(?=[\s"'<>()\]?#]|\z))};
	return [ map { +{ id => $_->{id}, title => $_->{title}, deleted_at => $_->{deleted_at} } }
		grep { $_->{og_image} eq "$folder$name" || $_->{body_src} =~ $re } @$rows ];
}

# ゴミ箱へ移す（サムネイルも）。ゴミ箱での名前を返す。無ければ die
sub trash {
	my ($self, $folder, $name, %opt) = @_;
	my $src = $self->_path($self->{dir}, $folder, $name);
	die "「$folder$name」はありません。\n" if !-f $src;
	my ($base, $ext) = $name =~ /\A(.*?)((?:\.[^.]*)?)\z/s;
	my ($sec, $min, $hour, $mday, $mon, $year) = gmtime(($opt{now} // time) + 9 * 60 * 60);   # 日本時間
	my $stamp = sprintf '%04d%02d%02d-%02d%02d%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec;
	my $trashed = "$base.#$stamp$ext";
	for (my $n = 2; -e $self->_path($self->{trash_dir}, $folder, $trashed); $n++) {
		$trashed = "$base.#$stamp-$n$ext";
	}
	make_path($self->_path($self->{trash_dir}, $folder, '.thumbnail'));
	move($src, $self->_path($self->{trash_dir}, $folder, $trashed)) or die "「$folder$name」を移せません: $!\n";
	my $thumb = $self->_path($self->{dir}, $folder, ".thumbnail/$name.jpg");
	move($thumb, $self->_path($self->{trash_dir}, $folder, ".thumbnail/$trashed.jpg")) if -f $thumb;
	return $trashed;
}

# ゴミ箱の中 [ { folder, name（ゴミ箱での名前）, original（元の名前）, deleted（消した日時の文字列）, size, kind, thumbnail }, ... ]
#   消した日時の新しい順
sub trash_files {
	my ($self) = @_;
	my @files;
	my $walk = sub {
		my ($folder) = @_;
		my $path = $self->_path($self->{trash_dir}, $folder);
		opendir my $dh, $path or return;
		for my $raw (grep { !/\A\./ } readdir $dh) {
			my $name = decode_utf8($raw);
			if (-d "$path/$raw") {
				__SUB__->("$folder$name/");
				next;
			}
			my ($base, $stamp, $ext) = $name =~ /\A(.*)\.#(\d{8}-\d{6}(?:-\d+)?)((?:\.[^.]*)?)\z/s or next;
			my ($ext_only) = $ext =~ /\.([^.]+)\z/;
			push @files, {
				folder    => $folder,
				name      => $name,
				original  => "$base$ext",
				deleted   => $stamp =~ s/\A(\d{4})(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d).*\z/$1-$2-$3 $4:$5/r,
				stamp     => $stamp,
				size      => -s "$path/$raw",
				kind      => $KIND_OF_EXT{ lc($ext_only // '') } // 'other',
				thumbnail => -f "$path/.thumbnail/$raw.jpg" ? 1 : 0,
			};
		}
	};
	$walk->('');
	return [ sort { $b->{stamp} cmp $a->{stamp} || $a->{folder} cmp $b->{folder} || $a->{name} cmp $b->{name} } @files ];
}

# ゴミ箱から戻す。戻した名前を返す（同じ名前があれば 名前-2 にする）
sub restore {
	my ($self, $folder, $trashed) = @_;
	my $src = $self->_path($self->{trash_dir}, $folder, $trashed);
	die "ゴミ箱に「$folder$trashed」はありません。\n" if !-f $src;
	my ($base, $ext) = $trashed =~ /\A(.*)\.#\d{8}-\d{6}(?:-\d+)?((?:\.[^.]*)?)\z/s or die "ゴミ箱の名前が正しくありません。\n";
	my $name = "$base$ext";
	for (my $n = 2; -e $self->_path($self->{dir}, $folder, $name); $n++) {
		$name = "$base-$n$ext";
	}
	make_path($self->_path($self->{dir}, $folder, '.thumbnail'));
	move($src, $self->_path($self->{dir}, $folder, $name)) or die "「$folder$trashed」を戻せません: $!\n";
	my $thumb = $self->_path($self->{trash_dir}, $folder, ".thumbnail/$trashed.jpg");
	move($thumb, $self->_path($self->{dir}, $folder, ".thumbnail/$name.jpg")) if -f $thumb;
	return $name;
}

# ゴミ箱から完全に消す
sub purge {
	my ($self, $folder, $trashed) = @_;
	my $src = $self->_path($self->{trash_dir}, $folder, $trashed);
	die "ゴミ箱に「$folder$trashed」はありません。\n" if !-f $src;
	unlink $src or die "「$folder$trashed」を消せません: $!\n";
	unlink $self->_path($self->{trash_dir}, $folder, ".thumbnail/$trashed.jpg");
	return 1;
}

1;
