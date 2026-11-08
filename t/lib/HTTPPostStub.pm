use strict;
#-------------------------------------------------------------------------------
# 子のプロセス（lyndbaum.cgi）で、Base::HTTPのpostを差し替える
#-------------------------------------------------------------------------------
# AppTestはlyndbaum.cgiを別のプロセスで動かすので、PERL5OPTで読み込ませる。
#
#	local $app->{env} = {
#		PERL5OPT       => "-I$FindBin::Bin/lib -MHTTPPostStub",
#		STUB_POST_LOG  => "$dir/post.log",	# 送ったものを1行ずつ書く（URL、Content-Type、本文をタブで区切る）
#		STUB_POST_STATUS => 202,		# 返す状態（既定は200）
#		STUB_GET_LOG   => "$dir/get.log",	# 入れたときだけgetも差し替える。取得したURLを1行ずつ書く
#	};
#
# getは、<title>に「取得N」（Nはそれまでに取得した回数）を入れたHTMLを返す。
# 取得し直したかどうかを、ページに出た題名で見分けられる。
#
# 外のネットワークには出ない。
#
package HTTPPostStub;
use File::Basename ();
use File::Spec ();

BEGIN {
	my $lib = File::Spec->rel2abs(File::Basename::dirname(__FILE__) . '/../../lib');
	unshift(@INC, $lib);
}
require Satsuki::Base::HTTP;

{
	no warnings 'redefine';
	*Satsuki::Base::HTTP::post = sub {
		my ($self, $url, $header, $body) = @_;
		my $ctype = ref($header) eq 'HASH' ? $header->{'Content-Type'} : '';
		if (my $log = $ENV{STUB_POST_LOG}) {
			open(my $fh, '>>:raw', $log) || die "$log: $!";
			$body =~ s/[\r\n]/ /g;
			print $fh "$url\t$ctype\t$body\n";
			close($fh);
		}
		my $status = $ENV{STUB_POST_STATUS} || 200;
		$self->{status} = $status;
		if ($status >= 400) { $self->{error} = "status $status"; }
		return wantarray ? ($status, [], []) : [];
	};

	my $get = \&Satsuki::Base::HTTP::get;
	*Satsuki::Base::HTTP::get = sub {
		my ($self, $url) = @_;
		my $log = $ENV{STUB_GET_LOG};
		if (!$log) { return $get->(@_); }
		open(my $fh, '>>:raw', $log) || die "$log: $!";
		print $fh "$url\n";
		close($fh);
		open($fh, '<:raw', $log) || die "$log: $!";
		my @lines = <$fh>;
		close($fh);
		my $n = scalar(@lines);
		$self->{url} = $url;
		my $body = "<html><head><title>取得$n</title></head><body></body></html>";
		return wantarray ? (200, [ 'HTTP/1.1 200', 'Content-Type: text/html; charset=UTF-8' ], [ $body ]) : [ $body ];
	};
}

1;
