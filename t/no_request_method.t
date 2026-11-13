#!/usr/bin/env perl
# env without REQUEST_METHOD (ex. created by hand in tests or drivers)
use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test2::V0;

use CGI::PSGI::Minimum ();

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

my $q = CGI::PSGI::Minimum->new(+{QUERY_STRING => 'a=1&b=2'});
is [$q->param], [qw(a b)], "param() works";
is $q->param('a'), 1;
is \@warnings, [], "no warnings";

done_testing;
