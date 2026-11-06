#!/usr/bin/env perl
# CGI.pm compatibility: undef values given to the setter form of param()
# are ignored, i.e. param(NAME => 1, undef, 2) stores [1, 2].

use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test2::V0 -no_srand => 1, -target => "CGI::PSGI::Minimum";

sub get_env {
  +{
    REQUEST_METHOD  => 'GET',
    QUERY_STRING    => 'a=1',
    SCRIPT_NAME     => '',
    PATH_INFO       => '',
    SERVER_NAME     => 'localhost',
    SERVER_PORT     => 80,
    SERVER_PROTOCOL => 'HTTP/1.1',
  };
}

{
  my $obj = CLASS->new(get_env());

  $obj->param(foo => 1, undef, 2);
  is [$obj->param('foo')], [1, 2], "undef in the middle is ignored";

  $obj->param(foo => undef, 3);
  is [$obj->param('foo')], [3], "leading undef is ignored";

  $obj->param(foo => 4, undef);
  is [$obj->param('foo')], [4], "trailing undef is ignored";

  $obj->param(foo => undef, undef, 5, undef);
  is [$obj->param('foo')], [5], "multiple undefs are ignored";

  is scalar($obj->param('foo')), 5, "scalar getter returns the first defined value";

  is $obj->query_string, "a=1;foo=5", "query_string has no undef entries";

  is [$obj->param], [qw(a foo)], "parameter names";
}

{
  # Like CGI.pm, when every given value is undef the parameter is
  # neither created nor overwritten.
  my $obj = CLASS->new(get_env());

  $obj->param(bar => undef);
  is [$obj->param], ['a'], "param(NAME => undef) does not create the parameter";

  $obj->param(a => undef);
  is [$obj->param('a')], [1], "param(NAME => undef) keeps the existing value";

  $obj->param(baz => undef, undef);
  is [$obj->param], ['a'], "param(NAME => undef, undef) does not create the parameter";
}

SKIP: {
  skip "CGI.pm is not installed", 1 unless eval {require CGI; 1};
  no warnings 'once';

  local %ENV = (%ENV, REQUEST_METHOD => 'GET', QUERY_STRING => 'a=1');
  CGI::initialize_globals();
  local $CGI::LIST_CONTEXT_WARN = 0;
  my $real = CGI->new;
  my $obj = CLASS->new(get_env());

  my @cases = ([foo => 1, undef, 2], [foo => undef, 3], [foo => 4, undef]);
  for my $case (@cases) {
    $real->param(@$case);
    $obj->param(@$case);
  }

  is [map {[$obj->param($_)]} qw(a foo)]
    , [map {[$real->multi_param($_)]} qw(a foo)]
    , "same values as CGI.pm";
}

done_testing;
