#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test2::V0;

use CGI::PSGI::Minimum ();

{
  no warnings 'redefine';
  *CGI::PSGI::Minimum::_now = sub { 1700000000 };
}
my $DATE = 'Tue, 14 Nov 2023 22:13:20 GMT';

sub new_cgi { CGI::PSGI::Minimum->new(+{}) }

subtest "has_header / no header" => sub {
  my $q = new_cgi();
  ok !$q->has_header, "header() is not called yet";
  is $q->as_cgi_header, "", "as_cgi_header is empty";
  print $q "body";
  is $q->as_cgi_response, "body", "as_cgi_response without header";

  $q->header;
  ok $q->has_header, "header() is called";

  my $q2 = new_cgi();
  $q2->redirect('/');
  ok $q2->has_header, "redirect() is called";
};

subtest "as_cgi_header" => sub {
  my $q = new_cgi();
  $q->header;
  is $q->as_cgi_header,
    "Content-Type: text/html; charset=ISO-8859-1\r\n\r\n",
    "no Status line when status is not specified";

  $q->header(-status => 404, -type => 'text/plain', -x_foo => 'bar');
  is $q->as_cgi_header,
    "Status: 404\r\nX-foo: bar\r\nContent-Type: text/plain; charset=ISO-8859-1\r\n\r\n";

  $q->header(-status => '200 OK', -type => '');
  is $q->as_cgi_header, "Status: 200 OK\r\n\r\n", "explicit 200";

  $q->redirect(-location => 'thanks.html', -cookie => 'U=1000; path=/');
  is $q->as_cgi_header, join("\r\n",
    "Status: 302 Found",
    "Set-Cookie: U=1000; path=/",
    "Date: $DATE",
    "Location: thanks.html",
    "", "");
};

subtest "as_cgi_header follows _status modified without header()" => sub {
  my $q = new_cgi();
  $q->header(-type => '');
  $q->{_status} = 404;
  is $q->as_cgi_header, "Status: 404\r\n\r\n";

  $q->header(-status => '302 Found', -type => '');
  $q->{_status} = 301;
  is $q->as_cgi_header, "Status: 301\r\n\r\n", "_status wins over stale _status_text";
};

subtest "as_cgi_response" => sub {
  my $q = new_cgi();
  $q->header(-type => 'text/plain');
  print $q "Hello\n";
  is $q->as_cgi_response,
    "Content-Type: text/plain; charset=ISO-8859-1\r\n\r\nHello\n";
};

subtest "headers modified through psgi_header() return value" => sub {
  my $q = new_cgi();
  my ($status, $headers) = $q->psgi_header(-type => 'text/plain');
  push @$headers, 'X-Added' => 'yes';
  is $q->as_cgi_header,
    "Content-Type: text/plain; charset=ISO-8859-1\r\nX-Added: yes\r\n\r\n";
};

done_testing;
