#!/usr/bin/env perl
# Compare as_cgi_header() with the output of CGI.pm's header()/redirect().
use strict;
use warnings;

use File::Basename ();
use FindBin;
use lib File::Basename::dirname($FindBin::Bin) . "/lib";

use Test2::V0;

BEGIN {
  eval { require CGI; CGI->VERSION(4.0); 1 }
    or skip_all "CGI.pm (>= 4.0) is not installed";
}

use CGI::PSGI::Minimum ();

require CGI::Cookie;
my $cookie = CGI::Cookie->new(-name => 'U', -value => '1000', -path => '/');

# CGI.pm compares cookie values with `ne`, so this needs overload fallback.
my $my_cookie = CGI::PSGI::Minimum->new(+{})
  ->cookie(-name => 'V', -value => '2', -path => '/');

# NOTE: Cases below avoid known, intentional differences:
#  - charset is appended only to text/* unless -charset is given
#  - arbitrary headers keep the argument order (CGI.pm sorts them)
#  - with no header lines at all (-type => ''), CGI.pm returns "\r\n\r\n"
#    while as_cgi_header returns "\r\n"
my @cases = (
  [header => ()],
  [header => 'text/plain'],
  [header => -type => 'text/plain', -charset => 'utf-8'],
  [header => -Status => '400', -Type => 'text/plain'],
  [header => -status => 400, '-X-Error-Reason' => 'NCK'],
  [header => -type => 'text/html', '-Content-Length' => 1234],
  [header => -target => 'frame1'],
  [header => -status => '302 Found', -cookie => 'U=1000; path=/'],
  [header => -cookie => ['a=1', '', undef, $cookie]],
  [header => -cookie => $cookie, -expires => '+2h'],
  [header => -cookie => $my_cookie],
  [header => -cookie => ['a=1', $my_cookie, $cookie]],
  [header => -attachment => 'a"b.txt', -type => 'text/plain'],
  [header => -p3p => [qw(CAO DSP)]],
  [header => -expires => 'now', -x_foo => 'bar'],
  [header => -nph => 0, -type => 'text/plain'],
  [header => -content_type => 'text/plain', -type => 'text/csv'],
  [header => -x_foo => "a\r\n b"],
  [header => {-type => 'text/plain', -status => 201}],
  [redirect => 'http://example.com/'],
  [redirect => -location => 'thanks.html', -cookie => 'U=1000; path=/'],
  [redirect => -location => 'x.html', -cookie => [$cookie], -status => 301, '-X-Foo' => 1],
  [redirect => -uri => 'x.html', -status => '303 See Other', -target => 'f1'],
  [redirect => -url => 'x.html', -Type => 'text/html'],
  [redirect => -location => 'x.html', -nph => 0],
);

for my $c (@cases) {
  my ($method, @args) = @$c;
  my $label = "$method(" . join(", ", map {
    !defined $_ ? 'undef' : ref $_ ? ref $_ : "'$_'"
  } @args) . ")";
  $label =~ s/\r\n/\\r\\n/g;

  my $q = CGI::PSGI::Minimum->new(+{});
  $q->$method(@args);
  my $mine = $q->as_cgi_header;

  my $theirs = CGI->new(+{})->$method(@args);

  s/^(?:Date|Expires): [^\r\n]*\r\n//mg for $mine, $theirs;

  is $mine, $theirs, $label;
}

subtest "cache(1)" => sub {
  my $q = CGI::PSGI::Minimum->new(+{});
  $q->cache(1);
  $q->header;
  my $cgi = CGI->new(+{});
  $cgi->cache(1);
  is $q->as_cgi_header, $cgi->header;
};

subtest "injection errors" => sub {
  for my $args (
    [-x_foo => "a\r\nb"],
    [-type => "text/html\nX: 1"],
  ) {
    my $mine   = dies { CGI::PSGI::Minimum->new(+{})->header(@$args) };
    my $theirs = dies { CGI->new(+{})->header(@$args) };
    ok $theirs, "CGI.pm dies too";
    like $mine, qr/^Invalid header value contains a newline not followed by whitespace: /;
  }
};

done_testing;
