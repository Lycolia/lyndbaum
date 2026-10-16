package Lyndbaum::Controller::AdminMedia;
# 管理画面のメディア（添付ファイルの一覧とゴミ箱。docs/admin.md の「メディア」）
#   /admin/media                       メディアの画面（中身は pub/assets/js/admin-media.js が JSON から組む）
#   /admin/media/folders               フォルダの木（JSON）
#   /admin/media/files?folder=F        フォルダの中のファイル（JSON）
#   /admin/media/usage?folder=F&name=N そのファイルを使っている記事（JSON）
#   POST /admin/media/trash            ゴミ箱へ移す（folder、name を複数）
#   /admin/media/trash                 ゴミ箱の中（JSON）
#   POST /admin/media/trash/restore    ゴミ箱から戻す（item を複数。「フォルダ/ゴミ箱での名前」）
#   POST /admin/media/trash/purge      ゴミ箱から完全に消す（item を複数。all=1 ならすべて）
#
# 編集の画面の「ファイル一覧から選択」も、同じ JSON を使う
use strict;
use warnings;
use utf8;

use JSON::PP ();
use Lyndbaum::Controller::Admin;
use Lyndbaum::Date qw(format_date);
use Lyndbaum::Media;
use Lyndbaum::Response;
use Lyndbaum::Upload;

sub page {
	my ($class, $app, $req) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	return $app->render_admin('admin_media', {
		title  => 'メディア',
		script => $app->url->static('js/admin-media.js'),
	}, session => $session);
}

sub folders {
	my ($class, $app, $req) = @_;
	return $class->_with_session($app, $req, sub {
		my $media = $app->media;
		my $current = Lyndbaum::Upload->folder_of(time);
		return { folders => $media->folders, current => $current };
	});
}

sub files {
	my ($class, $app, $req) = @_;
	return $class->_with_session($app, $req, sub {
		my $folder = Lyndbaum::Media->clean_folder($req->param('folder')) // return (400, { errors => ['フォルダが正しくありません。'] });
		return { folder => $folder, files => [ map { $class->_file($app, $folder, $_) } @{ $app->media->files($folder) } ] };
	});
}

sub usage {
	my ($class, $app, $req) = @_;
	return $class->_with_session($app, $req, sub {
		my $folder = Lyndbaum::Media->clean_folder($req->param('folder'));
		my $name   = $req->param('name');
		return (400, { errors => ['ファイルが正しくありません。'] }) if !defined $folder || !Lyndbaum::Media->valid_name($name);
		return { articles => [ map {
			+{ id => $_->{id} + 0, title => $_->{title}, trashed => defined $_->{deleted_at} ? JSON::PP::true : JSON::PP::false,
			   edit_url => $app->url->admin("articles/$_->{id}") }
		} @{ $app->media->usage($app->db, $folder, $name) } ] };
	});
}

sub trash {
	my ($class, $app, $req) = @_;
	return $class->_with_post($app, $req, sub {
		my $folder = Lyndbaum::Media->clean_folder($req->body_param('folder')) // return (400, { errors => ['フォルダが正しくありません。'] });
		my (@done, @errors);
		for my $name ($req->body_params('name')) {
			if (!Lyndbaum::Media->valid_name($name)) {
				push @errors, 'ファイルの名前が正しくありません。';
				next;
			}
			eval { $app->media->trash($folder, $name); push @done, $name; 1 } or push @errors, $@ =~ s/\n\z//r;
		}
		return { done => \@done, errors => \@errors };
	});
}

sub trash_list {
	my ($class, $app, $req) = @_;
	return $class->_with_session($app, $req, sub {
		my $trash = "$Lyndbaum::Media::TRASH/";
		return { files => [ map {
			+{
				%$_,
				item      => "$_->{folder}$_->{name}",
				size      => $_->{size} + 0,
				url       => $app->url->attachment("$trash$_->{folder}$_->{name}"),
				thumbnail => $_->{thumbnail} ? $app->url->attachment("$trash$_->{folder}.thumbnail/$_->{name}.jpg") : undef,
			}
		} @{ $app->media->trash_files } ] };
	});
}

sub restore {
	my ($class, $app, $req) = @_;
	return $class->_with_post($app, $req, sub {
		return $class->_each_item($req, sub { $app->media->restore(@_) });
	});
}

sub purge {
	my ($class, $app, $req) = @_;
	return $class->_with_post($app, $req, sub {
		my @items = ($req->body_param('all') // '') eq '1'
			? map { "$_->{folder}$_->{name}" } @{ $app->media->trash_files }
			: $req->body_params('item');
		return $class->_each_item($req, sub { $app->media->purge(@_) }, \@items);
	});
}

# item（「フォルダ/名前」）ごとに $code->(フォルダ, 名前) を呼ぶ
sub _each_item {
	my ($class, $req, $code, $items) = @_;
	my (@done, @errors);
	for my $item (@{ $items // [ $req->body_params('item') ] }) {
		my ($folder, $name) = $item =~ m{\A(.*/)?([^/]+)\z};
		$folder = Lyndbaum::Media->clean_folder($folder // '');
		if (!defined $folder || !Lyndbaum::Media->valid_name($name)) {
			push @errors, 'ファイルの名前が正しくありません。';
			next;
		}
		eval { $code->($folder, $name); push @done, $item; 1 } or push @errors, $@ =~ s/\n\z//r;
	}
	return { done => \@done, errors => \@errors };
}

# 一覧の1件（JSON）
sub _file {
	my ($class, $app, $folder, $file) = @_;
	my $path = "$folder$file->{name}";
	return {
		name      => $file->{name},
		folder    => $folder,
		kind      => $file->{kind},
		size      => $file->{size} + 0,
		mtime     => format_date($file->{mtime})->{datetime},
		url       => $app->url->attachment($path),
		thumbnail => $file->{thumbnail} ? $app->url->attachment("$folder.thumbnail/$file->{name}.jpg") : undef,
		# 本文に入れる記法。画像と動画のほかは、記法が無い
		tag       => $file->{kind} eq 'other' ? undef : Lyndbaum::Upload->tag_of({
			folder => $folder, name => $file->{name}, ext => $file->{ext},
			image => $file->{kind} eq 'image', thumbnail => $file->{thumbnail},
		}),
	};
}

# ログイン中なら $code->() の結果を JSON で返す。$code は（データ）か（ステータス, データ）を返す
sub _with_session {
	my ($class, $app, $req, $code) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req);
	return $res if !$session;
	return $class->_json($code->());
}

sub _with_post {
	my ($class, $app, $req, $code) = @_;
	my ($session, $res) = Lyndbaum::Controller::Admin->authorize($app, $req, post => 1);
	return $res if !$session;
	return $class->_json($code->());
}

sub _json {
	my ($class, @result) = @_;
	my ($status, $data) = @result == 2 ? @result : (200, $result[0]);
	return Lyndbaum::App::admin_headers(Lyndbaum::Response->json($data, status => $status));
}

1;
