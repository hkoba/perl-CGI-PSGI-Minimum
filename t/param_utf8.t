#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test2::V0 -no_srand => 1, -target => "CGI::PSGI::Minimum";

use Encode ();
use URI::Escape ();

my $ja = "日本語";
my $body = join "&"
  , "name=" . URI::Escape::uri_escape(Encode::encode_utf8($ja))
  , "ascii=abc"
  , "multi=" . URI::Escape::uri_escape(Encode::encode_utf8("あ"))
  , "multi=x";

sub post_env {
  open my $in, '<', \$body or die $!;
  +{
    REQUEST_METHOD  => 'POST',
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    CONTENT_LENGTH  => length($body),
    QUERY_STRING    => '',
    SCRIPT_NAME     => '',
    PATH_INFO       => '',
    SERVER_NAME     => 'localhost',
    SERVER_PORT     => 80,
    SERVER_PROTOCOL => 'HTTP/1.1',
    'psgi.input'    => $in,
  };
}

{
  local $CGI::PSGI::Minimum::PARAM_UTF8 = 0;
  my $obj = CLASS->new(post_env());
  is $obj->param('name'), Encode::encode_utf8($ja), "PARAM_UTF8=0: values are bytes";
}

{
  local $CGI::PSGI::Minimum::PARAM_UTF8 = 1;
  my $obj = CLASS->new(post_env());
  is $obj->param('name'), $ja, "PARAM_UTF8=1: values are decoded";
  is $obj->param('ascii'), 'abc', "ascii stays";
  is [$obj->param('multi')], ["あ", 'x'], "multiple values are decoded";
  is [$obj->param], [qw(name ascii multi)], "names are kept";

  $obj->param(name => $ja);
  is $obj->param('name'), $ja, "utf8 flagged value is not decoded twice";

  is $obj->query_string
    , "name=%E6%97%A5%E6%9C%AC%E8%AA%9E;ascii=abc;multi=%E3%81%82;multi=x"
    , "query_string escapes decoded values as UTF-8";

  for my $raw (qw(PUTDATA POSTDATA PATCHDATA)) {
    my $bytes = Encode::encode_utf8($ja);
    $obj->param($raw => $bytes);
    is $obj->param($raw), $bytes, "$raw is returned as is (not decoded)";
  }
}

{
  local $CGI::PSGI::Minimum::PARAM_UTF8;
  CLASS->import([param_utf8 => 1]);
  is $CGI::PSGI::Minimum::PARAM_UTF8, 1, "declare_param_utf8";
}

SKIP: {
  skip "CGI.pm is not installed", 1 unless eval {require CGI; 1};
  no warnings 'once'; # $CGI::PARAM_UTF8 is only seen at runtime

  open my $in, '<', \$body or die $!;
  local *STDIN = $in;
  local %ENV = (%ENV, REQUEST_METHOD => 'POST'
                , CONTENT_TYPE => 'application/x-www-form-urlencoded'
                , CONTENT_LENGTH => length($body), QUERY_STRING => '');
  CGI::initialize_globals(); # this also resets $CGI::PARAM_UTF8, so set it afterwards
  local $CGI::PARAM_UTF8 = 1;
  my $real = CGI->new;

  local $CGI::PSGI::Minimum::PARAM_UTF8 = 1;
  my $obj = CLASS->new(post_env());

  is [map {[$obj->param($_)]} qw(name ascii multi)]
    , [map {[$real->multi_param($_)]} qw(name ascii multi)]
    , "same values as CGI.pm with -utf8";
}

done_testing;
