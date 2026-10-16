package Lyndbaum::SidebarBoxes;
# サイドバーの自由欄（旧システムの「Information」や「カウンター」にあたるもの。docs/admin.md の「サイドバーの自由欄」）
#   題名と中身（HTML）の組を、並べた順に設定の sidebar_boxes に JSON で持つ
#   中身は書かれたまま保存し、出すときに Lyndbaum::HTML の許可リストに通す（許可リストを変えたら、そのまま効くように）
use strict;
use warnings;
use utf8;

use JSON::PP ();
use Lyndbaum::HTML qw(sanitize_html);

our $MAX_BOXES = 20;
our $MAX_TITLE = 100;
our $MAX_HTML  = 20000;

my $JSON = JSON::PP->new->canonical;

# 設定の値から、組の並び [ { title, html }, ... ] を返す。壊れていれば空
sub decode {
	my ($class, $value) = @_;
	my $boxes = eval { $JSON->decode($value // '[]') };
	return [] if ref $boxes ne 'ARRAY';
	return [ map { +{ title => $_->{title} // '', html => $_->{html} // '' } } grep { ref $_ eq 'HASH' } @$boxes ];
}

sub encode {
	my ($class, $boxes) = @_;
	return $JSON->encode([ map { +{ title => $_->{title}, html => $_->{html} } } @$boxes ]);
}

# フォームの値（同じ名前で並べて送る box_title と box_html）を確かめる
#   題名も中身も空の組は捨てる。戻り値は (\@boxes, \@errors)
sub parse_form {
	my ($class, $titles, $htmls) = @_;
	my (@boxes, @errors);
	my $count = @$titles > @$htmls ? @$titles : @$htmls;
	for my $i (0 .. $count - 1) {
		(my $title = $titles->[$i] // '') =~ s/\A\s+|\s+\z//g;
		$title =~ s/[\r\n]+/ /g;
		(my $html = $htmls->[$i] // '') =~ s/\r\n?/\n/g;
		$html =~ s/\A\s+|\s+\z//g;
		next if $title eq '' && $html eq '';
		my $n = @boxes + 1;
		push @errors, "${n}番目の欄の題名を書いてください。" if $title eq '';
		push @errors, "${n}番目の欄の題名は${MAX_TITLE}文字までにしてください。" if length $title > $MAX_TITLE;
		push @errors, "${n}番目の欄の中身は${MAX_HTML}文字までにしてください。" if length $html > $MAX_HTML;
		push @boxes, { title => $title, html => $html };
	}
	push @errors, "欄は${MAX_BOXES}個までにしてください。" if @boxes > $MAX_BOXES;
	return (\@boxes, \@errors);
}

# サイドバーに出す形 [ { title, html（許可リストに通したHTML） }, ... ]
sub for_display {
	my ($class, $value) = @_;
	return [ map { +{ title => $_->{title}, html => sanitize_html($_->{html}) } } @{ $class->decode($value) } ];
}

1;
