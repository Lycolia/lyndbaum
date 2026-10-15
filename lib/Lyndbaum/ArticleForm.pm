package Lyndbaum::ArticleForm;
# 管理画面の記事の編集フォーム（docs/admin.md の「記事の管理」）
#   フォームの値を読んで確かめ、保存する値（Lyndbaum::Model::Article->save に渡すもの）にする
use strict;
use warnings;
use utf8;

use Lyndbaum::BlogSettings;
use Lyndbaum::Date qw(parse_input_date);

my $MAX_TITLE = 200;

# フォームを読む
#   %args
#     values      $values->($name) はその名前のフォームの値をすべて返す関数
#     tag_exists  $tag_exists->(@names) は、その名前の列（親から順）のタグがあれば真を返す関数
#     page        真ならコンテンツページ（親、名前、並び順の欄を読む）
#   戻り値は（値, 理由の一覧）。理由は { key => 欄の名前, message => 文 }
#   値
#     title, body_src  題名は前後の空白を除く。本文は改行を LF にそろえる（前後の空白は残す）
#     tags            タグの名前の列の配列 [ [親, 子], ... ]（重なりは除く）
#     tag_chips       フォームに戻すタグ [ { name => '親::子', new => 新しいタグか }, ... ]
#     status          draft か published
#     published_at    UNIX 時刻。空なら undef
#     published_text  書いたままの公開日時の欄
#     comments_open   0 か 1
#     keep_updated    更新日時を変えないなら 1
#     og_image_mode   OGP の画像の決め方（auto、chosen、none。docs/ogp.md）
#     og_image        chosen のときの画像（添付ファイルの中のパス「フォルダ/名前」）。ほかのときは空
#     digest          フォームを開いたときの記事の中身の要約（ほかの画面で保存されていないかを見るため）
#     kind            page か post（新しい記事のとき）
#   コンテンツページのとき
#     parent_id       親のページのID。親が無ければ undef
#     page_name       名前（slug の最後の区切り。slug は「親の slug/名前」になる）
#     sort_order      同じ親の中での並び順。空なら undef（同じ親のままなら今の値、親を変えたらいちばん後ろ）
#     sort_text       書いたままの並び順の欄
#
# タグ
#   tag      今あるタグ（「親::子」）。無いタグなら保存しない
#   new_tag  新しく作るタグ。候補の「新規タグとして追加」を選んだときだけ送られる
#   書き間違いでタグが増えないよう、新しいタグは new_tag で明示されたときだけ作る
sub parse {
	my ($class, %args) = @_;
	my $values = $args{values};
	my $first  = sub { ($values->($_[0]))[0] };
	my (%v, @errors);
	my $error = sub { push @errors, { key => $_[0], message => $_[1] } };
	my $trim  = sub { my $s = $first->($_[0]) // ''; $s =~ s/\A\s+|\s+\z//g; $s };

	$v{title} = $trim->('title');
	$error->(title => '題名を書いてください。') if $v{title} eq '';
	$error->(title => "題名は${MAX_TITLE}文字までにしてください。") if length $v{title} > $MAX_TITLE;

	($v{body_src} = $first->('body') // '') =~ s/\r\n?/\n/g;

	my %seen;
	for my $kind (qw(tag new_tag)) {
		for my $full (grep { $_ ne '' } map { s/\A\s+|\s+\z//gr } $values->($kind)) {
			my @names = map { s/\A\s+|\s+\z//gr } split /::/, $full, -1;
			my $name  = join '::', @names;
			next if $seen{$name}++;
			push @{ $v{tag_chips} }, { name => $name, new => $kind eq 'new_tag' ? 1 : 0 };
			if ((grep { $_ eq "" } @names) || $name =~ /,/) {
				$error->(tags => "タグ「$full」の書き方が正しくありません。親と子は「::」で区切ります（例：料理::調味料）。「,」は使えません。");
			} elsif ($kind eq 'tag' && !$args{tag_exists}->(@names)) {
				$error->(tags => "タグ「$name」はありません。新しいタグにするときは、候補の「新規タグとして追加」を選んでください。");
			} else {
				push @{ $v{tags} }, \@names;
			}
		}
	}
	$v{tags} //= [];
	$v{tag_chips} //= [];

	$v{status} = ($first->('status') // '') eq 'published' ? 'published' : 'draft';

	$v{published_text} = $trim->('published_at');
	if ($v{published_text} ne '') {
		$v{published_at} = parse_input_date($v{published_text});
		$error->(published_at => '公開日時の書き方が正しくありません（例：2026-10-14T21:05）。') if !defined $v{published_at};
	}

	$v{comments_open} = ($first->('comments_open') // '') eq '1' ? 1 : 0;

	my $mode = $first->('og_image_mode') // '';
	$v{og_image_mode} = $mode =~ /\A(?:auto|chosen|none)\z/ ? $mode : 'auto';
	$v{og_image} = $trim->('og_image');
	if ($v{og_image_mode} eq 'chosen') {
		$error->(og_image => 'OGPの画像を選んでください。') if $v{og_image} eq '';
		$error->(og_image => 'OGPの画像のパスが正しくありません。') if $v{og_image} ne '' && !Lyndbaum::BlogSettings::valid_attachment($v{og_image});
	} else {
		$v{og_image} = '';
	}
	$v{keep_updated}  = ($first->('keep_updated') // '') eq '1' ? 1 : 0;
	$v{kind} = $args{page} ? 'page' : 'post';
	if ($args{page}) {
		my $parent = $first->('parent_id') // '';
		$v{parent_id} = $parent =~ /\A[1-9]\d*\z/ ? $parent : undef;
		$v{page_name} = $trim->('page_name');
		if ($v{page_name} eq '') {
			$error->(page_name => 'ページの名前を書いてください（URLになります）。');
		} elsif ($v{page_name} =~ m{[/\\?#%\s\x00-\x1F\x7F]} || $v{page_name} =~ /\A\.\.?\z/) {
			$error->(page_name => 'ページの名前に、空白と / \\ ? # % は使えません。「.」と「..」も使えません。');
		} elsif (length $v{page_name} > 100) {
			$error->(page_name => 'ページの名前は100文字までにしてください。');
		}
		$v{sort_text} = $trim->('sort_order');
		if ($v{sort_text} ne '') {
			$v{sort_text} =~ /\A-?\d{1,9}\z/ ? ($v{sort_order} = $v{sort_text} + 0)
				: $error->(sort_order => '並び順は整数で書いてください。');
		}
	}

	my $digest = $first->('digest') // '';
	$v{digest} = $digest =~ /\A[0-9a-f]{64}\z/ ? $digest : undef;
	return (\%v, \@errors);
}

1;
