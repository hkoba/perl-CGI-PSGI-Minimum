#!/usr/bin/env perl
# Tests for HTTP Response Splitting (CWE-113) protection.
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

sub new_cgi { CGI::PSGI::Minimum->new(+{}) }

my $NEWLINE_ERR = qr/^Invalid header value contains a newline not followed by whitespace/;

my %BAD = (
  CR   => "\r",
  LF   => "\n",
  CRLF => "\r\n",
);

subtest "storing: newlines are rejected" => sub {
  for my $kind (sort keys %BAD) {
    my $nl = $BAD{$kind};
    my $evil = "x${nl}Set-Cookie: evil=1";

    my @cases = (
      ['redirect(url)'      => redirect => "http://example.com/${nl}Set-Cookie: x=1"],
      ['redirect(-Location)'=> redirect => -Location => $evil],
      ['redirect(-uri)'     => redirect => -uri => $evil],
      ['redirect(-status)'  => redirect => -location => '/', -status => "302${nl}X: 1"],
      ['redirect(-cookie)'  => redirect => -location => '/', -cookie => $evil],
      ['redirect(X-Foo)'    => redirect => -location => '/', 'X-Foo' => $evil],
      ['header(-type)'      => header => -type => "text/html${nl}X: 1"],
      ['header(single)'     => header => "text/html${nl}X: 1"],
      ['header(-status)'    => header => -status => "200${nl}X: 1"],
      ['header(-cookie)'    => header => -cookie => $evil],
      ['header(-cookie [])' => header => -cookie => ['a=1', $evil]],
      ['header(-target)'    => header => -target => $evil],
      ['header(-expires)'   => header => -expires => $evil],
      ['header(-attachment)'=> header => -attachment => $evil],
      ['header(-p3p)'       => header => -p3p => $evil],
      ['header(-charset)'   => header => -charset => $evil],
      ['header(-x_foo)'     => header => -x_foo => $evil],
      ['header(X-Foo)'      => header => 'X-Foo' => $evil],
      ['header(Location)'   => header => 'Location' => $evil],
      ['psgi_header(-x_foo)'=> psgi_header => -x_foo => $evil],
      ['psgi_redirect(url)' => psgi_redirect => $evil],
    );

    for my $c (@cases) {
      my ($label, $method, @args) = @$c;
      my $q = new_cgi();
      like dies { $q->$method(@args) }, $NEWLINE_ERR, "$label with $kind";
      ok !$q->has_header, "$label with $kind: nothing is stored";
    }

    # Cookie object whose value contains a newline
    my $q = new_cgi();
    my $cookie = bless {}, 'EvilCookie';
    like dies { $q->header(-cookie => $cookie) }, $NEWLINE_ERR,
      "cookie object with $kind";
  }
};

subtest "storing: invalid header names are rejected" => sub {
  for my $name ("X Foo", "X:Foo", "X-Foo\r\nY", "", "-X Foo") {
    like dies { new_cgi()->header($name => 1) }, qr/^Invalid header name/,
      "name " . quotemeta($name);
  }
};

subtest "storing: NUL is rejected" => sub {
  like dies { new_cgi()->header(-x_foo => "a\0b") },
    qr/^Invalid header value contains a NUL character/;
  like dies { new_cgi()->redirect("/a\0b") },
    qr/^Invalid header value contains a NUL character/;
};

subtest "error message does not contain raw control characters" => sub {
  my $err = dies { new_cgi()->header(-x_foo => "a\r\nb") };
  like $err, qr/a\\x0D\\x0Ab/;
  my ($first_line) = split /\n/, $err;
  like $first_line, qr/ at \S+ line \d+\.\z/, "message is a single line";
};

subtest "storing: folding (CRLF + whitespace) is unfolded" => sub {
  my $q = new_cgi();
  $q->header(-type => '', -x_foo => "a\r\n b", -cookie => "c=1;\r\n\tpath=/");
  is $q->{_response_headers},
    ['Set-Cookie' => "c=1;\tpath=/", Date => 'Tue, 14 Nov 2023 22:13:20 GMT', 'X-foo' => 'a b'];
  like $q->as_cgi_header, qr/\r\nX-foo: a b\r\n\r\n\z/;

  $q->redirect("/a\r\n b");
  is $q->{_response_headers}, [Location => '/a b'];

  like dies { new_cgi()->header(-x_foo => "a\n b") }, $NEWLINE_ERR,
    "bare LF + space is not folding";
  like dies { new_cgi()->header(-x_foo => "a\r\nb") }, $NEWLINE_ERR;
};

subtest "serializing: invalid names in _response_headers" => sub {
  for my $name ("X Foo", "X:Foo", "X-Foo\r\nSet-Cookie", "X\nFoo", "", undef, "X\0") {
    my $q = new_cgi();
    $q->header(-type => '');
    push @{$q->{_response_headers}}, $name => 'v';
    like dies { $q->as_cgi_header }, qr/^Invalid header name/,
      "name " . (defined $name ? quotemeta($name) : 'undef');
  }
};

subtest "serializing: invalid values in _response_headers" => sub {
  for my $value ("a\rb", "a\nb", "a\r\nSet-Cookie: x=1", "a\r\n b", "a\0b") {
    my $q = new_cgi();
    $q->header(-type => '');
    $q->{_response_headers} = ['X-Foo' => $value];
    like dies { $q->as_cgi_header }, qr/^Invalid header value for X-Foo contains CR, LF or NUL/,
      "value " . quotemeta($value);
  }

  my $q = new_cgi();
  $q->header(-type => '');
  $q->{_response_headers} = ['X-Foo' => undef];
  like dies { $q->as_cgi_header }, qr/^Invalid header value for X-Foo: undef/;
};

subtest "serializing: injected through psgi_header() return value" => sub {
  my $q = new_cgi();
  my ($status, $headers) = $q->psgi_header;
  push @$headers, 'X-Foo' => "1\r\nSet-Cookie: evil=1";
  like dies { $q->as_cgi_header }, qr/^Invalid header value for X-Foo/;
};

subtest "serializing: malformed _response_headers" => sub {
  my $q = new_cgi();
  $q->header(-type => '');
  $q->{_response_headers} = ['X-Foo'];
  like dies { $q->as_cgi_header }, qr/odd number of elements/;

  $q->{_response_headers} = {'X-Foo' => 1};
  like dies { $q->as_cgi_header }, qr/not an ARRAY ref/;
};

subtest "serializing: invalid status" => sub {
  for my $text ("302\r\nX: 1", "302 Found\r\n", "302 Fo\0und", "abc", "3020", " 302", "302Found") {
    my $q = new_cgi();
    $q->header(-status => 302, -type => '');
    $q->{_status_text} = $text;
    like dies { $q->as_cgi_header }, qr/^Invalid status text/,
      "status text " . quotemeta($text);
  }
  for my $code ("302\r\nX: 1", "abc", "3020") {
    my $q = new_cgi();
    $q->header(-type => '');
    $q->{_status} = $code;
    like dies { $q->as_cgi_header }, qr/^Invalid status code/,
      "status code " . quotemeta($code);
  }
};

subtest "serializing does not output partially" => sub {
  my $q = new_cgi();
  $q->header(-type => 'text/plain');
  push @{$q->{_response_headers}}, 'X-Bad' => "\n";
  my $out;
  ok dies { $out = $q->as_cgi_header };
  is $out, undef;
  ok dies { $out = $q->as_cgi_response };
  is $out, undef;
};

done_testing;

package EvilCookie;
use overload '""' => sub { "a=1\r\nSet-Cookie: evil=1" };
