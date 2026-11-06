#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test2::V0 -no_srand => 1, -target => "CGI::PSGI::Minimum";

{
  my $obj = CLASS->new(+{});
  for my $method (qw(
    auth_type
    content_type

    path_info
    path_translated
    request_method
    request_uri

    remote_addr
    remote_host
    remote_ident
    remote_user

    script_name
    server_name
    server_port
    server_protocol
    server_software
  )) {
    is $obj->$method, undef, "$method - initially undef";
    $obj->$method($method);
    is $obj->$method, $method, "$method - correctly set";
  }

  # print STDERR "# ", MOP4Import::Util::terse_dump($obj->env), "\n";

  is $obj->env, +{
    'REMOTE_ADDR' => 'remote_addr',
    'REQUEST_METHOD' => 'request_method',
    'REMOTE_HOST' => 'remote_host',
    'SERVER_SOFTWARE' => 'server_software',
    'PATH_INFO' => 'path_info',
    'SERVER_PORT' => 'server_port',
    'SERVER_NAME' => 'server_name',
    'REMOTE_USER' => 'remote_user',
    'SCRIPT_NAME' => 'script_name',
    'CONTENT_TYPE' => 'content_type',
    'AUTH_TYPE' => 'auth_type',
    'REQUEST_URI' => 'request_uri',
    'PATH_TRANSLATED' => 'path_translated',
    'SERVER_PROTOCOL' => 'server_protocol',
    'REMOTE_IDENT' => 'remote_ident'
  }, "env contents";
}

done_testing();

