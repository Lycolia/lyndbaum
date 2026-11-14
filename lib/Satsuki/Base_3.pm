use strict;
package Satsuki::Base;
################################################################################
# ■SpeedyCGI用のスタートアップ
################################################################################
sub init_for_speedycgi {
	my $self = shift;
	$self->{CGI_cache} = 1;
	$self->{SpeedyCGI} = 1;
	$self->{CGI_mode}  = 'SpeedyCGI';
}

################################################################################
# ■FastCGI用のスタートアップ
################################################################################
sub init_for_fastcgi {
	my $self = shift;
	$self->{FCGI_request} = shift;

	$self->{CGI_cache}= 1;
	$self->{FastCGI}  = 1;
	$self->{CGI_mode} = 'FastCGI';
}

################################################################################
# ■fork処理
################################################################################
sub fork {
	my $self = shift;
	my $dbl  = shift;
	my $fcgi = $self->{FCGI_request};
	$fcgi && $fcgi->Detach();

	my $fork = fork();
	if ($fork) {
		# parent
		$fcgi && $fcgi->Attach();
		return $fork;
	}
	if (defined $fork) {
		# child
		close(STDIN);
		close(STDOUT);
		## close(STDERR);	# Error on FastCGI

		$self->{Shutdown} = 1;
		if ($dbl) {		# double fork
			fork() && $self->exit();
			eval {
				require	POSIX;
				POSIX::setsid();
			};
		}
	}
	return $fork;
}

################################################################################
# ■システムチェック用ルーチン
################################################################################
sub get_system_info {
	my ($self) = @_;
	my %h;
	my $v = $];
	$v =~ s/(\d+)\.(\d\d\d)(\d\d\d)/$1.'.'. ($2+0).'.'.($3+0)/e;
	$h{perl_version} = $v;
	$h{os}           = $^O;
	return \%h;
}

sub check_lib {
	my ($self, $lib) = @_;
	my $pm = $lib;
	$pm =~ s|::|/|g;
	eval { require "$pm.pm"; };
	if ($@) { return 0; }

	# $VERSIONが無ければ、親のパッケージのものを使う。
	# DebianのImage::Magickは use parent qw/Image::Magick::Q16/ だけで、バージョンは親にある
	my @pkgs = ($lib);
	my %seen;
	no strict "refs";
	while(@pkgs) {
		my $pkg = shift(@pkgs);
		if ($seen{$pkg}++) { next; }
		my $ver = ${$pkg . '::VERSION'};
		if ($ver) { return $ver; }
		push(@pkgs, @{$pkg . '::ISA'});
	}
	return '?.??';
}

sub check_cmd {
	my $self = shift;
	my $cmd  = shift;
	foreach(split(/:/, $ENV{PATH})) {
		if (-x "$_/$cmd") { return 1; }
	}
	return 0;
}

#-------------------------------------------------------------------------------
# ●ディレクトリ使用量
#-------------------------------------------------------------------------------
# get_dir_size("dir/", $depth, @split);
#	ファイルの大きさ（statの7番目）の合計を数える。duのブロック単位の値とは少しずれる
#	シンボリックリンクは辿らず、リンクそのものも数えない。無いフォルダは0になる
#
#	$depth	内訳を出す深さ。listにその深さのフォルダごとの値を返す
#		それより浅いところにあるファイルは、そのフォルダの行に入る（直下のファイルはnameが''）
#	@split	別に数えるフォルダの名前（'.thumbnail'など）
#		その名前のフォルダの中身はsplitに入れ、listには入れない
#
#	返り値	{ size, files, errors, list => [{ name, size, files }, ...（使用量の大きい順）],
#		  split => { 名前 => { size, files } } }
#
sub get_dir_size {
	my $self  = shift;
	my $dir   = shift;
	my $depth = int(shift);
	my %split = map { $_ => { size => 0, files => 0 } } @_;
	$dir =~ s|/*$|/|;

	my %list;
	my %r = ( size => 0, files => 0, errors => 0 );

	# [ディレクトリ（$dirからの相対）, 内訳の行の名前, 別に数えるフォルダの名前]
	my @stack = ([ '', '', '' ]);
	while(@stack) {
		my ($rel, $name, $sp) = @{ pop(@stack) };
		# 無いフォルダ（キャッシュを作る前など）は0とし、読めないものだけerrorsに数える
		opendir(my $fh, "$dir$rel") || do { if (-e "$dir$rel") { $r{errors}++; } next; };
		my @files = readdir($fh);
		closedir($fh);

		my $lv = ($rel =~ tr|/||);
		foreach(@files) {
			if ($_ eq '.' || $_ eq '..') { next; }
			my $path = "$rel$_";
			my @st   = lstat("$dir$path");
			if (!@st || -l _) { next; }
			if (-d _) {
				my $s = $sp || ($split{$_} ? $_ : '');
				my $n = (!$s && $lv < $depth) ? "$path/" : $name;
				push(@stack, [ "$path/", $n, $s ]);
				next;
			}
			$r{size} += $st[7];
			$r{files}++;
			my $h = $sp ? $split{$sp} : $depth ? ($list{$name} ||= { name => $name, size => 0, files => 0 }) : undef;
			if ($h) {
				$h->{size} += $st[7];
				$h->{files}++;
			}
		}
	}
	$r{split} = \%split;
	$r{list}  = [ sort { $b->{size} <=> $a->{size} || $a->{name} cmp $b->{name} } values(%list) ];
	return \%r;
}

################################################################################
# ■データダンプ
################################################################################
sub dump_all {
	my $self = shift;
	my $data = shift;
	my $tab  = shift || '  ';
	my $br   = shift || "\n";
	my $sp   = shift || '';
	my $ret = '';
	if (ref($data) eq 'HASH') {
		foreach(sort(keys(%$data))) {
			my $k = $_;
			my $v = $data->{$_};
			if (ref($v) eq 'ARRAY') {
				$ret .= "$sp$k=[$br";
				$ret .= $self->dump_all($v, $tab, $br, "$tab$sp");
				$ret .= "$sp]$br";
				next;
			}
			if (ref($v) eq 'HASH') {
				$ret .= "$sp$k={$br";
				$ret .= $self->dump_all($v, $tab, $br, "$tab$sp");
				$ret .= "$sp}$br";
				next;
			}
			$ret .= "$sp$k=$v$br";
		}
	} else {
		foreach(@$data) {
			if (ref($_) eq 'ARRAY') {
				$ret .= "$sp\[$br";
				$ret .= $self->dump_all($_, $tab, $br, "$tab$sp");
				$ret .= "$sp]$br";
				next;
			}
			if (ref($_) eq 'HASH') {
				$ret .= "$sp\{$br";
				$ret .= $self->dump_all($_, $tab, $br, "$tab$sp");
				$ret .= "$sp}$br";
				next;
			}
			$ret .= "$sp$_$br";
		}
	}
	return $ret;
}

1;
