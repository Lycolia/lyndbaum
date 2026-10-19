package Lyndbaum::Controller::AdminUpload;
# 添付ファイルのアップロード（docs/admin.md の「ファイルのアップロード」）
#   POST /admin/upload   multipart/form-data。file（複数）、folder、csrf_token
#   サムネイルの大きさは、編集の設定の thumbnail_size だけで決める（変えたら tools/rebuild-thumbnails.pl で作り直す）
#   応答は JSON { files => [ { name, url, tag }, ... ], errors => [ 理由, ... ] }
#   編集の画面（pub/assets/js/admin-article.js）が送り、返った記法を本文に入れる。置くのは今の年月のフォルダ
#   メディアの画面（pub/assets/js/admin-media.js）は、開いているフォルダ（folder）へ置く
use strict;
use warnings;
use utf8;

use Lyndbaum::Controller::Admin;
use Lyndbaum::Media;
use Lyndbaum::Response;
use Lyndbaum::Upload;

sub upload {
	my ($class, $app, $req) = @_;
	# 大きすぎる本文は読まないので、CSRFトークンも読めない。ログインしているかだけを先に見て、理由を返す
	return $class->_json($app, 413, errors => [ sprintf 'ファイルが大きすぎます（%dMBまで）。', $app->upload_max_bytes / 1024 / 1024 ])
		if $app->admin_session($req) && $req->body_too_large;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;

	my @uploads = $req->uploads('file');
	return $class->_json($app, 400, errors => ['ファイルを選んでください。']) if !@uploads;
	my $size = $app->settings->{thumbnail_size};

	# 置くフォルダ。省けば今の年月のフォルダ
	my $folder = $req->body_param('folder') // '';
	if ($folder ne '') {
		$folder = Lyndbaum::Media->clean_folder($folder);
		return $class->_json($app, 400, errors => ['置くフォルダがありません。']) if !defined $folder || !$app->media->has_folder($folder);
	}

	my (@files, @errors);
	my $dir = $app->attachment_dir;
	for my $upload (@uploads) {
		my $file = eval {
			Lyndbaum::Upload->save(dir => $dir, filename => $upload->{filename}, data => $upload->{data}, thumbnail_size => $size,
				$folder ne '' ? (folder => $folder) : ());
		};
		if (!$file) {
			(my $error = $@) =~ s/\n\z//;
			push @errors, $error;
			next;
		}
		push @files, {
			name => $file->{name},
			url  => $app->url->attachment("$file->{folder}$file->{name}"),
			tag  => Lyndbaum::Upload->tag_of($file),
		};
	}
	return $class->_json($app, @files ? 200 : 400, files => \@files, errors => \@errors);
}

sub _json {
	my ($class, $app, $status, %data) = @_;
	return Lyndbaum::App::admin_headers(Lyndbaum::Response->json({ files => [], errors => [], %data }, status => $status));
}

1;
