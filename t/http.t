#!/usr/bin/env perl
# Below is stolen with many modifications from CGI-PSGI/t/http.t

use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test::More;

use CGI::PSGI::Minimum ();

my $env;
$env->{REQUEST_METHOD}  = 'GET';
$env->{HTTP_HOST}       = 'virtual.example.com:81';
$env->{SERVER_NAME}     = 'server.example.com';
$env->{SCRIPT_NAME}     = '/cgi-bin/foo.cgi';
$env->{PATH_INFO}       = '';
$env->{QUERY_STRING}    = '';
$env->{SERVER_PROTOCOL} = 'HTTP/1.0';
$env->{SERVER_PORT}     = 8080;
$env->{REQUEST_URI}     = "$env->{SCRIPT_NAME}$env->{PATH_INFO}?$env->{QUERY_STRING}";
$env->{HTTP_USER_AGENT} = 'Mozilla/5.1';
$env->{HTTP_REFERER}    = 'http://localhost/foo';

{
    my $q = CGI::PSGI::Minimum->new(+{%$env});
    is $q->server_name, 'server.example.com';
    is $q->virtual_host, 'virtual.example.com';
    is $q->virtual_port, 81;

    is $q->user_agent, 'Mozilla/5.1';
    is $q->referer, 'http://localhost/foo';
}

{
    # Same as CGI.pm: case insensitive, '-' is '_', HTTP_ prefix is optional.
    my $q = CGI::PSGI::Minimum->new(+{%$env, HTTP_ACCEPT_LANGUAGE => 'ja'});
    for my $name (qw(User-Agent user-agent user_agent USER_AGENT HTTP_USER_AGENT http_user_agent Http-User-Agent)) {
        is $q->http($name), 'Mozilla/5.1', "http('$name')";
    }
    is $q->http('Accept-Language'), 'ja', "http('Accept-Language')";
    is $q->http('X-No-Such-Header'), undef, "missing header";
    is_deeply [$q->http], [qw(HTTP_ACCEPT_LANGUAGE HTTP_HOST HTTP_REFERER HTTP_USER_AGENT)],
        "http() returns sorted HTTP_* keys";
}

done_testing;
