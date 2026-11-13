package CGI::PSGI::Minimum;
use 5.010;
use strict;
use warnings;

our $VERSION = "0.03";

use constant WARN_CGI_GLOBAL_CALLS => $ENV{WARN_CGI_GLOBAL_CALLS};

#========================================

use Carp ();
use Scalar::Util ();
use URI::Escape ();
use URI;
use Encode ();
use Plack::Request ();
use Plack::Response ();

use MOP4Import::PSGIEnv qw(
  HTTP_X_FORWARDED_HOST
);

use Tie::IxHash;

our $USE_PARAM_SEMICOLONS = 1;

use MOP4Import::Opts;

our $ALSO_SETENV = 0;
sub declare_also_setenv {
  (my $myPack, my Opts $opts, my ($bool)) = m4i_args(@_);
  $ALSO_SETENV = $bool // 1;
}

# Equivalent of CGI.pm's `use CGI -utf8`. When true, values retrieved by
# param() are decoded from UTF-8, following the same rules as CGI.pm:
# only values are decoded (not names); references (uploads), utf8-flagged
# values and PUTDATA/POSTDATA/PATCHDATA are returned as is.
our $PARAM_UTF8 = 0;
sub declare_param_utf8 {
  (my $myPack, my Opts $opts, my ($bool)) = m4i_args(@_);
  $PARAM_UTF8 = $bool // 1;
}

#========================================

use MOP4Import::Base::IOHandle -as_base
  , [fields =>
     [charset => default => "ISO-8859-1", no_getter => 1],
     qw(
       env
       _request
       _parameters
       _query_parameters

       _status
       _status_text
       _response_headers
       _header_called
       _cache

       .cookies
       .raw_cookies
     )
   ]
  ;

use MOP4Import::Util qw(
  lock_keys_as
);

use MOP4Import::Types
  URL_Opts => [
    [fields => qw(
      -full
      -absolute
      -relative
      -path
      -path_info
      -query
    )]
  ],
  Cookie_Opts => [
    [fields => qw(
      -name
      -value
      -path
      -domain
      -expires
      -httponly
      -samesite
      -secure
      -max-age
      -priority
    )]
  ]
  ;

#========================================

sub _reset_globals {
  warn "_reset_globals is called!" if WARN_CGI_GLOBAL_CALLS;
}

sub new {
  my ($class, $env) = @_;
  $class->SUPER::new(env => $env);
}

sub request {
  my MY $prop = (my $glob = shift)->prop;
  $prop->{_request} //= do {
    Plack::Request->new($prop->{env});
  }
}

sub response {
  my MY $prop = (my $glob = shift)->prop;
  Plack::Response->new(
    $prop->{_status} // 200,
    $prop->{_response_headers} // [],
  );
}

sub psgi_tuple {
  my MY $prop = (my $glob = shift)->prop;
  [$prop->{_status} // 200
   , $prop->{_response_headers} // []
   , [$glob->as_bytes]];
}

#========================================

sub parameters {
  my MY $prop = (my $glob = shift)->prop;

  $prop->{_parameters} //= do {
    my Env $env = $prop->{env};
    if (not defined $env->{CONTENT_TYPE}
        and ($env->{REQUEST_METHOD} // '') eq 'POST') {
      $env->{CONTENT_TYPE} = 'application/x-www-form-urlencoded';
    }

    $glob->_fill_ixhash(
      $glob->_build_ixhash(%{$glob->query_parameters}),
      @{$glob->request->_body_parameters},
    );
  }
}

sub query_parameters {
  my MY $prop = (my $glob = shift)->prop;

  $prop->{_query_parameters} //= do {

    my Env $env = $prop->{env};

    if ($env->{QUERY_STRING} =~ /[&=;]/) {

      $glob->_fill_ixhash(
        $glob->_build_ixhash,
        @{$glob->request->_query_parameters}
      );

    }
    elsif ($env->{QUERY_STRING} ne '') {
      my $tosplit = URI::Escape::uri_unescape($env->{QUERY_STRING});
      $tosplit =~ tr/+/ /;
      my @keywords = split /\s+/, $tosplit;

      $glob->_build_ixhash(keywords => \@keywords);

    }
    else {
      $glob->_build_ixhash;
    }
  }
}

# Build IxHash as-is. (Value part should be an ARRAY).
sub _build_ixhash {
  my $pack = shift;
  tie my %params, 'Tie::IxHash', @_; # XXX: [undef] can be assigned.
  \%params;
}

sub _fill_ixhash {
  my ($self, $ixhash, @kvlist) = @_;
  while (my ($k, $v) = splice @kvlist, 0, 2) {
    push @{$ixhash->{$k}}, $v if defined $v;
  }
  $ixhash;
}

#========================================

sub query_string {
  my MY $prop = (my $glob = shift)->prop;

  my $parameters = $glob->parameters;

  my $sep = $USE_PARAM_SEMICOLONS ? ";" : "&";

  join $sep, map {
    my $key = $_;
    my $ekey = _escape($key);
    map {
      join "=", $ekey, _escape($_);
    } @{$parameters->{$key}}
  } keys %$parameters
}

# Equivalent of CGI.pm's _decode_utf8
sub _decode_utf8 {
  my ($val) = @_;
  return $val if ref $val or not defined $val or Encode::is_utf8($val);
  Encode::decode(utf8 => $val);
}

# Equivalent of CGI::escape: encode utf8-flagged strings to UTF-8 before escaping
sub _escape {
  my ($str) = @_;
  utf8::encode($str) if utf8::is_utf8($str);
  URI::Escape::uri_escape($str);
}

sub url_param {
  my MY $prop = (my $glob = shift)->prop;
  my ($name) = @_;

  my $parameters = $glob->query_parameters;

  if (not defined $name) {
    keys %$parameters
  }
  else {
    my $vals = $parameters->{$name};
    return () unless $vals;
    wantarray ? @$vals : $vals->[0];
  }
}

sub param {
  my MY $prop = (my $glob = shift)->prop;

  my $parameters = $glob->parameters;

  if (not @_) {
    # To preserve original key order.
    keys %$parameters;
  }
  elsif (@_ == 1) {
    # get
    my @vals = @{$parameters->{$_[0]} // []};
    if ($PARAM_UTF8 and $_[0] !~ /^(?:PUTDATA|POSTDATA|PATCHDATA)\z/) {
      @vals = map {_decode_utf8($_)} @vals;
    }
    if (wantarray) {
      @vals;
    } else {
      $vals[0];
    }
  }
  else {
    # set. Like CGI.pm, undef values are ignored, and when no defined
    # value is given, the parameter is left untouched.
    my @values = grep {defined} @_[1..$#_];
    $parameters->{$_[0]} = \@values if @values;
  }
}

sub delete {
  my MY $prop = (my $glob = shift)->prop;

  my $parameters = $glob->parameters;

  CORE::delete $parameters->{$_[0]};
}

sub keywords {
  my MY $prop = (my $glob = shift)->prop;

  my $keywords = $glob->parameters->{keywords}
    or return;

  @$keywords;
}

#========================================

sub self_url {
  shift->url(-full => 1, -query => 1, -path => 1);
}

sub url {
  my MY $prop = (my $glob = shift)->prop;

  my URL_Opts $opts = $glob->lock_keys_as(URL_Opts, +{@_});

  my Env $env = $prop->{env};

  my $uri = $env->{SCRIPT_NAME} // '';

  my $URL;
  if ($opts->{-absolute}) {
    $URL = $uri
  }
  elsif ($opts->{-relative}) {
    ($URL) = $uri =~ m!([^/]+)$!
  }
  else {
    # full
    $URL = $glob->protocol . "://";
    $URL .= $env->{SERVER_NAME};

    my $std_port = $env->{HTTPS} ? 443 : 80;
    $URL .= ":$env->{SERVER_PORT}"
      if $env->{SERVER_PORT} != $std_port;

    $URL .= $uri;
  }

  if (($opts->{-path} // $opts->{-path_info}) and $env->{PATH_INFO}) {
    $URL .= $env->{PATH_INFO}
  }
  if ($opts->{-query} and (my $qs = $glob->query_string) ne '') {
    $URL .= "?$qs";
  }

  URI->new($URL)->canonical->as_string;
}

# Same as CGI.pm: http('User-Agent'), http('user_agent') and
# http('HTTP_USER_AGENT') all return HTTP_USER_AGENT.
sub http {
  my MY $prop = (my $glob = shift)->prop;
  if (defined(my $key = $_[0])) {
    $key =~ tr/-a-z/_A-Z/;
    $key = "HTTP_$key" unless $key =~ /^HTTP(?:_|$)/;
    $prop->{env}{$key};
  } else {
    grep { /^HTTP (?:_ | $ )/x } sort keys %{$prop->{env}}
  }
}

sub protocol {
  my MY $prop = (my $glob = shift)->prop;
  my Env $env = $prop->{env};
  if ($env->{HTTPS} || $env->{SERVER_PORT} == 443) {
    'https'
  } else {
    my ($protocol, $version) = split m{/}, $env->{SERVER_PROTOCOL};
    lc($protocol);
  }
}

sub virtual_host {
  my MY $prop = (my $glob = shift)->prop;
  my Env $env = $prop->{env};
  my $vh = $env->{HTTP_X_FORWARDED_HOST}
    || $env->{HTTP_HOST}
    || $env->{SERVER_NAME};
  $vh =~ s/:\d+$//;
  $vh;
}

sub virtual_port {
  my MY $prop = (my $glob = shift)->prop;
  my Env $env = $prop->{env};
  my $vh = $env->{HTTP_X_FORWARDED_HOST}
    || $env->{HTTP_HOST}
    || $env->{SERVER_NAME};
  if ($vh) {
    ($vh =~ / :(\d+)$ /x )[0] || ($glob->protocol eq 'https' ? 443 : 80);
  } else {
    $glob->server_port
  }
}

sub charset {
  my MY $prop = (my $glob = shift)->prop;
  my ($charset) = @_;
  $prop->{charset} = $charset if defined $charset;
  $prop->{charset};
}

#========================================
# Response headers (CGI.pm compatible header() / redirect())
#
# header() and redirect() do not return the header string. Instead, they
# store the PSGI response status and headers into this object
# (_status / _status_text / _response_headers) and return "". This lets
# CGI.pm style code `print $cgi->header(...)` work as is. Use
# as_cgi_header() to serialize the stored headers in CGI style.
#========================================

our $CRLF = "\015\012";

# RFC 9110 token
our $HEADER_NAME_RE = qr/\A[!#\$%&'*+\-.^_`|~0-9A-Za-z]+\z/;

# "302", "302 Found". No control characters.
our $STATUS_TEXT_RE = qr/\A\d{3}(?: [^\x00-\x1F\x7F]*)?\z/;

# normalized key => canonical name.
our %HEADER_KNOWN_KEYS = (
  'type'          => 'type',
  'content-type'  => 'type',
  'status'        => 'status',
  'cookie'        => 'cookie',
  'cookies'       => 'cookie',
  'set-cookie'    => 'cookie',
  'target'        => 'target',
  'window-target' => 'target',
  'expires'       => 'expires',
  'nph'           => 'nph',
  'charset'       => 'charset',
  'attachment'    => 'attachment',
  'p3p'           => 'p3p',
  'p3p-policy'    => 'p3p',
);

our %REDIRECT_KNOWN_KEYS = (
  'location'      => 'location',
  'uri'           => 'location',
  'url'           => 'location',
  'status'        => 'status',
  'cookie'        => 'cookie',
  'cookies'       => 'cookie',
  'set-cookie'    => 'cookie',
  'target'        => 'target',
  'nph'           => 'nph',
);

sub header {
  my MY $prop = (my $glob = shift)->prop;

  $glob->psgi_header(@_);

  "";
}

sub psgi_header {
  my MY $prop = (my $glob = shift)->prop;

  my ($known, $rest) = $glob->_split_header_args(
    \%HEADER_KNOWN_KEYS, 'type', @_
  );

  # Build everything first, so that croak leaves previous state untouched.
  my ($code, $status_text, $headers) = $glob->_build_response_headers(
    $known, $glob->_extra_headers($rest)
  );

  $prop->{_status}           = $code;
  $prop->{_status_text}      = $status_text;
  $prop->{_response_headers} = $headers;
  $prop->{_header_called}    = 1;

  return $prop->{_status}, $prop->{_response_headers};
}

# Equivalent of CGI.pm's `CGI::Util::rearrange_header`, except:
#
# - Only `-name => value` pairs (or a single hash ref) are interpreted.
#   CGI.pm's positional form is not supported. Keys without the leading `-`
#   are kept as is as literal header names (historical behavior of this module).
# - Arbitrary headers keep their argument order (CGI.pm sorts them).
#
# Returns (\%known, \@rest) where @rest is a flat key/value list of
# unknown keys, in the order of appearance.
sub _split_header_args {
  my ($glob, $known_keys, $single_key, @args) = @_;

  if (@args == 1 and ref $args[0] eq 'HASH') {
    my $hash = $args[0];
    @args = map {($_ => $hash->{$_})} sort keys %$hash;
  }
  elsif (@args == 1) {
    return +{$single_key => $args[0]}, [];
  }

  if (@args % 2) {
    Carp::croak "Odd number of arguments: "
      . MOP4Import::Util::terse_dump(\@args);
  }

  my (%known, %prio, @rest);
  while (my ($key, $value) = splice @args, 0, 2) {
    Carp::croak "Undefined header argument name" unless defined $key;
    if ($key =~ /^-/ and my $canon = $known_keys->{_normalize_key($key)}) {
      # Like CGI.pm, -content_type is preferred over -type
      # regardless of the argument order (See GH #155 of CGI.pm).
      my $prio = _normalize_key($key) =~ /content/ ? 1 : 0;
      next if ($prio{$canon} // 0) > $prio;
      $prio{$canon} = $prio;
      $known{$canon} = $value;
    } else {
      push @rest, $key, $value;
    }
  }

  (\%known, \@rest);
}

sub _normalize_key {
  (my $key = lc $_[0]) =~ s/^-//;
  $key =~ tr/_/-/;
  $key;
}

# Convert unknown keys into a list of [$name, $value].
# `-x_foo => 1` becomes "X-foo: 1" (same as CGI.pm), while keys without
# the leading `-` are used as is.
sub _extra_headers {
  my ($glob, $rest) = @_;
  my (@extra, %pos);
  my @kv = @$rest;
  while (my ($key, $value) = splice @kv, 0, 2) {
    if ($key =~ /^-/) {
      my $name = ucfirst _normalize_key($key);
      if (defined(my $i = $pos{$name})) {
        # Same normalized name is given twice. Last one wins (as CGI.pm).
        $extra[$i][1] = $value;
      } else {
        $pos{$name} = @extra;
        push @extra, [$name, $value];
      }
    } else {
      push @extra, [$key, $value];
    }
  }
  \@extra;
}

sub _build_response_headers {
  my ($glob, $known, $extra) = @_;

  my ($type, $status, $cookie, $target, $expires, $charset, $attachment, $p3p)
    = @{$known}{qw(type status cookie target expires charset attachment p3p)};

  my @cookie;
  for (ref $cookie eq 'ARRAY' ? @$cookie : $cookie) {
    my $cs = _stringify_header_value($_, 'cookie');
    push @cookie, $cs if defined $cs and $cs ne '';
  }
  $p3p = join ' ', @$p3p if ref $p3p eq 'ARRAY';

  $_ = _stringify_header_value($_, 'header')
    for $type, $status, $target, $expires, $charset, $attachment, $p3p;

  _check_header_value($_)
    for $type, $status, @cookie, $target, $expires, $charset, $attachment, $p3p;

  my ($code, $status_text) = (200, undef);
  if (defined $status and $status ne '') {
    $status =~ $STATUS_TEXT_RE
      or Carp::croak "Invalid status: " . _safe_for_message($status);
    ($code, $status_text) = (0 + substr($status, 0, 3), $status);
  }

  $type = 'text/html' unless defined $type;

  $charset = do {
    if (defined $charset) {
      # sets the default charset too (same as CGI.pm)
      $glob->charset($charset)
    }
    elsif ($type =~ m{^text/}) {
      $glob->charset
    }
    else {
      ''
    }
  } // '';

  if ($type ne '' and $type !~ /\bcharset\b/ and $charset ne '') {
    $type .= "; charset=$charset";
  }

  my @header;

  push @header, 'Window-Target' => $target if $target;

  push @header, P3P => qq{policyref="/w3c/p3p.xml", CP="$p3p"} if $p3p;

  push @header, map {('Set-Cookie' => $_)} @cookie;

  # As CGI.pm, when expires is given, Date is also emitted
  # so that the browser uses OUR clock.
  push @header, Expires => $glob->_expires($expires) if $expires;
  push @header, Date => $glob->_expires(0) if $expires || $cookie;

  # Read the field directly (not via ->cache), so that a subclass which
  # has its own, unrelated cache() method does not affect this.
  push @header, Pragma => q{no-cache} if $glob->prop->{_cache};

  if ($attachment) {
    # filename is a quoted-string (RFC 9110 5.6.4).
    (my $filename = $attachment) =~ s/(["\\])/\\$1/g;
    push @header, 'Content-Disposition' => qq{attachment; filename="$filename"};
  }

  foreach my $pair (@$extra) {
    my ($name, $value) = @$pair;
    next unless defined $value;
    _check_header_name($name);
    $value = _stringify_header_value($value, $name);
    _check_header_value($value);
    push @header, $name => $value;
  }

  push @header, 'Content-Type' => $type if $type ne '';

  ($code, $status_text, \@header);
}

sub _stringify_header_value {
  my ($value, $what) = @_;
  return $value unless ref $value;
  if (Scalar::Util::blessed($value)) {
    return "$value";
  }
  Carp::croak "Invalid $what value (unblessed reference): $value";
}

# Same rule as CGI.pm's _check_header_values: "CRLF + whitespace" (folding)
# is unfolded, and any other CR/LF is rejected. NUL is rejected too.
# Modifies $_[0] in place.
sub _check_header_value {
  return unless defined $_[0];

  $_[0] =~ s/$CRLF([ \t])/$1/g if $_[0] =~ /$CRLF/;

  if ($_[0] =~ /[\015\012]/) {
    Carp::croak "Invalid header value contains a newline not followed by whitespace: "
      . _safe_for_message($_[0]);
  }
  if ($_[0] =~ /\0/) {
    Carp::croak "Invalid header value contains a NUL character: "
      . _safe_for_message($_[0]);
  }
}

sub _check_header_name {
  my ($name) = @_;
  unless (defined $name and not ref $name and $name =~ $HEADER_NAME_RE) {
    Carp::croak "Invalid header name: " . _safe_for_message($name);
  }
}

# Shorten and make control characters visible, to avoid log injection
# through error messages.
sub _safe_for_message {
  my ($str) = @_;
  return 'undef' unless defined $str;
  $str = substr($str, 0, 72) . '...' if length $str > 72;
  $str =~ s/([\x00-\x1F\x7F])/sprintf("\\x%02X", ord $1)/ge;
  $str;
}

#----------------------------------------
# Expires / Date. Equivalent of CGI::Util::expires($time, 'http')

# Override this to fix the current time (ex. in tests).
sub _now { time }

sub _expires {
  my ($glob, $time) = @_;
  $time = $glob->_expire_calc($time);
  return $time unless $time =~ /^\d+$/;
  _http_date($time);
}

sub _expire_calc {
  my ($glob, $time) = @_;
  my %mult = (
    's' => 1,
    'm' => 60,
    'h' => 60*60,
    'd' => 60*60*24,
    'M' => 60*60*24*30,
    'y' => 60*60*24*365,
  );
  my $offset;
  if (!$time || lc($time) eq 'now') {
    $offset = 0;
  } elsif ($time =~ /^\d+/) {
    return $time;
  } elsif ($time =~ /^([+-]?(?:\d+|\d*\.\d*))([smhdMy])/) {
    no warnings 'numeric';
    $offset = ($mult{$2} || 1) * $1;
  } else {
    return $time;
  }
  int($glob->_now + $offset);
}

sub _http_date {
  my ($time) = @_;
  my @MON  = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
  my @WDAY = qw/Sun Mon Tue Wed Thu Fri Sat/;
  my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($time);
  sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
          $WDAY[$wday], $mday, $MON[$mon], $year + 1900, $hour, $min, $sec);
}

#----------------------------------------
# CGI.pm compatible cache(). NOTE: cache(1) means "do NOT cache"!

sub cache {
  my MY $prop = (my $glob = shift)->prop;
  my ($new_value) = @_;
  # Same as CGI.pm: only a true value is stored, so it can't be reset.
  $prop->{_cache} = $new_value if $new_value;
  $prop->{_cache};
}

#========================================

sub psgi_redirect {
  my MY $prop = (my $glob = shift)->prop;
  $glob->redirect(@_);

  ($prop->{_status}, $prop->{_response_headers});
}

sub redirect {
  my MY $prop = (my $glob = shift)->prop;

  $glob->psgi_header($glob->_redirect_to_header_args(@_));

  "";
}

# Equivalent of the argument handling of CGI.pm's redirect().
sub _redirect_to_header_args {
  my ($glob, @args) = @_;

  my ($known, $rest) = $glob->_split_header_args(
    \%REDIRECT_KNOWN_KEYS, 'location', @args
  );

  my $status = $known->{status};
  $status = '302 Found' unless defined $status and $status ne '';

  my $url = $known->{location} || $glob->self_url;

  (($known->{cookie} ? (-cookie => $known->{cookie}) : ())
   , -type => ''
   , ($known->{target} ? (-target => $known->{target}) : ())
   , -status => $status
   , -location => $url
   , -nph => $known->{nph}
   , @$rest
  );
}

#========================================
# Serialize the stored headers in CGI style.

sub has_header {
  my MY $prop = (my $glob = shift)->prop;
  $prop->{_header_called} ? 1 : 0;
}

sub as_cgi_header {
  my MY $prop = (my $glob = shift)->prop;

  return "" unless $prop->{_header_called};

  # Do not trust stored values blindly. They can be modified without
  # header() (through prop or the arrayref returned by psgi_header).
  # Validate everything again and fail closed.

  my $out = "";

  if (defined(my $status = $glob->_cgi_status_line)) {
    $out .= "Status: $status$CRLF";
  }

  my $headers = $prop->{_response_headers} // [];
  ref $headers eq 'ARRAY'
    or Carp::croak "Invalid response headers: not an ARRAY ref";
  @$headers % 2 == 0
    or Carp::croak "Invalid response headers: odd number of elements";

  for (my $i = 0; $i < @$headers; $i += 2) {
    my ($name, $value) = @{$headers}[$i, $i+1];
    _check_header_name($name);
    defined $value
      or Carp::croak "Invalid header value for $name: undef";
    $value = _stringify_header_value($value, $name);
    if ($value =~ /[\x00\x0A\x0D]/) {
      Carp::croak "Invalid header value for $name contains CR, LF or NUL: "
        . _safe_for_message($value);
    }
    $out .= "$name: $value$CRLF";
  }

  $out . $CRLF;
}

# Status line is emitted only when explicitly specified (same as CGI.pm).
# If _status was modified without header(), _status is used.
sub _cgi_status_line {
  my MY $prop = (my $glob = shift)->prop;
  my ($code, $text) = @{$prop}{qw(_status _status_text)};

  if (defined $text and $text !~ $STATUS_TEXT_RE) {
    Carp::croak "Invalid status text: " . _safe_for_message($text);
  }
  if (defined $code and $code !~ /\A\d{3}\z/) {
    Carp::croak "Invalid status code: " . _safe_for_message($code);
  }

  if (defined $text and (not defined $code or substr($text, 0, 3) eq $code)) {
    $text;
  }
  elsif (defined $code and (defined $text or $code != 200)) {
    $code;
  }
  else {
    undef;
  }
}

sub as_cgi_response {
  my MY $prop = (my $glob = shift)->prop;
  $glob->as_cgi_header . ($glob->as_bytes // '');
}

#========================================
# Discard the response (headers and body) built so far, e.g. to emit an
# error response instead. Request side state and response settings
# (env, parameters, cookies, charset, encoding, _cache) are kept.

sub reset_response {
  my MY $prop = (my $glob = shift)->prop;

  # Body. Keep the filehandle (and layers added by binmode) as is:
  # flush pending output, rewind the position (otherwise the next print
  # would be written at the old position, leaving NULs before it), then
  # empty the scalar the filehandle is opened on (don't replace the ref).
  $glob->flush;
  seek $glob, 0, 0;
  ${$prop->{_buffer}} = "" if ref $prop->{_buffer};

  # Headers.
  $prop->{$_} = undef
    for qw(_status _status_text _response_headers _header_called);

  $glob;
}

#========================================
sub raw_cookie {
  my MY $prop = (my $glob = shift)->prop;
  if (defined $_[0]) {
    # cache せず、生成し直す。

    my $hash = $prop->{'.raw_cookies'} = do {
      my $cookies = $glob->request->cookies;
      my %hash;
      foreach my $name (keys %$cookies) {
        $hash{$name} = URI::Escape::uri_escape($cookies->{$name});
      }
      \%hash;
    };

    $hash->{$_[0]};
  }
  else {
    my Env $env = $prop->{env};
    $env->{HTTP_COOKIE};
  }
}

sub cookie {
  my MY $prop = (my $glob = shift)->prop;

  if (not @_) {
    # cache せず、生成し直す。
    my $hash = $prop->{'.cookies'} = do {
      my $cookies = $glob->request->cookies;
      my %hash;
      foreach my $name (keys %$cookies) {
        $hash{$name} = $glob->make_cookie(name => $name, value => $cookies->{$name});
      }
      \%hash;
    };
    return keys %$hash;
  }

  my Cookie_Opts $opts = do {
    if (@_ == 1) {
      +{-name => $_[0]}
    }
    elsif (@_ % 2 != 0) {
      Carp::croak "Odd number of arguments! "
        . MOP4Import::Util::terse_dump(\@_)
    }
    else {
      $glob->lock_keys_as(Cookie_Opts, +{@_})
    }
  };

  # CGI.pm 互換: 値(-value)を伴わない呼び出し(cookie('name') /
  # cookie(-name => 'name'))は getter。受信済み cookie を名前で引き、
  # その値(文字列)を返す。従来は名前だけの空 Cookie を生成していたが、
  # それは CGI.pm 非互換で実用上意味が無かった。
  unless (defined $opts->{-value}) {
    my $name = $opts->{-name};
    return unless defined $name;
    my $cookies = $prop->{'.cookies'} // do {
      my $c = $glob->request->cookies;
      +{ map {
        $_ => $glob->make_cookie(name => $_, value => $c->{$_})
      } keys %$c };
    };
    my $found = $cookies->{$name};
    return unless defined $found;
    return ref $found ? $found->value : $found;
  }

  $glob->make_cookie(map {
    $opts->{$_} ? (substr($_, 1) => $opts->{$_}) : ()
  } keys %$opts)
}

{
  sub make_cookie {
    my MY $prop = (my $glob = shift)->prop;
    CGI::PSGI::Minimum::Cookie->new(@_);
  }

  package
    CGI::PSGI::Minimum::Cookie;
  use MOP4Import::Base::Configure -as_base
    , [fields =>qw(
      name
      value
      path
      domain
      expires
      httponly
      samesite
      secure
      max-age
      priority
    )]
    ;

  use overload '""' => 'as_string', fallback => 1;

  sub as_string {
    (my MY $self) = @_;
    Cookie::Baker::bake_cookie($self->{name}, $self);
  }
}


#========================================
{
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
    my $key = uc($method);
    my $sym = MOP4Import::Util::globref(MY, $method);
    *$sym = sub {
      my MY $prop = (my $glob = shift)->prop;
      if (@_) {
        $ENV{$key} = $_[0] if $ALSO_SETENV;
        $prop->{env}->{$key} = $_[0];
      } else {
        $prop->{env}->{$key}
      }
    }
  }

  for my $method (qw(
    user_agent
    referer
  )) {
    my $key = 'HTTP_' . uc($method);
    my $sym = MOP4Import::Util::globref(MY, $method);
    *$sym = sub {
      shift->prop->{env}->{$key}
    }
  }

}

1;
__END__

=encoding utf-8

=head1 NAME

CGI::PSGI::Minimum - Run CGI.pm style application code on PSGI, with a small CGI.pm compatible object

=head1 SYNOPSIS

    # app.psgi
    use CGI::PSGI::Minimum [as => 'CGI'];   # CGI->new means CGI::PSGI::Minimum->new
    use SelectSaver;

    my $app = sub {
      my $env = shift;
      my $cgi = CGI->new($env);
      {
        # Plain print goes to $cgi (the response body) while selected.
        my $saver = SelectSaver->new($cgi);
        MyApp->dispatch($cgi);
      }
      $cgi->psgi_tuple;   # [$status, \@headers, [$body]]
    };

    # MyApp.pm -- application code written for CGI.pm keeps working
    sub cmd_main {
      my ($self, $cgi) = @_;
      print $cgi->header(-type => 'text/html', -charset => 'utf-8');
      print "<h1>Hello, ", escape($cgi->param('name')), "</h1>\n";
    }

    sub cmd_update {
      my ($self, $cgi) = @_;
      ...
      print $cgi->redirect('./');
    }

    # A CGI/FastCGI driver can emit the same response in CGI style
    # after the application finished.
    print STDOUT $cgi->as_cgi_response;   # "Status: ...\r\n...\r\n\r\n" . body

=head1 DESCRIPTION

CGI::PSGI::Minimum lets you run application code written against the
object interface of L<CGI> (CGI.pm) on L<PSGI> servers, with as little
modification of the application code as possible.

It is B<not> a subclass of CGI.pm and does not load it. It is a small,
independent reimplementation of the part of the CGI.pm API which real
world CGI applications use (parameters, URLs, cookies, request
information and response headers), built on L<Plack::Request>. The object
is also a filehandle which collects the response body.

=head2 The idea

A typical CGI.pm application prints its response from anywhere in the
code:

    print $cgi->header;
    print "<html>...";

With CGI::PSGI::Minimum:

=over 4

=item * C<header()> and C<redirect()> do not return the header string.
They store the status and headers into the object and return C<"">, so
C<print $cgi-E<gt>header(...)> prints nothing and keeps working.

=item * The object itself is a filehandle (L<MOP4Import::Base::IOHandle>)
which collects the body. C<select> it (or C<print $cgi ...>) and plain
C<print> goes into the response body. Nothing is written to STDOUT.

=item * After the application finished, C<psgi_tuple()> returns the PSGI
response C<[$status, \@headers, [$body]]>. For CGI/FastCGI, the same
object can be serialized with C<as_cgi_header()> / C<as_cgi_response()>,
so one code base can serve both PSGI and CGI.

=back

The modification needed in the application is usually limited to the
place where the object is created (C<CGI-E<gt>new> becomes
C<CGI::PSGI::Minimum-E<gt>new($env)>, or just C<CGI-E<gt>new($env)> with
C<[as =E<gt> 'CGI']>) and passing that object around instead of using
global state.

=head1 GOALS, AND DIFFERENCES FROM CGI::PSGI

L<CGI::PSGI> ("Adapt CGI.pm to the PSGI protocol") and this module both
put a CGI.pm style object on top of a PSGI C<$env>, and share method
names like C<psgi_header()> and C<psgi_redirect()>. But their goals are
different.

=head2 CGI::PSGI: let frameworks use CGI.pm under PSGI

CGI::PSGI is meant for web B<framework developers> who use CGI.pm to
handle query parameters and want their framework to speak PSGI. It
assumes that the framework already collects the response body in one
place, and asks that place to build the PSGI response by itself:

    my $q = CGI::PSGI->new($env);
    ...
    return [ $q->psgi_header, [ $body ] ];

=over 4

=item * It B<is> CGI.pm: a subclass of CGI (C<use base qw(CGI)>). All of
CGI.pm's features are available, and its behavior is CGI.pm's behavior.

=item * To make CGI.pm (which reads C<%ENV> and STDIN) work with
C<$env>, it localizes C<%ENV> to C<$env> in C<new> and in about 30 wrapped
methods, reads the request body from C<psgi.input>, and resets CGI.pm's
globals with C<CGI::initialize_globals()>.

=item * Application code that does C<print $q-E<gt>header> has to be
changed: C<header()> still returns a string as in CGI.pm, and nothing
captures the output of C<print>. For end users who want to run plain CGI
scripts, CGI::PSGI points to L<CGI::Emulate::PSGI> instead.

=back

=head2 CGI::PSGI::Minimum: keep CGI.pm style application code working

This module is meant for B<application code> written against CGI.pm,
where C<print $cgi-E<gt>header> and C<print "..."> are scattered all over
the code, and which you want to run on PSGI (and possibly still on
CGI/FastCGI) without rewriting it.

=over 4

=item * The response is collected by the object, not by the caller:
C<header()> / C<redirect()> store into the object and return C<"">, and
the body is printed into the object. The caller only returns
C<$cgi-E<gt>psgi_tuple>.

=item * It is B<not> CGI.pm. It implements only a subset of the API, and
does not load CGI.pm at all. Where an argument is outside of the
supported subset, it croaks rather than silently doing something
different (ex. unknown options of C<url()>).

=item * No global state: it does not touch C<%ENV>, STDIN or STDOUT, and
has no per-process globals to reset (C<_reset_globals> is a no-op). All
request information comes from C<$env> passed to C<new>. (Setting
C<%ENV> from the accessors is possible with C<-also_setenv>, for legacy
code which reads C<%ENV> directly.)

=item * Within the subset, CGI.pm compatibility of the B<behavior> is the
goal, and is tested against CGI.pm itself where possible (ex. the header
string from C<as_cgi_header()> is compared with CGI.pm's C<header()>).

=item * The same object works for CGI/FastCGI drivers too, through
C<as_cgi_header()>, C<as_cgi_response()> and C<reset_response()>.

=back

=head2 Which one to use

=over 4

=item * You write or maintain a framework which already builds the
response body in one place, and want the full CGI.pm: use L<CGI::PSGI>.

=item * You want to run an existing CGI script file as is, including its
use of C<%ENV>, STDOUT and the function interface: use
L<CGI::Emulate::PSGI> (with L<CGI::Compile>), which emulates the CGI
environment for each request.

=item * You have application code using the CGI.pm object interface,
which prints from everywhere, and want it to run on PSGI without global
state and without depending on CGI.pm: use this module.

=back

=head1 IMPORT OPTIONS

Options are given as L<MOP4Import::Declare> pragmas. A pragma without
arguments can be written as C<-NAME> (recommended), and a pragma with
arguments as an array ref C<[NAME =E<gt> ARGS...]>. In the array ref form,
quote the pragma name unless it is followed by C<=E<gt>> (a bare
C<[param_utf8]> is a compile error under C<use strict>):

    use CGI::PSGI::Minimum [as => 'CGI'], -param_utf8;

    # same as above
    use CGI::PSGI::Minimum [as => 'CGI'], ['param_utf8'];

=over 4

=item C<[as =E<gt> 'NAME']>

Defines a constant C<NAME> in the caller, which returns
C<"CGI::PSGI::Minimum">. With C<[as =E<gt> 'CGI']>, C<CGI-E<gt>new($env)>
creates a CGI::PSGI::Minimum object (CGI.pm is not loaded).

=item C<-param_utf8>

Equivalent of CGI.pm's C<use CGI -utf8>: values retrieved by C<param()>
are decoded from UTF-8. Only values are decoded (not names); references,
already decoded values and C<PUTDATA>/C<POSTDATA>/C<PATCHDATA> are
returned as is. This is a process wide setting
(C<$CGI::PSGI::Minimum::PARAM_UTF8>). C<['param_utf8', 0]> turns it off.

=item C<-also_setenv>

Makes the setter form of the request accessors (ex.
C<$cgi-E<gt>request_method('POST')>) also set C<%ENV>. Off by default.
This is a process wide setting (C<$CGI::PSGI::Minimum::ALSO_SETENV>).
C<['also_setenv', 0]> turns it off.

=back

Other package variables and environment variables:

=over 4

=item C<$CGI::PSGI::Minimum::USE_PARAM_SEMICOLONS>

When true (default, same as CGI.pm), C<query_string()> joins pairs with
C<;>, otherwise with C<&>.

=item C<WARN_CGI_GLOBAL_CALLS> (environment variable)

When set at compile time, C<_reset_globals()> warns when called. Useful
to find code which relies on CGI.pm's global state.

=back

=head1 METHODS

=head2 CONSTRUCTOR AND PSGI

=head3 new

    my $cgi = CGI::PSGI::Minimum->new($env);

Creates an object for the PSGI environment C<$env>. Unlike CGI.pm,
C<$env> is required, and query strings or hashes of parameters are not
accepted.

=head3 env

Returns the PSGI environment.

=head3 request

Returns the L<Plack::Request> for C<$env> (created once and cached). Use
it for what this module does not provide, ex. file uploads:
C<$cgi-E<gt>request-E<gt>uploads>.

=head3 psgi_tuple

    return $cgi->psgi_tuple;   # [$status, \@headers, [$body]]

Returns the PSGI response built from the stored headers and the body
printed into the object. If C<header()> / C<redirect()> has not been
called, the status is 200 and the headers are empty.

=head3 response

Returns a L<Plack::Response> with the stored status (default 200) and
headers. The body is not set.

=head3 as_bytes

Returns the body printed into the object so far (flushes first).

=head3 Printing the body

The object is a filehandle. Either print to it explicitly, or C<select>
it (ex. with L<SelectSaver>) so that plain C<print> goes into it:

    print $cgi "text";
    binmode $cgi, ':encoding(utf8)';   # layers can be added as usual

=head2 PARAMETERS

=head3 param

    my @names = $cgi->param;            # names, in the original order
    my $value = $cgi->param('name');    # first value
    my @values = $cgi->param('name');   # all values
    $cgi->param('name', @values);       # set

Parameters from the query string and the request body
(C<application/x-www-form-urlencoded> or C<multipart/form-data>, query
string first) are merged. A POST request without C<Content-Type> is
treated as urlencoded, as CGI.pm does. Like CGI.pm, the setter ignores
undef values, and leaves the parameter untouched when no defined value is
given. Only the positional form of the setter is supported (not
C<-name =E<gt> ..., -value =E<gt> ...>). Uploaded files are not returned;
use C<$cgi-E<gt>request-E<gt>uploads>.

=head3 url_param

    my @names = $cgi->url_param;
    my $value = $cgi->url_param('name');

Same as C<param()>, but only for the query string.

=head3 delete

    $cgi->delete('name');

=head3 keywords

Returns the keywords of an C<isindex> style query string (ex.
C<?mary+had+a+little+lamb>).

=head3 query_string

Returns the parameters (including those set by C<param()>) as a query
string. See C<$USE_PARAM_SEMICOLONS>.

=head3 parameters, query_parameters

Returns the underlying ordered hashes (L<Tie::IxHash>) of all parameters
and of the query string parameters. The values are array refs.

=head2 URL AND REQUEST INFORMATION

=head3 url

    $cgi->url;                         # http://host:port/cgi-bin/foo.cgi
    $cgi->url(-absolute => 1);         # /cgi-bin/foo.cgi
    $cgi->url(-relative => 1);         # foo.cgi
    $cgi->url(-path => 1, -query => 1);

Supported options are C<-full> (default), C<-absolute>, C<-relative>,
C<-path> (or C<-path_info>) and C<-query>. Other options croak.

=head3 self_url

Same as C<url(-full =E<gt> 1, -path =E<gt> 1, -query =E<gt> 1)>.

=head3 http

    my $value = $cgi->http('Accept-Language');   # HTTP_ACCEPT_LANGUAGE
    my @names = $cgi->http;                      # HTTP_* keys (sorted)

Same as CGI.pm: the name is case insensitive, C<-> is treated as C<_>,
and the C<HTTP_> prefix is optional (C<http('User-Agent')>,
C<http('user_agent')> and C<http('HTTP_USER_AGENT')> are the same).

=head3 protocol, virtual_host, virtual_port

Same as CGI.pm. C<virtual_host> and C<virtual_port> honor
C<X-Forwarded-Host>.

=head3 Request accessors

C<auth_type>, C<content_type>, C<path_info>, C<path_translated>,
C<request_method>, C<request_uri>, C<remote_addr>, C<remote_host>,
C<remote_ident>, C<remote_user>, C<script_name>, C<server_name>,
C<server_port>, C<server_protocol> and C<server_software> return the
corresponding value of C<$env>. With an argument, they set it (and also
C<%ENV> with C<-also_setenv>).

C<user_agent> and C<referer> return C<HTTP_USER_AGENT> and C<HTTP_REFERER>.

=head2 COOKIES

=head3 cookie

    my @names = $cgi->cookie;                 # names of received cookies
    my $value = $cgi->cookie('name');         # value of a received cookie
    my $value = $cgi->cookie(-name => 'name');
    my $cookie = $cgi->cookie(-name => 'U', -value => '1000', -path => '/',
                              -expires => '+1d', -httponly => 1);
    print $cgi->header(-cookie => $cookie);

Like CGI.pm, without C<-value> it is a getter of received cookies, and
with C<-value> it creates a cookie object
(C<CGI::PSGI::Minimum::Cookie>, serialized by L<Cookie::Baker>), which
can be passed to C<header(-cookie =E<gt> ...)>. Supported attributes are
C<-name>, C<-value>, C<-path>, C<-domain>, C<-expires>, C<-max-age>,
C<-secure>, C<-httponly>, C<-samesite> and C<-priority>.

=head3 raw_cookie

    my $header = $cgi->raw_cookie;          # HTTP_COOKIE as is
    my $value  = $cgi->raw_cookie('name');  # URI escaped value

=head2 RESPONSE HEADERS

=head3 header

    $cgi->header;                                   # text/html; charset=ISO-8859-1
    $cgi->header('text/plain');                     # single argument is -type
    $cgi->header(-status => '400', -type => 'text/plain');
    $cgi->header(-type => 'application/pdf', '-Content-Length' => $size);
    $cgi->header(-cookie => [$cookie1, $cookie2], -expires => '+1h');

Unlike CGI.pm, C<header()> does B<not> return the header string. It stores
the response into the object and returns C<"">, so that
C<print $cgi-E<gt>header(...)> works as is. The status code is stored in
C<_status> (default 200), the headers in C<_response_headers> (a flat
arrayref of name/value pairs), and the status string as given (ex.
C<"302 Found">) in C<_status_text>. When called multiple times, the last
call wins.

Arguments are interpreted like CGI.pm's C<header()>. Keys are normalized
(the leading C<-> is removed, lowercased, C<_> becomes C<->), so
C<-Type>, C<-type>, C<-content_type> and C<-Content-Type> are the same.
Known keys are C<type> (C<content-type>), C<status>, C<cookie>
(C<cookies>, C<set-cookie>), C<target> (C<window-target>), C<expires>,
C<nph> (accepted and ignored), C<charset>, C<attachment> and C<p3p>
(C<p3p-policy>). A single hash ref is also accepted.

Other C<-name =E<gt> value> pairs become arbitrary headers, named like
CGI.pm: C<-X_Error_Reason> becomes C<X-error-reason>. Keys without the
leading C<-> are used as header names as is.

The headers are stored in the same order as CGI.pm outputs them:
C<Window-Target>, C<P3P>, C<Set-Cookie> (one per cookie), C<Expires>,
C<Date> (when expires or cookie is given), C<Pragma>,
C<Content-Disposition>, arbitrary headers (in the argument order) and
C<Content-Type> (omitted when C<-type =E<gt> ''>).

C<charset> (default C<ISO-8859-1>) is appended to C<text/*> types only,
unless C<-charset> is given explicitly or the type already has a charset.

C<-expires> accepts the same forms as CGI.pm: C<now>, C<+30s>, C<+10m>,
C<+2h>, C<-1d>, C<+3M>, C<+10y>, epoch seconds, or a preformatted date
string. The current time is taken from C<_now()>, which can be overridden.

=head3 psgi_header

    my ($status, $headers) = $cgi->psgi_header(...);

Same as C<header()>, but returns the stored status code and headers.

=head3 redirect

    $cgi->redirect('http://example.com/');
    $cgi->redirect(-location => $url, -status => 301, -cookie => \@cookies,
                   'X-Foo' => 1);

Interprets arguments like CGI.pm's C<redirect()>: C<location> (C<uri>,
C<url>; defaults to C<self_url>), C<status> (default C<"302 Found">),
C<target>, C<cookie> and C<nph>. Other arguments are passed to
C<header()>. C<Content-Type> is not emitted unless C<-type> is given.
Returns C<"">.

=head3 psgi_redirect

Same as C<redirect()>, but returns C<($status, $headers)>.

=head3 charset

    $cgi->charset('utf-8');
    my $charset = $cgi->charset;

Gets or sets the default charset used by C<header()> (default
C<ISO-8859-1>, same as CGI.pm).

=head3 cache

    $cgi->cache(1);
    $cgi->header;     # includes "Pragma: no-cache"

CGI.pm compatible. B<Note that the meaning is inverted from what the name
suggests:> C<cache(1)> (true) means "do NOT cache": C<header()> emits
C<Pragma: no-cache>. The name is misleading, but kept as is for CGI.pm
compatibility. By default (not set) no C<Pragma> header is emitted.
Like CGI.pm, only a true value is stored (C<cache(0)> does not reset it)
and the current value is always returned.

=head3 has_header

True if C<header()> or C<redirect()> has been called.

=head3 as_cgi_header

Serializes the stored response into a CGI style header string, the same
form as CGI.pm's C<header()> returns:

    Status: 302 Found\r\n
    Set-Cookie: U=1000; path=/\r\n
    Date: Tue, 14 Nov 2023 22:13:20 GMT\r\n
    Location: thanks.html\r\n
    \r\n

C<Status> is emitted only when the status was specified explicitly (same
as CGI.pm). Returns C<""> if C<header()>/C<redirect()> has not been called.
Intended for CGI/FastCGI drivers which emit headers after the application
finished, and for tests.

=head3 as_cgi_response

C<as_cgi_header() . as_bytes()>.

=head3 reset_response

    print $cgi $cgi->header, "partial output...";
    # an error occurred
    $cgi->reset_response;
    print $cgi $cgi->header(-status => 500), "error page";

Discards the response built so far, so that an error response can be
emitted instead of the partial one. After this, the object is in the same
state as a newly created one on which C<header()> has not been called yet.
Returns the object itself.

It clears:

=over 4

=item * the headers: C<_status>, C<_status_text>, C<_response_headers> and
C<_header_called>. C<has_header> becomes false, C<as_cgi_header> returns
C<"">, and C<psgi_tuple> / C<response> return the same as a new object.

=item * the body printed to the object. The filehandle is not reopened:
it is flushed, rewound to the beginning, and the buffer is emptied. So
layers added by C<binmode> (ex. C<:encoding(utf8)>) are kept.

=back

It does B<not> clear the request side state (C<env>, parameters, the
request object, cookies) nor the response settings (C<charset>,
C<encoding>, C<cache>). C<cache> is kept because it is a setting rather
than a part of the response: like CGI.pm, once set to true it can not be
reset (only a true value is stored), so clearing it here would silently
change that rule.

It is safe to call on an object without header or body, and any number of
times.

=head1 HEADER INJECTION (HTTP RESPONSE SPLITTING, CWE-113)

Header values often contain user input (redirect targets, cookie values
...). A CR or LF in them would allow injecting arbitrary headers or body.
This module guards against it at two stages:

=over 4

=item When storing (header, redirect, psgi_header, psgi_redirect)

Like CGI.pm, "CRLF + whitespace" (folding) in values is unfolded into the
whitespace, and any other CR or LF makes it croak with
C<Invalid header value contains a newline not followed by whitespace>.
NUL is rejected too, and header names must be RFC 9110 tokens. This
applies to all values: type, status, cookies (after stringification),
target, expires, charset, attachment, p3p, Location and arbitrary headers.
Nothing is stored when it croaks.

=item When serializing (as_cgi_header)

Stored headers can be modified without going through C<header()> (through
the arrayref returned by C<psgi_header()>, or directly through the
object). So C<as_cgi_header()> validates everything again just before
output: names must be RFC 9110 tokens, values must not contain CR, LF or
NUL (folding is not allowed here at all), the status must look like
C<302> or C<302 Found>, and the headers must be an arrayref with an even
number of elements. Any violation makes it croak (fail closed); invalid
characters are never silently removed.

=back

Error messages show control characters escaped (ex. C<\x0D>), to avoid
log injection.

=head1 NOT SUPPORTED

Being a minimum subset, the following parts of CGI.pm are not provided:

=over 4

=item * The function interface (C<use CGI qw(:standard)>, C<param()>
without an object). Only the object interface is supported.

=item * HTML generation (C<start_html>, C<textfield>, ...) and sticky
forms.

=item * File uploads through C<param()> / C<upload()>. Use
C<$cgi-E<gt>request-E<gt>uploads> (L<Plack::Request::Upload>).

=item * C<multi_param>, C<Vars>, C<append>, C<save>, C<restore_parameters>
and other less common methods.

=item * The named form of the C<param()> setter, CGI.pm's positional
argument form of C<header()> / C<redirect()>, and NPH responses
(C<-nph> is accepted and ignored).

=item * Creating an object without C<$env> (from C<%ENV>, a query string
or a hash of parameters).

=back

Known intentional differences within the supported subset:

=over 4

=item * C<header()> / C<redirect()> return C<""> instead of the header
string. Use C<psgi_header()>, C<psgi_tuple()> or C<as_cgi_header()>.

=item * The default charset is appended to C<text/*> types only (CGI.pm
appends it to any type) unless C<-charset> is given.

=item * Arbitrary headers keep the argument order (CGI.pm sorts them).

=item * Header values are validated more strictly (NUL, header names,
status format). See L</HEADER INJECTION (HTTP RESPONSE SPLITTING, CWE-113)>.

=back

=head1 SEE ALSO

L<CGI>, L<CGI::PSGI>, L<CGI::Emulate::PSGI>, L<CGI::Compile>,
L<Plack::Request>, L<PSGI>, L<MOP4Import::Base::IOHandle>

=head1 LICENSE

Copyright (C) Kobayasi, Hiroaki.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kobayasi, Hiroaki E<lt>buribullet@gmail.comE<gt>

=cut

