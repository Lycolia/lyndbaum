#-------------------------------------------------------------------------------
# linkボックスモジュールのHTML生成ルーチン
#-------------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $id   = $self->plugin_name_id($name);
	my $set  = $self->load_plgset($name);

	my $title = $set->{title} || 'link list';
	my $html = <<HTML;
<!--Links======================================-->
<div class="side-module side-link-list" data-module-name="$name" id="$id">
<div class="side-module-title">$title</div>
<div class="side-module-body">
<ul class="side-module-list">
HTML


	foreach(split('\n', $set->{elements})) {
		my ($text,$url) = split(/\t/, $_, 2);
		if ($url ne '') {
			$html .= <<HTML;
<li><a href="$url">$text</a></li>
HTML
		} else {
			$html .= "<li>$text</li>";
		}
	}

	$html .= <<HTML;
</ul>
</div> <!-- side-module-body -->
</div> <!-- side-module -->
HTML
	return $html;
}

