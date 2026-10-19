package Lyndbaum::ArticleForm;
# 管理画面の記事の編集フォーム（docs/admin.md の「記事の管理」）
#   フォームの値を読んで確かめ、保存する値（Lyndbaum::Model::Article->save に渡すもの）にする
use strict;
use warnings;
use utf8;

use Lyndbaum::BlogSettings;
use Lyndbaum::Date qw(parse_input_date);
use Lyndbaum::Model::Article;

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
#     eyecatch        選んだアイキャッチ（添付ファイルの中のパス「フォルダ/名前」）。選んでいなければ空（docs/ogp.md）
#     digest          フォームを開いたときの記事の中身の要約（ほかの画面で保存されていないかを見るため）
#     kind            page か post（新しい記事のとき）
#   コンテンツページのとき
#     parent_id       親のページのID。親が無ければ undef
#     page_name       名前（slug の最後の区切り。slug は「親の slug/名前」になる）。題名と同じにする
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

	$v{eyecatch} = $trim->('eyecatch');
	$error->(eyecatch => 'アイキャッチのパスが正しくありません。') if $v{eyecatch} ne '' && !Lyndbaum::BlogSettings::valid_attachment($v{eyecatch});
	$v{keep_updated}  = ($first->('keep_updated') // '') eq '1' ? 1 : 0;
	$v{kind} = $args{page} ? 'page' : 'post';
	if ($args{page}) {
		my $parent = $first->('parent_id') // '';
		$v{parent_id} = $parent =~ /\A[1-9]\d*\z/ ? $parent : undef;
		# 題名がそのままURLになる。親の無いページだけの決まり（0で始めないなど）は、保存のときに確かめる
		$v{page_name} = $v{title};
		$error->(title => $_) for $v{title} eq '' ? () : Lyndbaum::Model::Article->page_name_errors($v{title});
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
