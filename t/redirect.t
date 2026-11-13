#!/usr/bin/env perl
# Below is stolen with many modifications from CGI-PSGI/t/redirect.t

use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test::More;

eval "use 5.008";
plan skip_all => "$@" if $@;
# plan tests => 6;
#plan 'no_plan';

use CGI::PSGI::Minimum ();

# Set up a CGI environment
my $env;
$env->{REQUEST_METHOD}  = 'GET';
$env->{QUERY_STRING}    = 'game=chess&game=checkers&weather=dull';
$env->{PATH_INFO}       = '/somewhere/else';
$env->{PATH_TRANSLATED} = '/usr/local/somewhere/else';
$env->{SCRIPT_NAME}     = '/cgi-bin/foo.cgi';
$env->{SERVER_PROTOCOL} = 'HTTP/1.0';
$env->{SERVER_PORT}     = 8080;
$env->{SERVER_NAME}     = 'the.good.ship.lollypop.com';
$env->{REQUEST_URI}     = "$env->{SCRIPT_NAME}$env->{PATH_INFO}?$env->{QUERY_STRING}";
$env->{HTTP_LOVE}       = 'true';

my $q = CGI::PSGI::Minimum->new($env);

# These first tree tests are ported from CGI.pm's 'function.t'
{
    my $test = 'psgi_redirect($url)';
    my ($status,$headers) = $q->psgi_redirect('http://somewhere.else');
    is($status, 302, "$test - default status");
    is_deeply $headers, [ 'Location' => 'http://somewhere.else' ], "$test - headers array";  
}
{
    my $test = 'psgi_redirect() with content type';
    my ($status,$headers) = $q->psgi_redirect( -Location=>'http://somewhere.else',-Type=>'text/html');
    is($status, 302, "$test - status");
    is_deeply $headers, [ 
        'Location' => 'http://somewhere.else',
        'Content-Type' => 'text/html; charset=ISO-8859-1',
        ], "$test - headers array";  
}
{
    my $test = "psgi_redirect() with path and query string"; 
    my ($status,$headers) = $q->psgi_redirect( -Location=>'http://somewhere.else/bin/foo&bar',-Type=>'text/html');
    is($status, 302, "$test - status");
    is_deeply $headers, [ 
        'Location' => 'http://somewhere.else/bin/foo&bar',
        'Content-Type' => 'text/html; charset=ISO-8859-1',
        ], "$test - headers array";  
}


#----------------------------------------
# CGI.pm compatible arguments of redirect()
#----------------------------------------
{
    no warnings 'redefine';
    *CGI::PSGI::Minimum::_now = sub { 1700000000 };
}
my $DATE = 'Tue, 14 Nov 2023 22:13:20 GMT';

{
    my $q = CGI::PSGI::Minimum->new(+{%$env});
    is $q->redirect('http://somewhere.else'), "", "redirect() returns empty string";
    is $q->{_status_text}, '302 Found', "default status text is '302 Found'";
    like $q->as_cgi_header, qr/\AStatus: 302 Found\r\nLocation: http:\/\/somewhere.else\r\n\r\n\z/,
        "as_cgi_header of default redirect";
}
{
    my $test = 'redirect(-location, -cookie, -status, X-Foo)';
    my $q = CGI::PSGI::Minimum->new(+{%$env});
    my ($status, $headers) = $q->psgi_redirect(
        -location => 'http://somewhere.else/', -cookie => ['U=1000; path=/'],
        -status => 301, 'X-Foo' => 1);
    is $status, 301, "$test - status";
    is $q->{_status_text}, '301', "$test - status text";
    is_deeply $headers, [
        'Set-Cookie' => 'U=1000; path=/',
        'Date' => $DATE,
        'Location' => 'http://somewhere.else/',
        'X-Foo' => 1,
    ], "$test - headers";
}
{
    for my $key (qw(-uri -url -URL -Location -location)) {
        my ($status, $headers) = CGI::PSGI::Minimum->new(+{%$env})
          ->psgi_redirect($key => 'http://somewhere.else/');
        is_deeply $headers, [Location => 'http://somewhere.else/'], "redirect($key)";
    }
}
{
    my $q = CGI::PSGI::Minimum->new(+{%$env});
    my ($status, $headers) = $q->psgi_redirect(
        -uri => 'x.html', -status => '303 See Other', -target => 'f1',
        -nph => 1, '-X_Bar' => 2, -content_type => 'text/plain', -charset => 'utf-8');
    is $status, 303;
    is_deeply $headers, [
        'Window-Target' => 'f1',
        'Location' => 'x.html',
        'X-bar' => 2,
        'Content-Type' => 'text/plain; charset=utf-8',
    ], "redirect() passes other header arguments to header()";
    like $q->as_cgi_header, qr/\AStatus: 303 See Other\r\n/;
}
{
    my $q = CGI::PSGI::Minimum->new(+{%$env});
    my ($status, $headers) = $q->psgi_redirect({-location => 'y.html', -status => 307});
    is $status, 307, "hash ref argument";
    is_deeply $headers, [Location => 'y.html'];
}
{
    my $q = CGI::PSGI::Minimum->new(+{%$env});
    my ($status, $headers) = $q->psgi_redirect(-status => 301);
    is_deeply $headers, [Location => $q->self_url], "Location defaults to self_url";
}
{
    require URI;
    my ($status, $headers) = CGI::PSGI::Minimum->new(+{%$env})
      ->psgi_redirect(URI->new('http://somewhere.else/a'));
    is_deeply $headers, [Location => 'http://somewhere.else/a'], "URI object";
}

done_testing;
