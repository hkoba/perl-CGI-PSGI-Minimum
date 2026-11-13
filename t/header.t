#!/usr/bin/env perl
use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test2::V0;

use CGI::PSGI::Minimum ();

my $NOW = 1700000000;           # Tue, 14 Nov 2023 22:13:20 GMT
my $NOW_STR = 'Tue, 14 Nov 2023 22:13:20 GMT';
{
  no warnings 'redefine';
  *CGI::PSGI::Minimum::_now = sub { $NOW };
}

sub new_cgi { CGI::PSGI::Minimum->new(+{}) }

# Returns ($status, \@headers) after calling header(@args)
sub hdr {
  my $q = new_cgi();
  my $ret = $q->header(@_);
  is $ret, "", "header() returns empty string";
  ($q->{_status}, $q->{_response_headers}, $q);
}

my $HTML = ['Content-Type' => 'text/html; charset=ISO-8859-1'];

subtest "defaults" => sub {
  my ($status, $headers, $q) = hdr();
  is $status, 200, "default status";
  is $headers, $HTML, "default type";
  is $q->{_status_text}, undef, "status text is undef when not specified";
};

subtest "single argument is type" => sub {
  my (undef, $headers) = hdr('text/plain');
  is $headers, ['Content-Type' => 'text/plain; charset=ISO-8859-1'];

  (undef, $headers) = hdr('image/png');
  is $headers, ['Content-Type' => 'image/png'], "charset only for text/*";
};

subtest "key normalization and aliases" => sub {
  for my $key (qw(-type -Type -TYPE -content_type -Content_Type -content-type -Content-Type)) {
    my (undef, $headers) = hdr($key => 'text/plain');
    is $headers, ['Content-Type' => 'text/plain; charset=ISO-8859-1'], $key;
  }

  my ($status) = hdr(-Status => '400', -Type => 'text/plain');
  is $status, 400, "-Status";

  for my $key (qw(-cookie -Cookies -set_cookie -Set-Cookie)) {
    my (undef, $headers) = hdr($key => 'a=1', -type => '');
    is $headers, ['Set-Cookie' => 'a=1', Date => $NOW_STR], $key;
  }

  for my $key (qw(-target -Window_Target -window-target)) {
    my (undef, $headers) = hdr($key => 'frame1', -type => '');
    is $headers, ['Window-Target' => 'frame1'], $key;
  }

  for my $key (qw(-p3p -P3P -p3p_policy)) {
    my (undef, $headers) = hdr($key => 'CAO', -type => '');
    is $headers, [P3P => 'policyref="/w3c/p3p.xml", CP="CAO"'], $key;
  }

  my (undef, $headers) = hdr({-type => 'text/plain', -status => 404});
  is $headers, ['Content-Type' => 'text/plain; charset=ISO-8859-1'], "hash ref";

  (undef, $headers) = hdr(-content_type => 'text/plain', -type => 'text/csv');
  is $headers, ['Content-Type' => 'text/plain; charset=ISO-8859-1'],
    "-content_type is preferred over -type (same as CGI.pm)";

  my (undef, undef, $q) = hdr(-nph => 1);
  is $q->{_response_headers}, $HTML, "-nph is accepted and ignored";

  like dies { new_cgi()->header(-type => 'text/plain', '-status') },
    qr/^Odd number of arguments/, "odd number of arguments";
};

subtest "charset" => sub {
  my (undef, $headers) = hdr(-type => 'text/plain', -charset => 'utf-8');
  is $headers, ['Content-Type' => 'text/plain; charset=utf-8'];

  (undef, $headers) = hdr(-type => 'application/json', -charset => 'utf-8');
  is $headers, ['Content-Type' => 'application/json; charset=utf-8'],
    "explicit charset is applied to any type";

  (undef, $headers) = hdr(-type => 'application/json');
  is $headers, ['Content-Type' => 'application/json'];

  (undef, $headers) = hdr(-type => 'text/plain; charset=EUC-JP');
  is $headers, ['Content-Type' => 'text/plain; charset=EUC-JP'],
    "type which already has charset";

  my $q = new_cgi();
  $q->header(-charset => 'utf-8');
  is $q->charset, 'utf-8', "-charset sets the default charset";
  $q->header(-type => 'text/plain');
  is $q->{_response_headers}, ['Content-Type' => 'text/plain; charset=utf-8'];

  $q = new_cgi();
  $q->charset('Shift_JIS');
  $q->header;
  is $q->{_response_headers}, ['Content-Type' => 'text/html; charset=Shift_JIS'];
};

subtest "empty type" => sub {
  my (undef, $headers) = hdr(-type => '');
  is $headers, [], "no Content-Type";
};

subtest "cookie" => sub {
  my $q = new_cgi();
  my $c1 = $q->cookie(-name => 'U', -value => '1000', -path => '/');
  my $c2 = $q->cookie(-name => 'V', -value => '2');

  my (undef, $headers) = hdr(-cookie => 'a=1');
  is $headers, ['Set-Cookie' => 'a=1', Date => $NOW_STR, @$HTML], "scalar";

  (undef, $headers) = hdr(-cookie => $c1);
  is $headers, ['Set-Cookie' => 'U=1000; path=/', Date => $NOW_STR, @$HTML],
    "Cookie object";

  (undef, $headers) = hdr(-cookie => ['a=1', '', undef, $c1, $c2]);
  is $headers, ['Set-Cookie' => 'a=1',
                'Set-Cookie' => 'U=1000; path=/',
                'Set-Cookie' => 'V=2',
                Date => $NOW_STR, @$HTML],
    "array: multiple Set-Cookie, empty elements are removed";

  (undef, $headers) = hdr(-cookie => '');
  is $headers, $HTML, "empty cookie";

  like dies { new_cgi()->header(-cookie => {a => 1}) },
    qr/^Invalid cookie value \(unblessed reference\)/;
};

subtest "target, attachment, p3p" => sub {
  my (undef, $headers) = hdr(-target => 'frame1');
  is $headers, ['Window-Target' => 'frame1', @$HTML];

  (undef, $headers) = hdr(-attachment => 'foo.txt', -type => 'text/plain');
  is $headers, ['Content-Disposition' => 'attachment; filename="foo.txt"',
                'Content-Type' => 'text/plain; charset=ISO-8859-1'];

  (undef, $headers) = hdr(-attachment => 'a"b\\c.txt', -type => '');
  is $headers, ['Content-Disposition' => 'attachment; filename="a\\"b\\\\c.txt"'],
    "quotes and backslashes are escaped";

  (undef, $headers) = hdr(-p3p => [qw(CAO DSP COR)], -type => '');
  is $headers, [P3P => 'policyref="/w3c/p3p.xml", CP="CAO DSP COR"'];
};

subtest "arbitrary headers" => sub {
  my (undef, $headers) = hdr(-type => 'application/pdf', '-Content-Length' => 1234);
  is $headers, ['Content-length' => 1234, 'Content-Type' => 'application/pdf'];

  my $status;
  ($status, $headers) = hdr(-status => 400, '-X-Error-Reason' => 'NCK');
  is $status, 400;
  is $headers, ['X-error-reason' => 'NCK', @$HTML];

  (undef, $headers) = hdr(-x_foo => 'bar', -type => '');
  is $headers, ['X-foo' => 'bar'], "underscore becomes dash";

  (undef, $headers) = hdr('X-Raw-Name' => 1, -x_b => 2, 'X-C' => 3, -type => '');
  is $headers, ['X-Raw-Name' => 1, 'X-b' => 2, 'X-C' => 3],
    "keys without dash are used as is, argument order is kept";

  (undef, $headers) = hdr(-x_a => 1, -X_A => 2, -type => '');
  is $headers, ['X-a' => 2], "same normalized name: last one wins";

  (undef, $headers) = hdr(-x_a => undef, -type => '');
  is $headers, [], "undef value is skipped";

  require URI;
  (undef, $headers) = hdr(-x_uri => URI->new('http://example.com/'), -type => '');
  is $headers, ['X-uri' => 'http://example.com/'], "objects are stringified";

  like dies { new_cgi()->header(-x_a => [1]) },
    qr/^Invalid X-a value \(unblessed reference\)/;
};

subtest "status" => sub {
  my ($status, undef, $q) = hdr(-status => "400");
  is $status, 400;
  is $q->{_status_text}, "400";
  like $q->as_cgi_header, qr/\AStatus: 400\r\n/;

  ($status, undef, $q) = hdr(-status => "302 Found");
  is $status, 302;
  is $q->{_status_text}, "302 Found";
  like $q->as_cgi_header, qr/\AStatus: 302 Found\r\n/;

  ($status, undef, $q) = hdr(-status => '');
  is $status, 200;
  is $q->{_status_text}, undef, "empty status is unspecified";

  like dies { new_cgi()->header(-status => 'Found') }, qr/^Invalid status: Found/;
};

subtest "cache" => sub {
  my $q = new_cgi();
  is $q->cache, undef, "default is undef";
  $q->header;
  is $q->{_response_headers}, $HTML, "no Pragma by default";

  is $q->cache(1), 1;
  $q->header;
  is $q->{_response_headers}, [Pragma => 'no-cache', @$HTML],
    "cache(1) means do NOT cache";

  is $q->cache(0), 1, "false value is ignored (same as CGI.pm)";
  is $q->cache(''), 1;
};

subtest "expires and Date" => sub {
  my @cases = (
    ['now'   => $NOW_STR],
    ['+30s'  => 'Tue, 14 Nov 2023 22:13:50 GMT'],
    ['+10m'  => 'Tue, 14 Nov 2023 22:23:20 GMT'],
    ['+2h'   => 'Wed, 15 Nov 2023 00:13:20 GMT'],
    ['-1d'   => 'Mon, 13 Nov 2023 22:13:20 GMT'],
    ['+3M'   => 'Mon, 12 Feb 2024 22:13:20 GMT'],
    ['+10y'  => 'Fri, 11 Nov 2033 22:13:20 GMT'],
    [0 + 86400 => 'Fri, 02 Jan 1970 00:00:00 GMT'],
    ['Thursday, 25-Apr-1999 00:40:33 GMT' => 'Thursday, 25-Apr-1999 00:40:33 GMT'],
  );
  for my $c (@cases) {
    my ($spec, $expect) = @$c;
    my (undef, $headers) = hdr(-expires => $spec, -type => '');
    is $headers, [Expires => $expect, Date => $NOW_STR], "expires $spec";
  }

  my (undef, $headers) = hdr(-expires => '+1h', -cookie => 'a=1', -type => '');
  is $headers, ['Set-Cookie' => 'a=1',
                Expires => 'Tue, 14 Nov 2023 23:13:20 GMT',
                Date => $NOW_STR], "only one Date for expires + cookie";

  (undef, $headers) = hdr(-expires => 0, -type => '');
  is $headers, [], "false expires is ignored (same as CGI.pm)";
};

subtest "header order" => sub {
  my $q = new_cgi();
  $q->cache(1);
  $q->header(-type => 'text/plain', -x_foo => 1, -attachment => 'a.txt',
             -expires => 'now', -cookie => 'c=1', -p3p => 'CAO',
             -target => 'f', -status => 201);
  is $q->{_response_headers}, [
    'Window-Target' => 'f',
    P3P => 'policyref="/w3c/p3p.xml", CP="CAO"',
    'Set-Cookie' => 'c=1',
    Expires => $NOW_STR,
    Date => $NOW_STR,
    Pragma => 'no-cache',
    'Content-Disposition' => 'attachment; filename="a.txt"',
    'X-foo' => 1,
    'Content-Type' => 'text/plain; charset=ISO-8859-1',
  ];
};

subtest "last header() call wins" => sub {
  my $q = new_cgi();
  $q->header(-status => 404, -x_a => 1);
  $q->header(-type => 'text/plain');
  is $q->{_status}, 200;
  is $q->{_status_text}, undef;
  is $q->{_response_headers}, ['Content-Type' => 'text/plain; charset=ISO-8859-1'];
};

subtest "psgi_header" => sub {
  my $q = new_cgi();
  my @ret = $q->psgi_header(-status => 404, -type => 'text/plain');
  is \@ret, [404, ['Content-Type' => 'text/plain; charset=ISO-8859-1']];
  ok $q->has_header;
};

done_testing;
