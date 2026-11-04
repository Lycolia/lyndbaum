#-------------------------------------------------------------------------------
# sitemap生成モジュール
#-------------------------------------------------------------------------------
sub {
	my $self = shift;
	my $name = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};

	my $h = {
		flag      => { enable => 1 },
		cols      => [ 'title', 'tm', 'link_key', 'update_tm' ],
	};
	my $ary = $DB->select("art", $h);

	foreach(@$ary) {
		$_->{elink_key} = $_->{link_key};
		$self->link_key_encode( $_->{elink_key} );
	}

	# generate XML
	my $xml = $ROBJ->call('_format/sitemap', $ary);

	# sitemap.xml
	my $file = $self->{pub_dir} . 'sitemap.xml';
	$ROBJ->fwrite_lines($file, $xml);

	return 0;
}

