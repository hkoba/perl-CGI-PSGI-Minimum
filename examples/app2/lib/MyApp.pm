package MyApp;
use strict;
use warnings;
use utf8;
use Encode;

my $CONTENT = "";

sub dispatch {
  my ($self, $cgi) = @_;
  my $cmdName = $cgi->param('cmd') || 'main';
  if (my $sub = __PACKAGE__->can("cmd_$cmdName")) {
    $sub->($self, $cgi);
  } else {
    die "No such cmd: $cmdName";
  }
}

sub cmd_main {
  my ($self, $cgi) = @_;
  $cgi->charset("utf-8");
  $cgi->header;
  binmode $cgi, ":utf8";
  print <<END;
<html>
<body>
<pre>@{[escape($CONTENT)]}</pre>
<form method="POST" action="?cmd=update">
<textarea name="body" rows=10 cols=80>@{[escape($CONTENT)]}</textarea>
<button type="submit">更新</button>
</form>
</body>
</html>
END
}

sub cmd_update {
  my ($self, $cgi) = @_;
  $CONTENT = decode_utf8($cgi->param('body') // '');
  $cgi->redirect('./');
}

sub escape {
  my ($s) = @_;
  $s =~ s|\r\n|\n|g;
  $s =~ s|\r|\n|g;
  $s =~ s|\&|&amp;|g;
  $s =~ s|<|&lt;|g;
  $s =~ s|>|&gt;|g;
  $s =~ s|\"|&quot;|g;
  return $s;
}

1;
