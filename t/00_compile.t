use strict;
use Test::More 0.98;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use_ok $_ for qw(
    CGI::PSGI::Minimum
);

done_testing;

