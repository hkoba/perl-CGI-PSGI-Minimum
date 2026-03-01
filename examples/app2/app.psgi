use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use SelectSaver;

use CGI::PSGI::Minimum [as => 'CGI'];

use MyApp;

{
  return sub {
    my ($env) = @_;
    my $cgi = CGI->new($env);
    {
      my $saver = SelectSaver->new($cgi);
      MyApp->dispatch($cgi);
    }
    $cgi->psgi_tuple;
  };
}

