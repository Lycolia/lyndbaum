package Lyndbaum::EditorSettings;
# 記事の編集の設定の項目（settingsテーブルに保存する）。決まりは docs/admin.md の「更新履歴」と「画像のアップロード」
#   項目の書き方は Lyndbaum::SettingsForm
use strict;
use warnings;
use utf8;

use Lyndbaum::SettingsForm;

our @FIELDS = (
	{ key => 'revision_interval', type => 'int', default => 3, min => 0, max => 720, label => '履歴を残す間隔（時間）',
	  help => '前に履歴を残してからこの時間の中の保存では、新しい履歴を作りません。続けて何度も保存したときに、履歴が増えすぎないようにします。0にすると、題名か本文が変わるたびに残します。' },
	{ key => 'thumbnail_size',    type => 'int', default => 240, min => 60, max => 800, label => 'サムネイルの大きさ（長い辺、px）',
	  help => '画像を上げるときの既定の大きさです。上げるときに変えられます。元の画像のほうが小さければ、元の大きさのままにします。' },
	{ key => 'revision_max',      type => 'int', default => 120, min => 0, max => 10000, label => '記事ごとに残す履歴の数',
	  help => '超えた分は、古いものから消します。0にすると、いくつでも残します。' },
);

sub fields { \@FIELDS }

sub defaults {
	return Lyndbaum::SettingsForm->defaults(\@FIELDS);
}

sub parse_form {
	my ($class, $get) = @_;
	return Lyndbaum::SettingsForm->parse(\@FIELDS, $get);
}

1;
