package Lyndbaum::Config;
# 設定ファイル（JSON）の読み込み
#   秘密情報を含むので config.json はリポジトリに入れない。見本は config.sample.json
use strict;
use warnings;
use utf8;

use File::Spec;
use JSON::PP;

sub new {
	my ($class, %values) = @_;
	return bless { %values }, $class;
}

sub load {
	my ($class, $file) = @_;
	open my $fh, '<:raw', $file or die "設定ファイルを開けません: $file: $!\n";
	my $json = do { local $/; <$fh> };
	close $fh;
	return $class->new(%{ JSON::PP->new->utf8->decode($json) });
}

sub get {
	my ($self, $key) = @_;
	return $self->{$key};
}

# パスの設定を返す。相対パスなら $root からの相対として扱う
sub path_of {
	my ($self, $key, $root) = @_;
	my $path = $self->{$key} // die "設定 $key がありません\n";
	return File::Spec->file_name_is_absolute($path) ? $path : File::Spec->catfile($root, $path);
}

1;
