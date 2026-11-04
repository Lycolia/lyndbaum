#-------------------------------------------------------------------------------
# InformationモジュールのHTML生成ルーチン
#-------------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $id   = $self->plugin_name_id($name);
	my $set  = $self->load_plgset($name);

#-------------------------------------------------------------------------------
# モジュールのデータ
#-------------------------------------------------------------------------------
	my %modules;
	my $title  = $set->{title} || 'Information';
	my $hidden = $set->{title_hidden} ? ' display-none' : '';

	$modules{_header} = <<HTML;
<!--Information==========================================-->
<div class="hatena-module" id="$id" data-module-name="$name">
<div class="hatena-moduletitle$hidden">$title</div>
<div class="hatena-modulebody">
<ul class="hatena-section">
HTML

	$modules{_footer} = <<'HTML';
</ul>
</div> <!-- hatena-modulebody -->
</div> <!-- hatena-module -->
HTML

	$modules{description} = <<'HTML';
	<li class="description"><@s.description_txt></li>
HTML
	$modules{bcounter} = <<'HTML';
	<li class="bcounter icons"><a class="bcounter" href="https://b.hatena.ne.jp/entrylist?url=<@ServerURL><@v.myself>"><img alt="はてブカウンタ" src="//b.hatena.ne.jp/bc/<#val>/<@ServerURL><@v.myself>" class="bcounter"></a></li>
HTML
	$modules{bicon} = <<'HTML';
	<li class="http-bookmark icons"><a class="http-bookmark" href="https://b.hatena.ne.jp/entry/<@ServerURL><@v.myself>"><img src="//b.st-hatena.com/entry/image/<@ServerURL><@v.myself>" alt="はてブ数"></a></li>
HTML
	$modules{rssicon} = <<'HTML';
	<li class="rss-icon icons">
	<@ifexec(s.rss_files, begin)>
	<a href="<@Basepath><@v.pub_dir><@v.load_rss_files()#0>">
	<$end>
	<img alt="RSS" src="<@Basepath><@v.pubdist_dir>rss-icon.png" width="80" height="15">
	<@if(s.rss_files, '</a>')></li>
HTML
	$modules{free_txt} = $modules{freebr_txt} =<<'HTML';
	<li class="free-text"><#val></li>
HTML
	my $ele = $set->{elements} ? $set->{elements} : <<'DEFAULT';
description
DEFAULT
	my @elements = split("\n", $ele);
	unshift(@elements, '_header');
	push   (@elements, '_footer');

	my $html='';
	foreach(@elements) {
		my $key = $_;
		my $val = '';
		if ($_ =~ /^([\w\-]*),(.*)$/s) {
			$key = $1;
			$val = $2;
		}
		my $mod = $modules{$key};
		if (!$mod) { next; }

		if ($val eq '') {
			$val = $modules{"$key:default"};
		}

		# 保存
		$mod =~ s/<#val>/$val/g;
		$html .= $mod;
	}

	return $html;
}

