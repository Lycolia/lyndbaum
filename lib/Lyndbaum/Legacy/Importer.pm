package Lyndbaum::Legacy::Importer;
# 旧システム（adiary）のテキストDBから、記事、タグ、コメント、ブログの設定を取り込む
#   対応は docs/db-schema.md の「旧データからの移行」を参照
#   取り込み先のDBは空であること（やり直すときはDBを作り直す）
use strict;
use warnings;
use utf8;
use feature 'current_sub';

use File::Spec;
use Time::Local qw(timegm);
use Lyndbaum::Legacy::TextDB;
use Lyndbaum::Parser;
use Lyndbaum::Parser::Markdown;
use Lyndbaum::Model::Article;
use Lyndbaum::Model::Comment;
use Lyndbaum::Model::Setting;
use Lyndbaum::Model::Tag;

# 旧システムの設定のキー => 新しい設定のキー
my %SETTING_KEYS = (
	blog_name       => 'blog_title',
	description_txt => 'blog_description',
	load_items      => 'per_page',
	rss_items_int   => 'feed_items',
);

# $data_dir は旧システムの data、$blog_id はブログのID（data/db/lycolia_art の lycolia の部分）
# %options
#   attachment_path  添付ファイルのURLの接頭辞。本文に書かれた旧システムのパスをこれに書き換える
# 取り込んだ件数を返す
sub run {
	my ($class, $dbh, $data_dir, $blog_id, %options) = @_;
	my $rewrite = $class->body_rewriter($blog_id, $options{attachment_path} // '/pub/attachments/');
	my $table = sub {
		Lyndbaum::Legacy::TextDB->read_table(File::Spec->catdir($data_dir, 'db', "${blog_id}_$_[0]"));
	};

	my $articles = $table->('art');
	my $tags     = $table->('tag');
	my $comments = $table->('com');
	my $setting  = Lyndbaum::Legacy::TextDB->read_record(
		File::Spec->catfile($data_dir, 'blog', $blog_id, 'setting.dat'));

	die "取り込み先のDBが空ではありません\n"
		if $dbh->selectrow_array('SELECT COUNT(*) FROM articles') || $dbh->selectrow_array('SELECT COUNT(*) FROM tags');

	my %result;
	$dbh->begin_work;
	eval {
		$result{tags}         = $class->_import_tags($dbh, $tags);
		($result{articles}, $result{rewritten}, $result{image_alts}, $result{heading_ids}, $result{article_links}, $result{lythumb})
			= $class->_import_articles($dbh, $articles, $rewrite);
		$result{article_tags} = $class->_import_article_tags($dbh, $articles, $tags);
		($result{comments}, $result{private_comments}) = $class->_import_comments($dbh, $comments);
		$result{settings}     = $class->_import_settings($dbh, $setting, $articles);
		# 取り込んだコメントは、新着として数えない
		Lyndbaum::Model::Comment->mark_seen($dbh);
		# 記事のIDを使い回さないよう、最後に使ったIDを記録する（Lyndbaum::Model::Article->next_id）
		$dbh->do(q{INSERT OR REPLACE INTO sequences (name, value) SELECT 'articles', COALESCE(MAX(id), 0) FROM articles});
		Lyndbaum::Model::Tag->rebuild_paths($dbh);
		$dbh->commit;
		1;
	} or do {
		my $error = $@;
		$dbh->rollback;
		die $error;
	};
	return \%result;
}

sub _import_tags {
	my ($class, $dbh, $tags) = @_;
	my $sth = $dbh->prepare('INSERT INTO tags (id, parent_id, name, sort_order) VALUES (?, ?, ?, ?)');

	# 親を先に入れるため、階層の浅い順に並べる（旧データのタグ名は親を含めた「A::B::C」の形）
	my $depth = sub { scalar(() = $_[0]{name} =~ /::/g) };
	for my $tag (sort { $depth->($a) <=> $depth->($b) || $a->{pkey} <=> $b->{pkey} } @$tags) {
		my ($leaf) = $tag->{name} =~ /([^:]+)\z/;
		$sth->execute(
			$tag->{pkey},
			_id_or_null($tag->{upnode}),
			$leaf,
			$tag->{priority} // 0,
		);
	}
	return scalar @$tags;
}

sub _import_articles {
	my ($class, $dbh, $articles, $rewrite) = @_;
	my $sth = $dbh->prepare(<<'SQL');
INSERT INTO articles (
    id, kind, slug, title, syntax, body_src, description, eyecatch, eyecatch_mode,
    status, published_at, created_at, updated_at, sort_order,
    comments_open
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
SQL

	my $page_slugs = $class->_page_slugs($articles);
	my %parent_of;
	my ($rewritten, $image_alts, $heading_ids, $article_links, $lythumb) = (0, 0, 0, 0, 0);
	for my $art (@$articles) {
		my $body = $art->{_text} // '';
		my $changed = eval { $rewrite->($body, $art->{parser} || 'markdown') } or die "記事 $art->{pkey}: $@";
		$rewritten++  if $changed->{paths} || $changed->{folders};
		$image_alts++ if $changed->{image_alts};
		$heading_ids += $changed->{heading_ids};
		$article_links += $changed->{article_links};
		$lythumb += $changed->{lythumb};
		my $kind = ($art->{ctype} // '') ne '' ? 'page' : 'post';
		my $slug = $kind eq 'page' ? $page_slugs->{ $art->{pkey} } : $art->{link_key};

		# 下書きには公開日時が無い。作成日時は tm（無ければ更新日時）
		my $published_at = _published_at($art);
		$sth->execute(
			$art->{pkey},
			$kind,
			$slug,
			$art->{title} // '',
			$art->{parser} || 'markdown',
			$body,
			$art->{description} // '',
			$class->rename_folder($art->{main_image} // ''),
			# アイキャッチが決まっていれば、その画像を出す（docs/ogp.md）。無ければ本文の最初の画像
			($art->{main_image} // '') ne '' ? 'chosen' : 'auto',
			$art->{enable} ? 'published' : 'draft',
			$published_at,
			$art->{tm} // $art->{update_tm},
			$art->{update_tm},
			$art->{priority} // 0,
			$art->{com_ok} ? 1 : 0,
		);
		my $parent = _id_or_null($art->{upnode});
		$parent_of{ $art->{pkey} } = $parent if defined $parent;
	}

	# 親が後に来ることもあるので、親子関係は全件入れてから付ける
	my $update = $dbh->prepare('UPDATE articles SET parent_id = ? WHERE id = ?');
	$update->execute($parent_of{$_}, $_) for sort { $a <=> $b } keys %parent_of;

	return (scalar @$articles, $rewritten, $image_alts, $heading_ids, $article_links, $lythumb);
}

# コンテンツページの slug を、管理画面で保存したときと同じ「親の slug/題名」にする（{ ID => slug }）
#   旧システムの link_key は題名と別に付けられたが、新しいシステムでは題名から作る（docs/compat-diffs.md）
#   題名がURLに使えないときや、ほかのページとぶつかるときは止める
sub _page_slugs {
	my ($class, $articles) = @_;
	my %page = map { $_->{pkey} => $_ } grep { ($_->{ctype} // '') ne '' } @$articles;
	for my $art (values %page) {
		my $key = $art->{link_key} // '';
		# 旧システムのリンク項目とトップページ指定は、実データに無いので扱わない。来たら止める
		die "記事 $art->{pkey}: リンク項目（$key）の取り込みは未対応です\n" if $key =~ m{\A(?:https?://|/)};
		die "記事 $art->{pkey}: トップページ指定（$key）の取り込みは未対応です\n" if $key =~ /\A(?:FrontPage|top|index)\z/;
	}

	my (%slug, %visiting);
	my $slug_of = sub {
		my ($id) = @_;
		return $slug{$id} if defined $slug{$id};
		my $art = $page{$id};
		die "記事 $id: 親子関係が輪になっています\n" if $visiting{$id}++;
		my $title = $art->{title} // '';
		$title =~ s/\A\s+|\s+\z//g;
		my $parent = _id_or_null($art->{upnode});
		die "記事 $id: 親のページ（$parent）がありません\n" if defined $parent && !$page{$parent};
		my @errors = $title eq '' ? ('題名がありません。') : Lyndbaum::Model::Article->page_name_errors($title, root => !defined $parent);
		die "記事 $id: 題名「$title」からページのURLを作れません：$errors[0]\n" if @errors;
		return $slug{$id} = defined $parent ? __SUB__->($parent) . "/$title" : $title;
	};
	my %owner;
	for my $id (sort { $a <=> $b } keys %page) {
		my $slug = $slug_of->($id);
		die "記事 $owner{$slug} と記事 $id のURL「/$slug」がぶつかります（同じ親の中に同じ題名のページがあります）\n"
			if defined $owner{$slug};
		$owner{$slug} = $id;
	}
	return \%slug;
}

# 取り込むときに本文を書き換える関数を返す（全記事の比較ツールでも使う）
#   関数は（本文, 記法）を受け取り、本文をその場で書き換え、書き換えた数を
#   { paths => …, folders => …, image_alts => …, article_links => …, lythumb => …, heading_ids => … } で返す
#   paths       添付ファイルの旧パス（https://ドメイン/pub/ブログID/image/… 、/pub/ブログID/image/… 、
#               pub/ブログID/image/…）を、添付ファイルのURLの接頭辞に書き換える
#   folders     添付ファイルのフォルダの名前を付け替える（adiary/ → posts/。%FOLDERS。@system/ はそのまま）。
#               画像と動画の記法（[image:S:adiary/2026/10/:a.png]）と、書き換えた後のURLの両方
#   image_alts  ファイル名と同じ代替テキストを、画像タグから落とす
#               （[image:S:dir/:a.jpg:a.jpg] → [image:S:dir/:a.jpg]。キャプションは残す）
#   article_links  記事へのリンクの先頭の / を外す（[文字](/0756) → [文字](0756)）。参照元（Lyndbaum::Backlinks）は
#               [文字](0756) の形だけを数えるので、それに揃える。リンク先のURLは変わらない
#   lythumb     生HTMLに書いた画像の拡大表示の属性を付け替える（data-fancybox= → data-lythumb=）。
#               data-fancybox は許可リスト（Lyndbaum::HTML）に無いので、そのままだと落ちて拡大表示されない
#   heading_ids 見出しに識別子（[#識別子]）を書き足す。識別子は、今の見出しのID（見出しの文字から作ったもの）
#               にする。見出しの文字を後で変えても、すでにあるリンクが壊れないように
#   コードの中は区別しない（実データのコードの中に、どれも無いことを確かめている）
my %FOLDERS = (adiary => 'posts');
my $FOLDER_RE = join '|', map { quotemeta } sort keys %FOLDERS;

# アイキャッチ（旧データの main_image。「adiary/2023/a.png」の形）のフォルダを付け替える
sub rename_folder {
	my ($class, $path) = @_;
	$path =~ s{\A($FOLDER_RE)/}{$FOLDERS{$1}/};
	return $path;
}

sub body_rewriter {
	my ($class, $blog_id, $attachment_path) = @_;
	my $re = qr{(?:https?://[A-Za-z0-9.-]+/|(?<![\w/.-])/?)pub/\Q$blog_id\E/image/};
	return sub {
		my %count = (paths => scalar($_[0] =~ s/$re/$attachment_path/g) || 0, image_alts => 0);
		$count{folders} = (scalar($_[0] =~ s{\Q$attachment_path\E($FOLDER_RE)/}{$attachment_path$FOLDERS{$1}/}g) || 0)
			+ (scalar($_[0] =~ s{(\[(?:image|file):[^:\]\n]*:)($FOLDER_RE)/}{$1$FOLDERS{$2}/}g) || 0);
		$_[0] =~ s{\[image:([^\]\n]*)\]}{
			my $tag = _drop_image_alt($1);
			$count{image_alts}++ if $tag ne $1;
			"[image:$tag]";
		}ge;
		$count{article_links} = scalar($_[0] =~ s{\]\(/(0[0-9]+)\)}{]($1)}g) || 0;
		$count{lythumb} = scalar($_[0] =~ s{(?<=\s)data-fancybox=}{data-lythumb=}g) || 0;
		$count{heading_ids} = ($_[1] // 'markdown') eq 'markdown' ? _freeze_heading_ids($_[0]) : 0;
		return \%count;
	};
}

# 見出しに、今の見出しのIDを識別子として書き足す。書き足した数を返す
#   書き足す前と後で、変換したHTMLがまったく同じになることも確かめる（違えば止める）
sub _freeze_heading_ids {
	my $before = Lyndbaum::Parser->parse('markdown', $_[0], sectioning => 1);
	my @ids = map { $_->{id} } @{ $before->{toc} };
	my ($text, $added) = Lyndbaum::Parser::Markdown->add_heading_ids($_[0], sub {
		my ($n) = @_;
		return $ids[$n] // die "見出しの数が合いません（" . ($n + 1) . " 番目の見出し）\n";
	});
	die "見出しに識別子を書き足すと、変換したHTMLが変わります\n"
		if Lyndbaum::Parser->parse('markdown', $text, sectioning => 1)->{html} ne $before->{html};
	$_[0] = $text;
	return $added;
}

# 画像タグの中身（サイズ:フォルダ/:ファイル名:代替テキスト(:#キャプション)）から、
# ファイル名と同じ代替テキストを落とす
sub _drop_image_alt {
	my ($inner) = @_;
	my ($size, $dir, $file, @rest) = split /:/, $inner, -1;
	return $inner if !defined $file;
	my @captions = grep { /\A#/ } @rest;
	my $alt = join ':', grep { !/\A#/ } @rest;
	return $inner if $alt ne $file;
	return join ':', $size, $dir, $file, @captions;
}

# 記事とタグの対応は、記事の tags 欄（親を含めたタグ名のカンマ区切り）から作る
#   旧システムの tagart には、タグを付け直す前の古い行や重複が残っているため使わない
sub _import_article_tags {
	my ($class, $dbh, $articles, $tags) = @_;
	my %tag_id = map { $_->{name} => $_->{pkey} } @$tags;
	my $sth = $dbh->prepare('INSERT OR IGNORE INTO article_tags (article_id, tag_id) VALUES (?, ?)');

	my $count = 0;
	for my $art (@$articles) {
		for my $name (grep { $_ ne '' } split /,/, $art->{tags} // '') {
			my $id = $tag_id{$name} // die "記事 $art->{pkey}: タグ「$name」がありません\n";
			$count += $sth->execute($art->{pkey}, $id);
		}
	}
	return $count;
}

# コメント。非公開コメント（hidden = 1）は取り込まない（公開できない内容を含むため）
#   取り込んだ件数と、取り込まなかった非公開コメントの件数を返す
#   最後に使った番号には非公開コメントの番号も含める（その番号を新しいコメントに使い回さないため）
sub _import_comments {
	my ($class, $dbh, $comments) = @_;
	my $sth = $dbh->prepare(<<'SQL');
INSERT INTO comments (id, article_id, num, status, by_admin, author_name, body, ip, host, user_agent, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
SQL
	my ($count, $private) = (0, 0);
	my %last_num;
	for my $com (@$comments) {
		$last_num{ $com->{a_pkey} } = $com->{num} if $com->{num} > ($last_num{ $com->{a_pkey} } // 0);
		if ($com->{hidden}) {
			$private++;
			next;
		}
		$sth->execute(
			$com->{pkey},
			$com->{a_pkey},
			$com->{num},
			$com->{enable} ? 'public' : 'held',
			($com->{id} // '') ne '' ? 1 : 0,
			_unescape_comment($com->{name}),
			_unescape_comment($com->{text}),
			$com->{ip} // '',
			$com->{host} // '',
			$com->{agent} // '',
			$com->{tm},
		);
		$count++;
	}
	my $update = $dbh->prepare('UPDATE articles SET last_comment_num = ? WHERE id = ?');
	$update->execute($last_num{$_}, $_) for sort { $a <=> $b } keys %last_num;
	return ($count, $private);
}

# 旧データのコメントはHTMLエスケープ済みで、改行は <br>。原文に戻す
my %UNESCAPE = ('&lt;' => '<', '&gt;' => '>', '&quot;' => '"', '&#39;' => "'", '&amp;' => '&');
sub _unescape_comment {
	my ($text) = @_;
	$text //= '';
	$text =~ s/<br>/\n/g;
	$text =~ s/(&(?:lt|gt|quot|#39|amp);)/$UNESCAPE{$1}/g;
	return $text;
}

#   書いた人の名前（blog_author。RSSに出す）は、旧システムでは記事ごとに持っていたので、
#   いちばん古い記事のものを使う（ユーザーは1人だけなので、どの記事も同じ）
sub _import_settings {
	my ($class, $dbh, $setting, $articles) = @_;
	my $count = 0;
	for my $old (sort keys %SETTING_KEYS) {
		next if !defined $setting->{$old} || $setting->{$old} eq '';
		Lyndbaum::Model::Setting->set($dbh, $SETTING_KEYS{$old}, $setting->{$old});
		$count++;
	}
	# ブログの画像（OGP で、記事に画像が無いときに出すもの）。旧システムのパス（pub/ブログID/image/…）を添付ファイルの中のパスにする
	if (($setting->{blog_image} // '') =~ m{\A/?pub/[^/]+/image/(.+)\z}) {
		Lyndbaum::Model::Setting->set($dbh, blog_image => $class->rename_folder($1));
		$count++;
	}
	my ($author) = grep { defined && $_ ne '' } map { $_->{name} } sort { $a->{pkey} <=> $b->{pkey} } @$articles;
	if (defined $author) {
		Lyndbaum::Model::Setting->set($dbh, blog_author => $author);
		$count++;
	}
	return $count;
}

# 公開日時。旧システムは記事の日付（yyyymmdd）を投稿日として表示する
#   tm は記事を作った日時で、ほかのシステムから移した記事では、移した日になっている
#   日付は yyyymmdd、時刻は tm の時刻（日本時間）にする。同じ日の記事の並びを保つため
sub _published_at {
	my ($art) = @_;
	my $tm = $art->{tm};
	return undef if !defined $tm || $tm eq '';
	my ($y, $m, $d) = ($art->{yyyymmdd} // '') =~ /\A(\d{4})(\d{2})(\d{2})\z/ or return $tm;
	my $JST = 9 * 60 * 60;
	my $time_of_day = ($tm + $JST) % 86400;
	return timegm(0, 0, 0, $d, $m - 1, $y) - $JST + $time_of_day;
}

# 旧データでは、親がないことを 0 か空で表す
sub _id_or_null {
	my ($id) = @_;
	return defined $id && $id ne '' && $id != 0 ? $id : undef;
}

1;
