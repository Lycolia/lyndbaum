use strict;
#-------------------------------------------------------------------------------
# adiary_3.pm (C)nabe@abk
#-------------------------------------------------------------------------------
# ・画像管理
# ・ブログの設定
# ・記事、コメントなどの削除関連
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
package SatsukiApp::adiary;
################################################################################
# ■画像管理
################################################################################
#-------------------------------------------------------------------------------
# ●画像dir関連の初期化
#-------------------------------------------------------------------------------
sub init_image_dir {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $self->blogimg_dir();
	$ROBJ->mkdir($dir);
	$ROBJ->mkdir($dir . '.trashbox/');	# ごみ箱フォルダ

	# フォルダリストの生成
	$self->genarete_imgae_dirtree();
}

#-------------------------------------------------------------------------------
# ●画像ディレクトリツリーの生成
#-------------------------------------------------------------------------------
sub genarete_imgae_dirtree {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir   = $self->blogimg_dir();
	my $tree  = $self->get_dir_tree($dir);
	my $trash = $self->get_dir_tree($dir . '.trashbox/', '.trashbox/');	# ゴミ箱

	$tree->{name} = '/';
	$tree->{key}  = '/';
	$trash->{name} = '.trashbox/';
	$trash->{key}  = '.trashbox/';
	my $json = $self->generate_json([$tree, $trash], ['name', 'key', 'date', 'count', 'children']);
	$ROBJ->fwrite_lines( $self->{pub_dir} . 'images.json', $json);

	return $tree->{count};
}

#-------------------------------------------------------------------------------
# ●ディレクトリ階層の全データ取得
#-------------------------------------------------------------------------------
sub get_dir_tree {
	my $self = shift;
	my $dir  = shift;
	my $path = shift;
	my $ROBJ = $self->{ROBJ};

	my $list = $ROBJ->search_files($dir, {dir=>1});
	@$list = sort {		# '@'(0x40)を最後に表示する仕組み
		my $x = (ord($a)==0x40) cmp (ord($b)==0x40);
		$x ? $x : $a cmp $b;
	} @$list;

	my @dirs;
	my $files=0;
	my $cnt  =0;	# ファイル数カウント
	foreach(@$list) {
		if (substr($_,-1) ne '/') {
			# ただのファイル
			$files++;
			next;
		}
		# ディレクトリ
		my $d    = $_;
		my $tree = $self->get_dir_tree("$dir$_", "$path$d");
		$tree->{name} = $d;
		push(@dirs, $tree);
		$cnt += $tree->{count};
	}

	my $h = { key => $path, date => (stat($dir))[9], count => ($cnt + $files) };
	if (@dirs) {
		$h->{children} = \@dirs;
	}
	return $h;
}

#-------------------------------------------------------------------------------
# ●ディレクトリ内のファイル一覧取得
#-------------------------------------------------------------------------------
sub load_image_files {
	my $self = shift;
	my $dir  = $self->image_folder_to_dir( shift );	# 値check付
	my $ROBJ = $self->{ROBJ};

	if (!-r $dir) {
		return(-1,'["msg":"Folder not found"]');
	}

	my $files = $ROBJ->search_files( $dir );
	# サムネイル生成
	if (@$files) {
		$self->make_thumbnail($dir, $files);
	}

	my @ary;
	foreach(@$files) {
		my @st = stat("$dir$_");
		push(@ary,{
			name => $_,
			size => $st[7],
			date => $st[9],
			isImg=> $self->is_image($_),
			thumb=> $self->thumbnail_name($dir, $_)	# .thumbnail/ の中のファイル名
		});
	}

	my $json = $self->generate_json(\@ary, ['name', 'size', 'date', 'isImg', 'thumb', 'children']);
	return (0, $json);
}

#-------------------------------------------------------------------------------
# ●ディレクトリ内のEXIFあり画像一覧
#-------------------------------------------------------------------------------
sub load_exif_files {
	my $self = shift;
	my $dir  = $self->image_folder_to_dir( shift );	# 値check付
	my $ROBJ = $self->{ROBJ};
	if (!-r $dir) {
		return(-1,'["msg":"Folder not found"]');
	}

	my $files = $ROBJ->search_files( $dir );
	my $jpeg = $ROBJ->loadpm('Jpeg');
	my @ary;
	foreach(@$files) {
		if ($_ !~ /\.jpe?g$/i) { next; }
		if (! $jpeg->check_exif("$dir$_")) { next; }
		push(@ary, $_);
	}

	my $json = $self->generate_json(\@ary);
	return (0, $json);
}

#-------------------------------------------------------------------------------
# ●サムネイルの大きさ（長い辺）
#-------------------------------------------------------------------------------
# 編集画面の設定（edit_thumb_size）だけで決める。アップロードや再生成のときに選ばせない
sub thumbnail_size {
	my $self = shift;
	my $size = int($self->{blog}->{edit_thumb_size}) || 320;
	if ($size <  60) { $size= 60; }
	if (800 < $size) { $size=800; }
	return $size;
}

#-------------------------------------------------------------------------------
# ●サムネイルの形式
#-------------------------------------------------------------------------------
# 画像と動画のサムネイルは、ImageMagickでAVIFを書けるならAVIF（.thumbnail/元の名前.avif）、書けなければJPEG（.jpg）。
# 動画の記事用のサムネイル（.thumbnail/動画名.poster.avif か .poster.jpg）も同じ。
# 画像でも動画でもないファイルのアイコンはいつもJPEG。
# 前に作ったJPEGのサムネイルが残っていることもあるので、使うときは thumbnail_name、poster_file で今あるものを探す
#
# 下の関数の $suffix は、一覧用なら空、動画の記事用なら '.poster'
#
our @THUMBNAIL_EXTS = ('avif', 'jpg');

sub thumbnail_ext {
	my ($self, $file) = @_;
	if (defined $file && !$self->is_image($file) && !$self->is_video($file)) { return 'jpg'; }
	require Satsuki::ImageFormat;
	return Satsuki::ImageFormat::can_write_avif() ? 'avif' : 'jpg';
}

# 今あるサムネイルのファイル名（.thumbnail/ の中）。無ければ、これから作る名前
sub thumbnail_name {
	my ($self, $dir, $file) = @_;
	foreach(@THUMBNAIL_EXTS) {
		if (-e "${dir}.thumbnail/$file.$_") { return "$file.$_"; }
	}
	return "$file." . $self->thumbnail_ext($file);
}

# 今ある動画の記事用のサムネイルの実パス。無ければ空
sub poster_file {
	my ($self, $dir, $file) = @_;
	foreach(@THUMBNAIL_EXTS) {
		if (-e "${dir}.thumbnail/$file.poster.$_") { return "${dir}.thumbnail/$file.poster.$_"; }
	}
	return '';
}

# サムネイルを消す（どの形式も）
sub delete_thumbnail {
	my ($self, $dir, $file, $suffix) = @_;
	foreach(@THUMBNAIL_EXTS) {
		unlink("${dir}.thumbnail/$file$suffix.$_");
	}
}

# サムネイルを移す（どの形式も）。移せなかったものは消す。ret : 1つでも移せたら1
sub rename_thumbnail {
	my ($self, $from, $src, $to, $des, $suffix) = @_;
	my $r = 0;
	if ("$from$src" ne "$to$des") { $self->delete_thumbnail($to, $des, $suffix); }	# 移した先の古いサムネイルを優先しないように
	foreach(@THUMBNAIL_EXTS) {
		my $f = "${from}.thumbnail/$src$suffix.$_";
		if (!-e $f) { next; }
		if (rename($f, "${to}.thumbnail/$des$suffix.$_")) { $r=1; next; }
		unlink($f);
	}
	return $r;
}

#-------------------------------------------------------------------------------
# ●サムネイル生成
#-------------------------------------------------------------------------------
sub make_thumbnail {
	my $self = shift;
	my $dir  = shift;
	my $files= shift || [];
	my $opt  = shift || {};
	my $ROBJ = $self->{ROBJ};

	$ROBJ->mkdir("${dir}.thumbnail/");
	foreach(@$files) {
		my $thumb = "${dir}.thumbnail/$_.jpg";
		# すでに存在したら生成しない（前に作ったJPEGのサムネイルでもよい）
		if (!$opt->{force} && -r "${dir}.thumbnail/" . $self->thumbnail_name($dir, $_)) { next; }
		# 動画のサムネイルはブラウザーで作るので、作り直しでもアイコンに戻さない
		if ($self->is_video($_) && $self->poster_file($dir, $_)) { next; }

		my $isImage = $self->is_image($_);
		if ($isImage) {
			if ($opt->{del_exif}) {
				require Satsuki::ImageMeta;
				Satsuki::ImageMeta::clean_file("$dir$_", { exif => 1 });
			}
			my $r = $self->make_thumbnail_for_image($dir, $_);
			if (!$r) { next; }
			$self->delete_thumbnail($dir, $_);	# 作れなければアイコンにする
		}
		my $r = $self->make_thumbnail_for_notimage($dir, $_);
		if (!$r) { next; }

		# サムネイル生成に失敗したとき
		my $icon = $self->{media_icons} . $self->{media_allow_ext}->{'..'};
		if ($_ =~ m/\.(\w+)$/) {
			my $ext = $1;
			$ext =~ tr/A-Z/a-z/;
			my $exts = $self->load_media_allow_ext();
			my $file = $self->{media_allow_ext}->{$ext};
			if ($file) {
				$icon = $self->{media_icons} . $file;
			}
		}
		$ROBJ->file_copy($icon, $thumb);	# アイコンをコピー
	}
}

#-------------------------------------------------
# ○サムネイルパスを取得（for import_img() ）
#-------------------------------------------------
# 取り込んだ元のサイトのサムネイルを、そのままJPEGで置く
sub get_thumbnail_file {
	my $self = shift;
	my $dir  = shift;
	my $ROBJ = $self->{ROBJ};
	$ROBJ->mkdir("${dir}.thumbnail/");
	return "${dir}.thumbnail/" . (shift) . ".jpg";
}

#-------------------------------------------------
# ○画像ファイル
#-------------------------------------------------
# サムネイルを作ったら、ほかの形式の古いサムネイル（前に作ったJPEGなど）は消す
sub make_thumbnail_for_image {
	my $self = shift;
	my $dir  = shift;	# 実パス
	my $file = shift;
	my $ext  = $self->thumbnail_ext($file);
	my $r = $self->make_jpeg_thumbnail("$dir$file", "${dir}.thumbnail/$file.$ext", $self->thumbnail_size());
	if ($r == -3 && $ext ne 'jpg') {	# AVIFを書けなかった画像はJPEGにする
		$ext = 'jpg';
		$r = $self->make_jpeg_thumbnail("$dir$file", "${dir}.thumbnail/$file.$ext", $self->thumbnail_size());
	}
	if ($r) { return $r; }
	foreach(@THUMBNAIL_EXTS) {
		if ($_ ne $ext) { unlink("${dir}.thumbnail/$file.$_"); }
	}
	return 0;
}

#-------------------------------------------------
# ○画像を縮めて書き出す
#-------------------------------------------------
# 画像のサムネイルと、動画のサムネイル（記事用と一覧用）で使う
#	$src  : 読む画像の実パス
#	$dest : 書き出す実パス。拡張子が .avif ならAVIF、ほかはJPEG
#	$size : 長い辺の大きさ。これより小さい画像は縮めない
#	ret   : 成功なら0
# 回転してメタ情報を消し、4:2:0で書く。画質はAVIFなら media_avif_quality（既定65）、JPEGなら media_jpeg_quality（既定80）。JPEGはプログレッシブ（Satsuki::ImageFormat::make_thumbnail）
#
sub make_jpeg_thumbnail {
	my ($self, $src, $dest, $size) = @_;
	require Satsuki::ImageFormat;
	return Satsuki::ImageFormat::make_thumbnail($src, $dest, $size, {
		quality => ($dest =~ /\.avif$/i ? $self->{media_avif_quality} : $self->{media_jpeg_quality})	# 空なら make_thumbnail の既定値
	});
}

#-------------------------------------------------
# ○その他のファイル
#-------------------------------------------------
sub make_thumbnail_for_notimage {
	my $self = shift;
	my $dir  = shift;	# 実パス
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	# サイズ処理
	my $size  = 120;
	my $fsize = $self->{media_font_size};
	if($fsize < 6) { $fsize = 6; }
	my $fpixel = int($fsize*1.3333 + 0.999);
	my $f_height = $fpixel*3 +2;	# bottom padding = 2

	# キャンパス生成
	my $img = $self->load_image_magick();
	if (!$img) { return -99; }
	$img->Set(size => $size . 'x' . $size);
	$img->ReadImage('xc:white');

	# 拡張子アイコンの読み込み
	my $exts = $self->load_media_allow_ext();
	my $icon_dir  = $self->{media_icons};
	my $icon_file = $exts->{'.'};
	if ($self->is_image($file)) {
		$icon_file = $exts->{'.img'};	# 画像読み込みエラー時
	} elsif ($file =~ m/\.(\w+)$/) {
		my $ext = $1;
		$ext =~ tr/A-Z/a-z/;
		if ($exts->{$1}) {
			$icon_file = $exts->{$1};
		}
	}
	if (!-r "$icon_dir$icon_file") {	# 読み込めない時はdefaultアイコン
		$icon_file = $exts->{'.'};
	}
	my $icon = $self->load_image_magick();
	eval {
		$self->read_image( $icon, $icon_dir . $icon_file );

		my ($x, $y) = $icon->Get('width', 'height');
		$x = ($size - $x) / 2;
		$y =  $size - $f_height -$y -1;		# default 72 + 1 + 47 = 120
		$img->Composite(image=>$icon, compose=>'Over', x=>$x, y=>$y);
	};

	# 画像情報の書き込み
	my $media_file = $self->{media_font};
	if ($self->{media_font} && -r $media_file) {
		my @st = stat("$dir$file");
		my $tm = $ROBJ->print_tmf("%Y/%m/%d %H:%M", $st[9]);
		my $fs = $self->size_format($st[7]);
		my $name = $file;
		my $code = $ROBJ->{SystemCode};
		if ($code ne 'UTF-8') {
			my $jcode = $ROBJ->load_codepm();
			$name = $jcode->from_to($name, $code, 'UTF-8');
		}
		if ($dir =~ m|/\.trashbox/|) {	# ゴミ箱内？
			$self->remove_trash_timestamp($name);
		}
		$self->image_magick_text_encode( $name );
		my $text = "$name\r\n$tm\r\n$fs";
		$img->Annotate(
			text => $text,
			font => $media_file,
			x => 3,
			y => ($size - $f_height + $fpixel),	# 最初の行の baseline 基準なので1行下げる
			pointsize => $fsize
		);
	}

	# ファイルに書き出し
	$img->Set( quality => 98 );

	my $f = "${dir}.thumbnail/$file.jpg";
	$f =~ s/%/%%/g;
	$img->Write( $f );
	return 0;
}

sub size_format() {
	my $self = shift;
	my $s = shift;
	if ($s > 104857600) {	# 100MB
		$s = int(($s+524288)/1048576);
		$s =~ s/(\d{1,3})(?=(?:\d\d\d)+(?!\d))/$1,/g;
		return $s . ' MB';
	}
	if ($s > 1023487) { return sprintf("%.3g", $s/1048576) . ' MB'; }
	if ($s >     999) { return sprintf("%.3g", $s/1024   ) . ' KB'; }
	return $s . ' Byte';
}

sub image_magick_text_encode {
	my $self = shift;
	foreach(@_) {		# See more https://imagemagick.org/api/annotate.php
		$_ =~ s/%%/%/g;
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
	}
	return @_;
}

#-------------------------------------------------------------------------------
# ●画像のアップロード
#-------------------------------------------------------------------------------
sub image_upload_form {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付

	# アップロード
	my $count_s = 0;
	my $count_f = 0;
	my $ary = $form->{"file_ary"} || [];

	my @files;
	foreach(@$ary) {
		if (!ref($_)) { next; }

		my $fname = $_->{name};
		if ($fname eq '') { next; }

		if ($self->do_upload( $dir, $_, { exif => $form->{del_exif} } )){
			# $ROBJ->message('Upload fail: %s', $fname);
			$count_f++;
			next;
		}
		$fname = $_->{name};	# リネームされた場合は保存したファイル名
		$count_s++;
		$ROBJ->message('Upload: %s', $fname);
		push(@files, $fname);
	}

	# ファイルが残ってたら削除
	foreach(@$ary) {
		if (!ref($_)) { next; }
		my $tmp = $_->{tmp};
		if ($tmp) { $ROBJ->file_delete($tmp); }
	}

	# サムネイル生成（Exifの削除は、保存するときにdo_uploadで済ませてある）
	$self->make_thumbnail( $dir, \@files );

	# フォルダリストの再生成
	$self->genarete_imgae_dirtree();

	# 動画のサムネイルは、この後にブラウザーで作る（media/_action/upload_form、edit.js）
	$self->{uploaded_videos} = [ grep { $self->is_video($_) } @files ];

	# メッセージ
	return wantarray ? ($count_s, $count_f, \@files) : $count_f;
}

#-------------------------------------------------------------------------------
# ●ajax用の画像のアップロード
#-------------------------------------------------------------------------------
sub ajax_image_upload {
	my $self = shift;
	my $h = $self->do_ajax_image_upload( @_ );
	return $self->generate_json($h);
}
sub do_ajax_image_upload {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	# 画像フォルダ初期化
	$self->init_image_dir();

	# ディレクトリ作成
	my $dir = $self->image_folder_to_dir_and_create( $form->{folder} );

	my ($cs, $cf, $files) = $self->image_upload_form( $form );
	my %h;
	$h{ret}  = $cf ? 1 : 0;
	$h{fail} = $cf;
	$h{success} = $cs;
	$h{dir} = $dir;
	my @ary;
	foreach(@$files) {
		push(@ary,{
			name => $_,
			isImg=> $self->is_image($_),
			isVideo => $self->is_video($_) ? 1 : 0
		});
	}
	$h{files} = \@ary;
	return \%h;
}

#---------------------------------------------------------------------
# ●アップロードの実処理
#---------------------------------------------------------------------
sub do_upload {
	my $self = shift;
	my $dir  = shift;
	my $file_h = shift;
	my $opt  = shift || {};		# { exif => 1 } ならExifも消す
	my $ROBJ = $self->{ROBJ};

	# ハッシュデータ（フォームデータの確認）
	my $file_name = $file_h->{name};
	my $file_size = $file_h->{size};
	my $tmp_file  = $file_h->{tmp};		# 読み込んだファイルデータ(tmp file)

	# 中間拡張子が許可されていなければ、中間の . を _ に置き換える
	#   photo.edited.jpg → photo_edited.jpg
	if (! $self->media_check_ext($file_name) && $file_name =~ /^(.+)\.([^\.]+)$/) {
		my $base = $1;
		my $ext  = $2;
		$base =~ tr/./_/;
		$file_name = "$base.$ext";
	}

	# 名前の変更・移動・削除で使えない文字（check_file_name）は _ に置き換える
	#   a:b.png → a_b.png、.htaccess.png → _htaccess.png
	$file_name =~ s![\x00-\x1f/:\\\*\?\"<>|]!_!g;
	$file_name =~ s!^\.!_!;

	# 拡張子チェック
	if (! $self->media_check_ext($file_name)) {
		$ROBJ->message("File extension error : %s", $file_h->{name});
		return 3;
	}

	# 画像のメタ情報を消す。同じ画像かどうかを、消した後の中身で比べるため、保存する前に消す
	$self->clean_upload_meta($file_h, $opt);

	# ファイルの保存
	my $save_file = $dir . $file_name;
	if (-e $save_file && !$file_h->{overwrite}) {	# 同じ名前のファイルが存在する
		# 中身が同じなら、保存せずに今あるファイルを使う（同じ画像をもう一度上げたとき）
		if ($self->is_same_upload_file($save_file, $file_h)) {
			$file_h->{name} = $file_name;
			return 0;
		}
		# 中身が違えば、別の名前で保存する
		$file_name = $self->unique_upload_name($dir, $file_name);
		$save_file = $dir . $file_name;
	}

	my $fail;
	if ($tmp_file) {
		if ($ROBJ->file_move($tmp_file, $save_file)) { $fail=21; }
	} else {
		if ($ROBJ->fwrite_lines($save_file, $file_h->{data})) { $fail=22; }
	}
	if ($fail) {	# 保存失敗
		$ROBJ->message("File can't write '%s'", $file_name);
		return $fail;
	}
	# 実際に保存したファイル名を呼び出し元へ返す
	$file_h->{name} = $file_name;

	# サムネイル削除
	$self->delete_thumbnail( $dir, $file_name );
	$self->delete_thumbnail( $dir, $file_name, '.poster' );
	return 0;	# 成功
}

#---------------------------------------------------------------------
# ○アップロードした画像のメタ情報を消す
#---------------------------------------------------------------------
# 撮影情報（Exif）と表示に要るもの以外を消す。何を消すかはSatsuki::ImageMetaに書いてある
# 画像でないファイルや、壊れていて読めない画像は、そのまま保存する
#
sub clean_upload_meta {
	my ($self, $file_h, $opt) = @_;
	if (!$self->is_image($file_h->{name})) { return; }
	require Satsuki::ImageMeta;
	my $o = { exif => $opt->{exif} ? 1 : 0 };
	if ($file_h->{tmp}) {
		Satsuki::ImageMeta::clean_file($file_h->{tmp}, $o);
		return;
	}
	my ($r, $data) = Satsuki::ImageMeta::clean_data($file_h->{data}, $o);
	if (!$r && defined $data) {
		$file_h->{data} = $data;
		$file_h->{size} = length($data);
	}
}

#---------------------------------------------------------------------
# ○同じ名前のファイルがあるときの別名
#---------------------------------------------------------------------
# photo.jpg → photo_20261027-114032.jpg。その名前もあれば photo_20261027-114032_2.jpg、_3 …
# ※ゴミ箱に入れたときの名前（photo.#20261027-114032.jpg）とは形を変えてある
#
sub unique_upload_name {
	my ($self, $dir, $file_name) = @_;
	my $ROBJ = $self->{ROBJ};

	my ($base, $ext) = $file_name =~ /^(.*)(\.[^\.]+)$/ ? ($1, $2) : ($file_name, '');
	$base .= '_' . $ROBJ->print_tmf('%Y%m%d-%H%M%S');
	my $name = "$base$ext";
	for(my $i=2; -e $dir . $name; $i++) {
		$name = "${base}_$i$ext";
	}
	return $name;
}

#---------------------------------------------------------------------
# ○アップロードしたファイルと、今あるファイルの中身が同じか
#---------------------------------------------------------------------
sub is_same_upload_file {
	my ($self, $file, $file_h) = @_;
	my $size = $file_h->{tmp} ? -s $file_h->{tmp} : length($file_h->{data});
	if ((-s $file) != $size) { return 0; }
	if ($file_h->{tmp}) {
		require File::Compare;
		return File::Compare::compare($file, $file_h->{tmp}) == 0;
	}
	open(my $fh, '<:raw', $file) || return 0;
	local $/;
	my $data = <$fh>;
	close($fh);
	return $data eq $file_h->{data};
}

#-------------------------------------------------------------------------------
# ●サムネイルの再生成
#-------------------------------------------------------------------------------
sub remake_thumbnail {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir   = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $files = $form->{file_ary};
	my @names = @{ $files || [] };

	# サムネイル生成
	$self->make_thumbnail( $dir, $files, {
		del_exif => $form->{del_exif},
		force    => 1
	});

	# サムネイルの大きさが変わるので、使っている記事を作り直す
	$self->rebuild_arts_using_files(\@names);
	return 0;
}

#-------------------------------------------------------------------------------
# ●exifの除去
#-------------------------------------------------------------------------------
sub remove_exifjpeg {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir   = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $files = $form->{file_ary};

	# Exif削除（JPEG、PNG、WebP。ほかの形式は飛ばす）
	require Satsuki::ImageMeta;
	my $fail = 0;
	my @names;
	foreach(@$files) {
		if (!$self->is_image($_)) { next; }
		my ($r) = Satsuki::ImageMeta::clean_file("$dir$_", { exif => 1 });
		if ($r > 0) { next; }
		push(@names, $_);
		$fail += $r ? 1 : 0;
	}
	# Exifの向きが消えると縦と横が入れ替わることがあるので、使っている記事を作り直す
	$self->rebuild_arts_using_files(\@names);
	return $fail;
}

#-------------------------------------------------------------------------------
# ●ファイルを使っている記事を作り直す
#-------------------------------------------------------------------------------
# 記事のHTMLには、保存したときの画像の大きさ（width、height）を書いている（Tag_image.pm）。
# 本文にファイル名がある記事を作り直して、今の大きさにする。
# ファイル名だけで探すので、ほかのフォルダの同じ名前のファイルを使う記事も作り直すが、害は無い
#
sub rebuild_arts_using_files {
	my ($self, $files) = @_;
	my @names;
	foreach(@$files) {
		if ($_ eq '') { next; }
		push(@names, $_);
		my $esc = $_;			# 記法の中では : [ ] を \ でエスケープする
		if ($esc =~ s/([:\[\]])/\\$1/g) { push(@names, $esc); }
	}
	if (!@names) { return 0; }

	my $filter = sub {
		my $text = shift->{_text};
		foreach(@names) {
			if (index($text, $_) >= 0) { return 1; }
		}
		return 0;
	};
	# 編集者もサムネイルを作り直せるので、ここでは再構築を許す
	local($self->{blog_admin}) = 1;
	return $self->rebuild_blog({ filter => $filter });
}

#-------------------------------------------------------------------------------
# ●動画のサムネイルを保存する
#-------------------------------------------------------------------------------
# 動画の1コマは、管理画面でブラウザーが切り出してPNGで送る（サーバーではコマンドを動かさない）
# サーバーは、それを画像のサムネイルと同じ処理（make_jpeg_thumbnail）で、AVIFかJPEG（thumbnail_ext）にする
#   記事に出すサムネイル         → .thumbnail/動画名.poster.avif（.poster.jpg）
#   メディア管理の一覧に出すもの → .thumbnail/動画名.avif（.jpg）
# PNGで、大きさが決めた範囲のものだけを受け付ける。保存する名前はここで決める
#
my $VIDEO_POSTER_MAX = 960;	# 記事用のサムネイルの長い辺（記事での既定の表示480pxの2倍）

sub upload_video_thumbnail {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $r   = $self->save_video_thumbnail($dir, $form->{file}, $form->{poster});

	# 送られたファイルが残っていたら消す
	if (ref($form->{poster}) && $form->{poster}->{tmp}) { $ROBJ->file_delete($form->{poster}->{tmp}); }
	if ($r) { return $r; }

	# 記事に<video>ではなくサムネイルを出すように、使っている記事を作り直す
	$self->rebuild_arts_using_files([ $form->{file} ]);
	return 0;
}

sub save_video_thumbnail {
	my ($self, $dir, $file, $poster) = @_;
	my $ROBJ = $self->{ROBJ};
	if (!$self->check_file_name($file) || !$self->is_video($file)) { return 1; }
	if (!-f "$dir$file") { return 2; }
	if (!ref($poster)) { return 3; }

	require Satsuki::ImageFormat;
	$ROBJ->mkdir("${dir}.thumbnail/");
	# 送られたPNGを .tmp に書き、記事用と一覧用のサムネイルを作れたら、記事用を置き換える
	# どちらも送られたPNGから作る（圧縮を1回にする）
	my $th  = "${dir}.thumbnail/$file";
	my $tmp = "$th.poster.png.tmp";
	if ($poster->{tmp} ? $ROBJ->file_move($poster->{tmp}, $tmp) : $ROBJ->fwrite_lines($tmp, $poster->{data})) {
		$ROBJ->file_delete($tmp);
		return 4;
	}
	my ($w, $h);
	if (Satsuki::ImageFormat::detect($tmp) eq 'png') {
		($w, $h) = Satsuki::ImageFormat::get_size($tmp);
	}
	my $ext = $self->thumbnail_ext($file);
	my $make = sub {
		return $self->make_jpeg_thumbnail($tmp, "$th.poster.new.$ext", $VIDEO_POSTER_MAX)
		    || $self->make_jpeg_thumbnail($tmp, "$th.new.$ext", $self->thumbnail_size());
	};
	my $fail;
	if (!$w || $VIDEO_POSTER_MAX < $w || $VIDEO_POSTER_MAX < $h) {
		$fail = 5;
	} else {
		my $r = &$make();
		if ($r == -3 && $ext ne 'jpg') {	# AVIFを書けなければJPEGにする
			unlink("$th.poster.new.$ext", "$th.new.$ext");
			$ext = 'jpg';
			$r = &$make();
		}
		if ($r) {
			$fail = 7;
		} else {
			# ほかの形式の古いサムネイルを消してから置き換える（古いほうを先に見つけないように）
			foreach(@THUMBNAIL_EXTS) {
				if ($_ ne $ext) { unlink("$th.poster.$_", "$th.$_"); }
			}
			if (!rename("$th.poster.new.$ext", "$th.poster.$ext")) { $fail = 6; }
			elsif (!rename("$th.new.$ext", "$th.$ext"))           { $fail = 6; }
		}
	}
	$ROBJ->file_delete($tmp);
	if ($fail) { unlink("$th.poster.new.$ext", "$th.new.$ext"); }
	return $fail || 0;
}

#-------------------------------------------------------------------------------
# ●サムネイルを作る動画の一覧
#-------------------------------------------------------------------------------
# アップデート処理の後に、ブラウザーでまとめて作るときに使う。ゴミ箱は除く
# 次の動画を返す
#   サムネイルの無い動画
#   記事用のサムネイルが今の大きさ（$VIDEO_POSTER_MAX）より大きい動画（4.18より前に作ったもの）
#   記事用のサムネイルが、v4.19のアップデート処理（video_poster_time）より前に作ったものの動画
#   （4.19より前は、ブラウザーが品質0.85のJPEGで作っていた）
#   AVIFを書けるサーバーで、記事用のサムネイルがJPEGの動画（4.25より前に作ったもの）
#   （JPEGからAVIFに変換すると圧縮が2回になるので、動画から作り直す）
# ret : [ { folder => 'posts/2026/', name => 'clip.mp4' }, ... ]
#
sub load_videos_need_thumbnail {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $base = $self->blogimg_dir();
	my $since = $self->{sys}->{video_poster_time};
	my $ext  = $self->thumbnail_ext('a.mp4');	# 動画のサムネイルの今の形式
	require Satsuki::ImageFormat;

	my @ary;
	my @dirs = ('');
	while(@dirs) {
		my $folder = shift(@dirs);
		my $dir    = $base . $folder;
		foreach(@{ $ROBJ->search_files($dir, {dir=>1}) }) {
			if (substr($_,-1) eq '/') {
				push(@dirs, "$folder$_");
				next;
			}
			if (!$self->is_video($_)) { next; }
			my $poster = $self->poster_file($dir, $_);
			if ($poster && $poster !~ /\.$ext$/) { $poster = ''; }	# 今の形式でない
			if ($poster && (!$since || $since <= (stat($poster))[9])) {
				my ($w, $h) = Satsuki::ImageFormat::get_size($poster);
				if ($w && $w <= $VIDEO_POSTER_MAX && $h <= $VIDEO_POSTER_MAX) { next; }
			}
			push(@ary, { folder => "$folder", name => "$_" });
		}
	}
	return \@ary;
}

#-------------------------------------------------------------------------------
# ●フォルダの作成
#-------------------------------------------------------------------------------
sub create_folder {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $name = $self->chop_slash( $form->{name} );
	if ( !$self->check_file_name($name) ) { return -1; }
	if ( !$self->media_check_ext($name) ) { return -1; }

	my $r = $ROBJ->mkdir("$dir$name") ? 0 : 1;
	$ROBJ->mkdir("$dir$name/.thumbnail");

	return $r;
}

#-------------------------------------------------------------------------------
# ●フォルダ名の変更
#-------------------------------------------------------------------------------
sub rename_folder {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $old  = $self->chop_slash( $form->{old}  );
	my $name = $self->chop_slash( $form->{name} );
	if ( !$self->check_file_name($old ) ) { return -2; }
	if ( !$self->check_file_name($name) ) { return -1; }
	if ( !$self->media_check_ext($name) ) { return -1; }

	return rename("$dir$old", "$dir$name") ? 0 : 1;
}

#-------------------------------------------------------------------------------
# ●ファイルの移動
#-------------------------------------------------------------------------------
sub move_files {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $from = $self->image_folder_to_dir( $form->{from} ); # 値check付
	my $to   = $self->image_folder_to_dir( $form->{to}   ); # 値check付

	my $src_trash = ($form->{from} =~ m|^\.trashbox/|);	# 移動元がゴミ箱？
	my $des_trash = ($form->{to}   =~ m|^\.trashbox/|);	# 移動先がゴミ箱？
	if ($src_trash && $des_trash) {
		# ゴミ箱内移動ならファイル名に日付付加しない
		$src_trash = $des_trash = 0;
	}

	my $files = $form->{file_ary} || [];
	my @fail;
	my $tm = $ROBJ->print_tmf("%Y%m%d-%H%M%S");
	foreach(@$files) {
		if ( !$self->check_file_name($_) ) {
			push(@fail, $_);
			next;
		}
		my $src = $_;
		my $des = $_;
		#---------------------------------
		# ゴミ箱にファイルを移動
		#---------------------------------
		if ($des_trash && !-d "$from$_") {
			my $x = rindex($des, '.');
			if ($x > 0) {
				$des = substr($des, 0, $x) . ".#$tm" . substr($des, $x);
			} else {
				$des .= ".#$tm";
			}
		}
		#---------------------------------
		# ゴミ箱からファイルを移動
		#---------------------------------
		if ($src_trash && !-d "$from$_") {
			$self->remove_trash_timestamp($des);
		}
		#---------------------------------
		# 許可していない拡張子
		#---------------------------------
		if (!$self->media_check_ext($des)) {
			push(@fail, $_);
			next;
		}
		#---------------------------------
		# 同じファイル名が存在する
		#---------------------------------
		if (-e "$to$des") {
			push(@fail, $_);
			next;
		}
		#---------------------------------
		# リネーム（移動）
		#---------------------------------
		if (!rename("$from$src", "$to$des")) {
			push(@fail, $_);
			next;
		}

		# ファイルを移動した場合、サムネイルも移動
		if (-d "$to$des") { next; }
		# $ROBJ->mkdir("${to}.thumbnail/");
		$self->rename_thumbnail($from, $src, $to, $des);	# 移動失敗時はサムネイル消去
		# 動画の記事用のサムネイル
		if ($self->poster_file($from, $src)) {
			$ROBJ->mkdir("${to}.thumbnail/");
			$self->rename_thumbnail($from, $src, $to, $des, '.poster');
		}
	}
	my $f = $#fail+1;
	return wantarray ? ($f, \@fail) : $f;
}

sub remove_trash_timestamp {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/(.*)\.#\d\d\d\d\d\d\d\d-\d\d\d\d\d\d/$1/;
	}
}

#-------------------------------------------------------------------------------
# ●ファイル名の変更
#-------------------------------------------------------------------------------
sub rename_file {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $old  = $form->{old};
	my $name = $form->{name};
	if ( !$self->check_file_name($old ) ) { return -2; }
	if ( !$self->check_file_name($name) ) { return -1; }
	if ( !$self->media_check_ext($name) ) { return -1; }
	if (-e "$dir$name") { return 1; }	# 同じ名前のファイルを上書きしない

	my $r  = rename("$dir$old", "$dir$name");
	my $r2;
	# 画像ファイルのみ移動を試みる。本体を移せなければ、サムネイルも動かさない
	if ($r && $self->is_image($old) && $self->is_image($name)) {
		$r2 = $self->rename_thumbnail($dir, $old, $dir, $name);
	}
	# 動画のサムネイル（ブラウザーで作ったもの）は、動画のままなら移す。動画でなくなれば消す
	if ($r && $self->poster_file($dir, $old)) {
		if ($self->is_video($name) && $self->rename_thumbnail($dir, $old, $dir, $name, '.poster')) {
			$r2 = $self->rename_thumbnail($dir, $old, $dir, $name);
		} else {
			$self->delete_thumbnail( $dir, $old, '.poster' );
		}
	}

	if ($r && !$r2) {
		# サムネイルだけ失敗時、古いサムネイルの削除
		$self->delete_thumbnail( $dir, $old );
		# 新しいサムネイル生成
		$self->make_thumbnail( $dir, [$name], {
			force => 1
		});
	}

	return ($r ? 0 : 1);
}

#-------------------------------------------------------------------------------
# ●ファイルを削除する
#-------------------------------------------------------------------------------
sub delete_files {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $files = $form->{file_ary} || [];
	my @fail;
	foreach(@$files) {
		my $file = $_;
		if ( !$self->check_file_name($file) ) {
			push(@fail, $_);
			next;
		}
		my $r = unlink("$dir$file");
		if (!$r) {
			push(@fail, $_);
			next;
		}
		$self->delete_thumbnail( $dir, $file );
		$self->delete_thumbnail( $dir, $file, '.poster' );
	}
	my $f = $#fail + 1;
	return wantarray ? ($f, \@fail) : $f;
}

#-------------------------------------------------------------------------------
# ●フォルダを削除する
#-------------------------------------------------------------------------------
sub delete_folder {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $folder = $form->{folder};
	if ($folder eq '' || $folder eq '/') {
		return -1;
	}

	my $dir = $self->image_folder_to_dir( $folder );
	# 「..」などを取り除いた結果、メディア管理の根元を指すときは消さない
	if ($dir eq $self->blogimg_dir()) {
		return -1;
	}
	my $ret = $ROBJ->dir_delete($dir) ? 0 : 1;

	$ROBJ->mkdir($self->blogimg_dir() . '.trashbox/');
	return $ret;
}

#-------------------------------------------------------------------------------
# ■メディア管理関連サブルーチン
#-------------------------------------------------------------------------------
sub load_image_magick {
	eval { require Image::Magick; };
	if ($@) { return ; }
	return Image::Magick->new(@_);
}
# 中身の形式を確かめてから読み込む（Satsuki::ImageFormat）。画像の読み込みは必ずこれを使う
sub read_image {
	my $self = shift;
	require Satsuki::ImageFormat;
	return Satsuki::ImageFormat::read(@_);
}

#-------------------------------------------------------------------------------
# ○画像フォルダ→実ディレクトリ
#-------------------------------------------------------------------------------
sub image_folder_to_dir {
	my ($self, $folder) = @_;
	$folder =~ s|[\x00-\x1f]| |g;
	# 空の段と、「.」だけでできた段（.. など。最後に / が無くても）を取り除く
	my @dirs = grep { $_ ne '' && $_ !~ /^\.+$/ } split(m|/|, $folder);
	return $self->blogimg_dir() . join('', map { "$_/" } @dirs);
}

sub image_folder_to_dir_and_create {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $self->image_folder_to_dir(@_);
	my @dirs;
	while ($dir && !-d $dir) {
		unshift(@dirs, $dir);
		$dir =~ s|[^/]*/?$||;
	}
	foreach(@dirs) {
		$ROBJ->mkdir($_);
	}
	return $dir;
}

#-------------------------------------------------------------------------------
# ○画像フォルダ名/ファイル名チェック
#-------------------------------------------------------------------------------
sub check_file_name {
	my ($self, $file) = @_;
	if ($file eq '' || $file =~ /^\./) { return 0; }	# ng
	# 制御コードや / 等の使用不可文字
	if ($file =~ m![\x00-\x1f/:\\\*\?\"<>|]!) { return 0; }	# Windows準拠
	return 1;	# ok
}
# 最後のスラッシュを取り除く
sub chop_slash {
	my ($self, $folder) = @_;
	if (substr($folder,-1) eq '/') { chop($folder); }
	return $folder;
}

#-------------------------------------------------------------------------------
# ○画像ファイルか拡張子判定
#-------------------------------------------------------------------------------
sub is_image {
	my ($self, $f) = @_;
	$f =~ tr/A-Z/a-z/;
	return ($f =~ m/\.(\w+)$/ && $self->{media_image_ext}->{$1});
}

#-------------------------------------------------------------------------------
# ○動画ファイルか拡張子判定（サムネイルを作れる動画。Tag_audio.pmと同じ）
#-------------------------------------------------------------------------------
sub is_video {
	my ($self, $f) = @_;
	return ($f =~ m/\.(?:mp4|m4v|webm|ogv)$/i);
}

#-------------------------------------------------------------------------------
# ○許可拡張子か判定
#-------------------------------------------------------------------------------
sub media_check_ext {
	my ($self, $f) = @_;
	# if ($self->{trust_mode}) { return 1; }	## 危険すぎるので無効に
	$self->load_media_allow_ext();

	# 空の拡張子も確かめる（x.php. や x.php..png で確認が止まらないように）
	while($f =~ /^(.*)\.([^\.]*)$/) {
		$f = $1;
		if (!$self->media_check_ext_one($2)) { return 0; }
	}
	return 1;
}

sub media_check_ext_one {
	my ($self, $ext) = @_;
	$ext =~ tr/A-Z/a-z/;
	if ($self->{media_image_ext}->{$ext} || $self->{media_allow_ext}->{$ext}) { return 1; }

	# 特殊な文字を含むか、数字で始まる
	return ($ext =~ /[^\w]/ || $ext =~ /^\d/);
}

#-------------------------------------------------------------------------------
# ○その他拡張子のロード
#-------------------------------------------------------------------------------
sub load_media_allow_ext {
	my $self = shift;
	if (!$self->{media_allow_ext}->{'.'}) {
		$self->{ROBJ}->call('media/_load_extensions');
	}
	return $self->{media_allow_ext};
}

################################################################################
# ■設定関連
################################################################################
#-------------------------------------------------------------------------------
# ●ブログの設定変更（保存）
#-------------------------------------------------------------------------------
sub save_blogset {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $new_set = shift;

	# 権限確認
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 10; }
	my $blog   = $self->{blog};
	$self->update_blogset($blog, $new_set);

	return 0;
}

################################################################################
# ■記事やコメントの状態変更
################################################################################
#-------------------------------------------------------------------------------
# ●記事の表示状態変更、削除する
#-------------------------------------------------------------------------------
sub edit_articles {
	my ($self, $mode, $keylist, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	if (ref($keylist) ne 'ARRAY' || !@$keylist) {
		return (0,0);
	}
	$keylist = [ map { int($_) } @$keylist ];

	# IndexNow。公開をやめる記事（削除、非公開）は公開していたもの、公開する記事は下書きでないものを、変える前に集める
	my %indexnow;
	if ($mode ne 'tagset' && $self->{sys}->{indexnow}) {
		my $arts = $DB->select_match("art", 'pkey', $keylist, '*cols', ['pkey', 'enable', 'tm', 'link_key']);
		foreach(@$arts) {
			my $target = $mode eq 'enable' ? (!$_->{enable} && $_->{tm} ne '') : $_->{enable};
			if ($target) { $indexnow{ $_->{pkey} } = $_->{link_key}; }
		}
	}

	# 初期状態設定

	my $cnt = 0;
	my $com;
	my $event_name;
	my $cevent_name;
	if ($mode eq 'delete') {
		# 削除（ゴミ箱へ移動できた記事のみ削除する）
		$event_name  = 'ARTICLES_DELETE';
		$cevent_name = 'COMMENTS_DELETE';

		$keylist = $self->move_articles_to_trash($keylist);
		if (!@$keylist) {
			return wantarray ? (1,0) : 1;
		}
		$DB->delete_match("tagart", 'a_pkey', $keylist);
		# 更新履歴はゴミ箱から戻すときのために残す（ゴミ箱から削除するときに消す）
		$com = $DB->delete_match("com", 'a_pkey', $keylist);
		$cnt = $DB->delete_match("art", 'pkey', $keylist);

	} elsif ($mode eq 'tagset') {
		# タグの追加
		$event_name = 'ARTICLES_EDIT';
		my $append = $opt->{tag_append};
		my $arts = $DB->select_match("art", 'pkey', $keylist, '*cols', ['pkey', 'enable', 'tags'] );

		$DB->begin();
		foreach(@$arts) {
			my $pkey = $_->{pkey};
			my $t = ($append ? $_->{tags} . ',' : '') . $opt->{tags};
			my @tag  = $self->normalize_tag( $t );
			my $tags = join(",",@tag);
			my $r = $DB->update_match("art", { tags => $tags }, 'pkey', $pkey);
			if (!$r) { next; }

			# タグ情報書き換え
			$cnt += 1;
			$DB->delete_match("tagart", 'a_pkey', $pkey);
			my $t_pkeys = $self->regist_tags(\@tag);
			foreach my $t_pkey (@$t_pkeys) {
				$DB->insert("tagart", {
					'a_pkey'   => $pkey,
					'a_enable' => $_->{enable},
					't_pkey'   => $t_pkey
				});
			}
		}
		$DB->commit();

	} elsif ($mode eq 'enable') {
		# 表示に設定
		$event_name  = 'ARTICLES_EDIT';
		$cevent_name = 'COMMENTS_EDIT';
		$cnt = $DB->update_match("art",
			{ enable => 1 },
			'enable', 0,
			'-tm', '',	# 下書き記事は対象外
			'pkey', $keylist
		);
		$DB->update_match("tagart", {
			'a_enable' => 1
		}, 'a_pkey', $keylist);

		# 公開した記事の、承認済みのコメントを表示に戻す
		my $ary = $DB->select_match("art",
			'enable', 1,
			'-coms_all', 0,	# コメントがある
			'pkey', $keylist,
			'*cols', ['pkey']
		);
		my @pkeys = map { $_->{pkey} } @$ary;
		if (@pkeys) {
			$com = $DB->update_match("com",
				{ enable => 1 },
				'enable', 0,
				'-hold',  1,
				'a_pkey', \@pkeys
			);
			if ($com) {
				foreach(@pkeys) { $self->calc_comments($_); }
			}
		}

	} else {
		# 非表示に設定
		$event_name  = 'ARTICLES_EDIT';
		$cevent_name = 'COMMENTS_EDIT';
		$cnt = $DB->update_match("art",
			{ enable => 0 },
			'enable', 1,
			'-tm', '',	# 下書き記事は対象外
			'pkey', $keylist
		);
		$DB->update_match("tagart", {
			'a_enable' => 0
		}, 'a_pkey', $keylist);

		# 非公開にした記事にコメントがあれば
		my $ary = $DB->select_match("art",
			'enable', 0,
			'-coms', 0,	# 公開コメントがある
			'pkey', $keylist,
			'*cols', ['pkey']
		);
		my @pkeys = map { $_->{pkey} } @$ary;
		if (@pkeys) {
			$com = $DB->update_match("com",
				{ enable => 0 },
				'enable',  1,
				'a_pkey', \@pkeys
			);
			if ($com) {
				foreach(@pkeys) { $self->calc_comments($_); }
			}
		}
	}

	# イベント処理
	if ($cnt) {
		$keylist = ref($keylist) ? $keylist : [$keylist];
		$self->call_event($event_name,            $keylist, $cnt);
		$self->call_event('ARTICLE_STATE_CHANGE', $keylist);
		if ($com) {
			$self->call_event($cevent_name,           $keylist);
			$self->call_event('COMMENT_STATE_CHANGE', $keylist);
		}
		$self->call_event('ARTCOM_STATE_CHANGE',  $keylist);

		# 削除は、ゴミ箱へ移せた記事（$keylist）だけ
		my @urls;
		foreach(grep { exists $indexnow{$_} } @$keylist) {
			my $k = $indexnow{$_};
			$self->link_key_encode($k);
			push(@urls, $ROBJ->{ServerURL} . $self->{myself2} . $k);
		}
		$self->send_indexnow(\@urls);
	}

	return wantarray ? (0, $cnt) : 0;
}

################################################################################
# ■ゴミ箱
################################################################################
# _trash    : 記事テーブルと同じカラム + deleted_tm
# _trashcom : コメントテーブルと同じカラム
# pkeyは元の記事/コメントのpkeyをそのまま使う（pkeyは再利用されないので戻せる）
#-------------------------------------------------------------------------------
# ●記事をゴミ箱へ移動（記事データ自体は呼び出し元で削除する）
#-------------------------------------------------------------------------------
# ret: ゴミ箱へ移動できた記事のpkey配列
sub move_articles_to_trash {
	my ($self, $keylist) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $art_cols = $self->table_info_cols( $self->art_table_info() );
	my $com_cols = $self->table_info_cols( $self->com_table_info() );

	my $arts = $DB->select_match("art", 'pkey', $keylist, '*cols', $art_cols);
	my @moved;
	foreach my $art (@$arts) {
		my $pkey = $art->{pkey};
		# 前回戻すのに失敗した残骸があれば消しておく
		$DB->delete_match("trashcom", 'a_pkey', $pkey);
		$DB->delete_match("trash",    'pkey',   $pkey);

		$art->{deleted_tm} = $ROBJ->{TM};
		if (!$DB->insert("trash", $art)) {
			$ROBJ->message("Can't move to trash: %s", $art->{title});
			next;
		}
		my $coms = $DB->select_match("com", 'a_pkey', $pkey, '*cols', $com_cols);
		my $fail;
		foreach(@$coms) {
			if (!$DB->insert("trashcom", $_)) { $fail=1; last; }
		}
		if ($fail) {
			$DB->delete_match("trashcom", 'a_pkey', $pkey);
			$DB->delete_match("trash",    'pkey',   $pkey);
			$ROBJ->message("Can't move to trash: %s", $art->{title});
			next;
		}
		push(@moved, $pkey);
	}
	return \@moved;
}

#-------------------------------------------------------------------------------
# ●ゴミ箱の記事一覧
#-------------------------------------------------------------------------------
sub load_trash_list {
	my $self = shift;
	my $DB   = $self->{DB};
	if (!$self->{blog_admin}) { return []; }

	return $DB->select_match("trash", '*sort', '-deleted_tm',
		'*cols', [qw(pkey title tags ctype link_key yyyymmdd coms_all enable deleted_tm)]);
}

# 操作できるゴミ箱の記事に絞る
sub filter_trash_keys {
	my ($self, $keylist) = @_;
	if (ref($keylist) ne 'ARRAY') { $keylist = [ $keylist ]; }
	$keylist = [ grep { $_ > 0 } map { int($_) } @$keylist ];
	if (!@$keylist) { return []; }

	my $ary = $self->{DB}->select_match("trash", 'pkey', $keylist, '*cols', ['pkey']);
	return [ map { $_->{pkey} } @$ary ];
}

#-------------------------------------------------------------------------------
# ●ゴミ箱から戻す
#-------------------------------------------------------------------------------
sub restore_articles {
	my ($self, $keylist) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (!$self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	$keylist = $self->filter_trash_keys($keylist);
	if (!@$keylist) { return wantarray ? (0,0) : 0; }

	my $art_cols = $self->table_info_cols( $self->art_table_info() );
	my $com_cols = $self->table_info_cols( $self->com_table_info() );
	my $arts = $DB->select_match("trash", 'pkey', $keylist, '*cols', $art_cols);

	my @restored;
	my $com_cnt = 0;
	foreach my $art (@$arts) {
		my $pkey = $art->{pkey};
		if ($DB->select_match_limit1("art", 'pkey', $pkey, '*cols', ['pkey'])) {
			$ROBJ->message("Article already exists: %s", $art->{title});
			next;
		}
		# content keyが他の記事に使われていたら既定のkeyにする
		if ($DB->select_match_limit1("art", 'link_key', $art->{link_key}, '*cols', ['pkey'])) {
			$ROBJ->message("Content key '%s' is already used. Changed to '%s'.", $art->{link_key}, "0$pkey");
			$art->{link_key} = "0$pkey";
		}
		if (!$DB->insert("art", $art)) {
			$ROBJ->message("Can't restore: %s", $art->{title});
			next;
		}

		# コメント
		my $coms = $DB->select_match("trashcom", 'a_pkey', $pkey, '*cols', $com_cols);
		foreach(@$coms) {
			if ($DB->select_match_limit1("com", 'pkey', $_->{pkey}, '*cols', ['pkey'])) { next; }
			$DB->insert("com", $_) && $com_cnt++;
		}

		# タグ
		my @tag = $self->normalize_tag( $art->{tags} );
		if (@tag) {
			my $t_pkeys = $self->regist_tags(\@tag);
			foreach(ref($t_pkeys) ? @$t_pkeys : ()) {	# 失敗時は -1
				$DB->insert("tagart", {
					a_pkey   => $pkey,
					a_enable => $art->{enable},
					t_pkey   => $_
				});
			}
		}

		$DB->delete_match("trashcom", 'a_pkey', $pkey);
		$DB->delete_match("trash",    'pkey',   $pkey);
		push(@restored, $pkey);
	}

	# イベント処理（タグ一覧、固定ページの一覧、RSS等の再生成）
	if (@restored) {
		$self->call_event('ARTICLES_RESTORE',     \@restored);
		$self->call_event('ARTICLE_STATE_CHANGE', \@restored);
		if ($com_cnt) {
			$self->call_event('COMMENT_STATE_CHANGE', \@restored);
		}
		$self->call_event('ARTCOM_STATE_CHANGE',  \@restored);
	}
	my $cnt = $#restored + 1;
	return wantarray ? (0, $cnt) : 0;
}

#-------------------------------------------------------------------------------
# ●ゴミ箱から完全に削除
#-------------------------------------------------------------------------------
# $all : ゴミ箱を空にする（ブログ管理者のみ）
sub purge_trash {
	my ($self, $keylist, $all) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (!$self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	if ($all) {
		if (!$self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }
		my $ary = $DB->select_match("trash", '*cols', ['pkey']);
		$keylist = [ map { $_->{pkey} } @$ary ];
	} else {
		$keylist = $self->filter_trash_keys($keylist);
	}
	if (!@$keylist) { return wantarray ? (0,0) : 0; }

	$DB->delete_match("rev",      'a_pkey', $keylist);
	$DB->delete_match("lastrev",  'a_pkey', $keylist);
	$DB->delete_match("trashcom", 'a_pkey', $keylist);
	my $cnt = $DB->delete_match("trash", 'pkey', $keylist);
	return wantarray ? (0, $cnt) : 0;
}

#-------------------------------------------------------------------------------
# ●コメントの表示状態変更、または削除
#-------------------------------------------------------------------------------
sub edit_comment {
	my ($self, $mode, $keylist) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 5; }

	if (ref($keylist) ne 'ARRAY' || !@$keylist) {
		return (0,0);
	}
	$keylist = [ map { int($_) } @$keylist ];

	# 該当する記事のリスト
	my $ary = $DB->select_by_group("com",{
		group_by => 'a_pkey',
		match => { pkey => $keylist }
	});
	my @a_pkeys = map { $_->{a_pkey} } @$ary;

	# 削除
	my $cnt;
	my $event_name;
	if ($mode eq 'delete') {
		$event_name = 'COMMENTS_DELETE';
		$cnt = $DB->delete_match("com", 'pkey', $keylist);

	} elsif ($mode eq 'enable') {
		# 承認する。記事が非公開なら、記事を公開したときに表示する
		$event_name = 'COMMENTS_EDIT';
		$cnt = $DB->update_match("com",
			{ hold => 0 },
			'hold', 1,
			'pkey', $keylist
		);

		my $ary = $DB->select_match("art",
			'pkey', \@a_pkeys,
			'*cols', ['pkey', 'enable']
		);
		my @exlist;
		foreach(@$ary) {
			if ($_->{enable}) { next; }
			push(@exlist, $_->{pkey});
		}
		my $shown = $DB->update_match("com",
			{ enable => 1 },
			'enable', 0,
			'pkey', $keylist,
			'-a_pkey', \@exlist	# not match
		);
		# 承認済みで表示していなかったもの（holdが無い頃のデータ）も数える
		if ($cnt < $shown) { $cnt = $shown; }
	} else {
		# 承認を取り消す
		$event_name = 'COMMENTS_EDIT';
		$cnt = $DB->update_match("com",
			{ hold => 1 },
			'-hold', 1,
			'pkey', $keylist
		);
		my $hidden = $DB->update_match("com",
			{ enable => 0 },
			'enable',  1,
			'pkey', $keylist
		);
		if ($cnt < $hidden) { $cnt = $hidden; }
	}

	# イベント処理
	if ($cnt) {
		foreach( @a_pkeys ) {
			$self->calc_comments($_);
		}
		$keylist = ref($keylist) ? $keylist : [$keylist];
		$self->call_event($event_name,            \@a_pkeys, $keylist, $cnt);
		$self->call_event('COMMENT_STATE_CHANGE', \@a_pkeys, $keylist);
		$self->call_event('ARTCOM_STATE_CHANGE',  \@a_pkeys, $keylist);
	}

	return wantarray ? (0, $cnt) : 0;
}

################################################################################
# ■タグの編集処理
################################################################################
#-------------------------------------------------------------------------------
# ●タグの編集
#-------------------------------------------------------------------------------
sub tag_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $joins = $form->{join_ary} || [];
	my $dels  = $form->{del_ary}  || [];
	my $edits = $form->{tag_ary};

	# タグリスト
	my @tags;
	{
		my $ary = $DB->select_match("tag");
		foreach(@$ary) {
			$tags[ $_->{pkey} ] = $_;
		}
	}

	my %e_art;	# 編集したarticleのpkey
	# 中で e_art を参照しているので順番を逆にしてはいけない。
	foreach(@$joins) {
		my ($master, @slaves) = split(',',$_);
		my $ta = $DB->select_match("tagart", 't_pkey', \@slaves, '*cols', ['a_pkey', 'a_enable'] );
		$DB->delete_match("tagart", 't_pkey', \@slaves);
		$DB->delete_match("tag",    'pkey'  , \@slaves);
		foreach(@$ta) {
			if ($e_art{ $_->{a_pkey} }) { next; }
			my $r = $DB->insert("tagart", {
				a_pkey => $_->{a_pkey},
				t_pkey => $master,
				a_enable => $_->{a_enable}
			});
			$e_art{ $_->{a_pkey} } = 1;
		}
	}
	# タグの削除
	if(@$dels) {
		my $ta = $DB->select_match("tagart", 't_pkey', $dels, '*cols', 'a_pkey' );
		$DB->delete_match("tagart", 't_pkey', $dels);
		$DB->delete_match("tag"   ,   'pkey', $dels);
		foreach(@$ta) {
			$e_art{ $_->{a_pkey} } = 1;
		}
	}
	# タグの編集
	foreach(@$edits) {
		my ($pkey,$upnode,$priority,$name) = split(',',$_,4);
		$ROBJ->normalize_string($name);
		$ROBJ->tag_escape_amp($name);
		if ($name =~ /::/ || $name =~ /,/ || $name eq '') {
			$ROBJ->message("Tag name error '%s'", $name);
			next;
		}
		if($upnode) {
			$name = $tags[ $upnode ]->{name} . '::' . $name;
		}
		my $org = $tags[ $pkey ];
		my $ef_art;
		if ($upnode != $org->{upnode} || $name ne $org->{name}) {
			$ef_art = 1;	# 記事に影響あり
		} elsif ($priority == $org->{priority}) {
			next;		# 変更なし
		}
		my %h = (
			upnode   => ($upnode==0 ? undef : $upnode),
			priority => $priority,
			name     => $name
		);
		my $r = $DB->update_match("tag", \%h, 'pkey', $pkey);
		if (!$r) {	# 失敗
			if ($name ne $org->{name}) {
				$ROBJ->message("Tag edit error '%s' to '%s' (same tag name exist?)", $org->{name}, $name);
			} else {
				$ROBJ->message("Tag edit error '%s'", $org->{name});
			}
			next;
		}

		$h{pkey} = $pkey;
		$tags[ $pkey ] = \%h;

		# 記事の変更予約処理
		if (!$ef_art) { next; }
		my $ta = $DB->select_match("tagart", 't_pkey', $pkey);
		foreach(@$ta) {
			$e_art{ $_->{a_pkey} } = 1;
		}
	}

	# 変更があったarticleのタグ情報を書き換える
	foreach my $a_pkey (keys(%e_art)) {
		my $ta = $DB->select_match("tagart", 'a_pkey', $a_pkey, '*cols', 't_pkey');
		my @t_pkeys = map { $_->{t_pkey} } @$ta;

		# upnodeのいずれかのタグを含まないかチェック
		my %h;
		foreach(@t_pkeys) {
			my $up = $tags[$_]->{upnode};
			while($up) {
				$h{$up} = 1;
				$up = $tags[$up]->{upnode};
			}
		}
		my @tag;
		my @dels;
		foreach(@t_pkeys) {
			if ($h{$_}) {
				push(@dels, $_);
				next;
			}
			push(@tag, $tags[ $_ ]->{name});
		}
		# ツリー組み換えにより重複したタグを削除
		$DB->delete_match("tagart", 'a_pkey', $a_pkey, 't_pkey', \@dels);

		# 新しいタグ情報に書き換え
		my $tag = join(',', @tag);
		$DB->update_match("art", {tags => $tag}, 'pkey', $a_pkey);
	}
	if (%e_art) {
		my $artkeys = keys(%e_art);
		$self->call_event('ARTICLE_STATE_CHANGE', $artkeys);
	}
	$self->update_taglist();

	return 0;
}

################################################################################
# ■固定ページの編集処理
################################################################################
#-------------------------------------------------------------------------------
# ●固定ページの編集
#-------------------------------------------------------------------------------
sub contents_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	# タグリスト
	my %cons;
	{
		my $ary = $DB->select_match("art",
			'enable', 1,
			'-ctype', '',
			'*cols', ['pkey', 'title', 'link_key', 'priority', 'upnode', 'coms_all']
		);
		%cons = map { $_->{pkey} => $_ } @$ary;
	}

	# タグの編集
	my $edits = $form->{contents_txt_ary};
	my $com_edit;
	foreach(@$edits) {
		my ($pkey,$upnode,$priority,$link_key) = split(',',$_,4);
		$ROBJ->normalize_string($link_key);
		if ($link_key =~ /^[\"\',]/ || $link_key =~ /^\s*$/ || $link_key =~ m|^[\d&]| || $self->check_link_key_path($link_key)) {
			$link_key = '';
		}
		my $org = $cons{ $pkey };
		my %h;
		if ($upnode != $org->{upnode} && ($cons{$upnode} || $upnode==0)) {
			$h{upnode} = $upnode;
		}
		if ($link_key ne '' && $link_key ne $org->{link_key}) {
			$h{link_key} = $link_key;
		}
		if ($priority != $org->{priority}) {
			$h{priority} = $priority;
		}
		if (!%h) { next; }

		$DB->update_match("art", \%h, 'pkey', $pkey);
		if (exists($h{link_key}) && $cons{$pkey}->{coms_all}) {
			my $elkey = $h{link_key};
			$self->link_key_encode($elkey);
			my $r = $DB->update_match("com", { a_elink_key=>$elkey }, 'a_pkey', $pkey);
			if ($r) { $com_edit=1; }
		}
	}

	# イベント処理
	my $a_pkeys = keys(%cons);
	$self->call_event('ARTICLE_STATE_CHANGE', $a_pkeys);
	if ($com_edit) {
		$self->call_event('COMMENT_STATE_CHANGE', $a_pkeys);
	}
	$self->call_event('ARTCOM_STATE_CHANGE', $a_pkeys);

	return 0;
}


1;
