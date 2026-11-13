#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test2::V0;

use CGI::PSGI::Minimum ();

my %ENV0 = (REQUEST_METHOD => 'GET', QUERY_STRING => 'a=1&b=2');

sub new_cgi { CGI::PSGI::Minimum->new(+{%ENV0}) }

subtest "headers and body are cleared" => sub {
  my $q = new_cgi();
  print $q $q->header(-status => 404, -type => 'text/plain', -x_foo => 1),
    "partial output";
  ok $q->has_header;

  $q->reset_response;

  ok !$q->has_header, "has_header is false";
  is $q->as_cgi_header, "", "as_cgi_header is empty";
  is $q->as_bytes, "", "as_bytes is empty";
  is $q->as_cgi_response, "", "as_cgi_response is empty";
  is $q->{$_}, undef, "$_ is undef"
    for qw(_status _status_text _response_headers _header_called);
  is $q->psgi_tuple, new_cgi()->psgi_tuple, "psgi_tuple is same as a new object";
  my ($r1, $r2) = ($q->response, new_cgi()->response);
  is [$r1->status, $r1->headers->as_string], [$r2->status, $r2->headers->as_string],
    "response is same as a new object";
};

subtest "output after reset contains only the new response" => sub {
  my $q = new_cgi();
  print $q $q->header(-type => 'text/plain'), "partial output";
  $q->reset_response;
  print $q $q->header(-status => 500, -type => 'text/plain'), "error page";

  my $res = $q->as_cgi_response;
  is $res,
    "Status: 500\r\nContent-Type: text/plain; charset=ISO-8859-1\r\n\r\nerror page";
  unlike $res, qr/\0/, "no NUL";
  is $q->as_bytes, "error page", "body is written from the beginning";
};

subtest "old body longer / shorter than new body" => sub {
  for my $c (
    [longer  => "x" x 100, "short"],
    [shorter => "ab", "a much longer body than before"],
    [same    => "12345", "abcde"],
  ) {
    my ($label, $old, $new) = @$c;
    my $q = new_cgi();
    print $q $old;
    $q->as_bytes;     # flushes
    print $q "more";  # pending in the buffer of the handle
    $q->reset_response;
    print $q $new;
    my $bytes = $q->as_bytes;
    is $bytes, $new, "$label: only the new body";
    unlike $bytes, qr/\0/, "$label: no NUL";
  }
};

subtest "binmode layers are kept" => sub {
  my $q = new_cgi();
  binmode $q, ':encoding(utf8)';
  print $q "\x{3042}\x{3044}\x{3046}";   # あいう
  $q->reset_response;
  print $q "\x{30A8}\x{30E9}\x{30FC}";   # エラー
  my $bytes = $q->as_bytes;
  is $bytes, "\xE3\x82\xA8\xE3\x83\xA9\xE3\x83\xBC", "valid UTF-8 bytes";
  ok !utf8::is_utf8($bytes), "bytes, not characters";
  is Encode::decode('UTF-8', $bytes, Encode::FB_CROAK()), "\x{30A8}\x{30E9}\x{30FC}";
};

subtest "redirect then reset" => sub {
  my $q = new_cgi();
  $q->redirect('http://example.com/');
  $q->reset_response;
  my ($status, $headers) = $q->psgi_header(-status => 503, -type => 'text/plain');
  is $status, 503;
  is $headers, ['Content-Type' => 'text/plain; charset=ISO-8859-1'], "no Location";
  is $q->as_cgi_header,
    "Status: 503\r\nContent-Type: text/plain; charset=ISO-8859-1\r\n\r\n";
};

subtest "cache is kept" => sub {
  my $q = new_cgi();
  $q->cache(1);
  $q->header;
  $q->reset_response;
  is $q->cache, 1, "cache is still 1";
  $q->header;
  is $q->{_response_headers},
    [Pragma => 'no-cache', 'Content-Type' => 'text/html; charset=ISO-8859-1'];
};

subtest "request side and charset are kept" => sub {
  my $q = new_cgi();
  $q->charset('utf-8');
  $q->param(c => 3);
  $q->header(-type => 'text/plain');
  $q->reset_response;
  is [sort $q->param], [qw(a b c)], "param names";
  is $q->param('a'), 1;
  is $q->param('c'), 3, "parameter set by the app is kept";
  is $q->charset, 'utf-8', "charset";
  is $q->request_method, 'GET', "env";
};

subtest "safe on a fresh object, and when called twice" => sub {
  my $q = new_cgi();
  ok lives { $q->reset_response }, "fresh object";
  ok lives { $q->reset_response }, "twice";
  ok !$q->has_header;
  is $q->as_bytes, "";
  is $q->psgi_tuple, new_cgi()->psgi_tuple;

  print $q $q->header, "body";
  $q->reset_response->reset_response;
  print $q "ok";
  is $q->as_bytes, "ok";
};

subtest "returns the object itself" => sub {
  my $q = new_cgi();
  my $ret = $q->reset_response;
  is ref $ret, ref $q;
  is Scalar::Util::refaddr($ret), Scalar::Util::refaddr($q);
};

done_testing;
