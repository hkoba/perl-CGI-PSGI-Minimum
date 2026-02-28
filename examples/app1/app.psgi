use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use CGI::PSGI::Minimum [as => 'CGI'];
use SelectSaver;

{
  return sub {
    my ($env) = @_;
    my $cgi = CGI->new($env);
    print "cgi=", $cgi, "\n";
    print "params: ", $cgi->param, "\n";
    {
      my $saver = SelectSaver->new($cgi);
      toppage($cgi);
    }
    $cgi->psgi_tuple;
  };
}

sub toppage {
  my ($cgi) = @_;
  $cgi->header;
  print "<h2>hello!</h2>\n";
  print "$_ => ", $cgi->param($_), "<br>\n" for $cgi->param;
}
