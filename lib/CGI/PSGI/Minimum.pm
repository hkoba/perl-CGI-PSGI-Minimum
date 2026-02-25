package CGI::PSGI::Minimum;
use 5.010;
use strict;
use warnings;

our $VERSION = "0.01";

use constant WARN_CGI_GLOBAL_CALLS => $ENV{WARN_CGI_GLOBAL_CALLS};

#========================================

use URI::Escape ();
use URI;
use Plack::Request ();
use Plack::Response ();

use MOP4Import::PSGIEnv qw(
  HTTP_X_FORWARDED_HOST
);

use Tie::IxHash;

our $USE_PARAM_SEMICOLONS = 1;

#========================================

use CGI::PSGI::Minimum::IOHandle -as_base
  , [fields =>
     qw(
       env
       charset
       _request
       _parameters
       _query_parameters

       _status
       _response_headers
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
  Header_Opts => [
    [fields => qw(
      -status
      -type
      -content_type
      -expires
      -cookie
      -charset
    )]
  ],
  ;

#========================================

sub _reset_globals {
  warn "_reset_globals is called!" if WARN_CGI_GLOBAL_CALLS;
}

sub new {
  my ($class, $env) = @_;
  $class->from(env => $env);
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

#========================================

sub parameters {
  my MY $prop = (my $glob = shift)->prop;

  $prop->{_parameters} //= do {
    my Env $env = $prop->{env};
    if (not defined $env->{CONTENT_TYPE}
        and $env->{REQUEST_METHOD} eq 'POST') {
      $env->{CONTENT_TYPE} = 'application/x-www-form-urlencoded';
    }

    tie my %params, 'Tie::IxHash', %{$glob->query_parameters};

    my $request = $glob->request;
    my @kvlist = (
      @{$request->_body_parameters}
    );
    while (my ($k, $v) = splice @kvlist, 0, 2) {
      push @{$params{$k}}, $v;
    }
    \%params;
  }
}

sub query_parameters {
  my MY $prop = (my $glob = shift)->prop;

  $prop->{_query_parameters} //= do {
    tie my %params, 'Tie::IxHash';

    my Env $env = $prop->{env};

    if ($env->{QUERY_STRING} =~ /[&=;]/) {
      my $request = $glob->request;
      my @kvlist = (
        @{$request->_query_parameters},
      );
      while (my ($k, $v) = splice @kvlist, 0, 2) {
        push @{$params{$k}}, $v;
      }
    }
    elsif ($env->{QUERY_STRING} ne '') {
      my $tosplit = URI::Escape::uri_unescape($env->{QUERY_STRING});
      $tosplit =~ tr/+/ /;
      my @keywords = split /\s+/, $tosplit;
      $params{keywords} = \@keywords;
    }

    \%params;
  }
}

#========================================

sub query_string {
  my MY $prop = (my $glob = shift)->prop;

  my $parameters = $glob->parameters;

  my $sep = $USE_PARAM_SEMICOLONS ? ";" : "&";

  join $sep, map {
    my $key = $_;
    my $ekey = URI::Escape::uri_escape($key);
    map {
      join "=", $ekey, URI::Escape::uri_escape($_);
    } @{$parameters->{$key}}
  } keys %$parameters
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
    my $vals = $parameters->{$_[0]};
    if (wantarray) {
      $vals ? @$vals : ();
    } else {
      $vals->[0];
    }
  }
  else {
    # set
    $parameters->{$_[0]} = [@_[1..$#_]];
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

sub http {
  my MY $prop = (my $glob = shift)->prop;
  if (defined $_[0]) {
    my $key = "HTTP_".uc($_[0]);
    $prop->{env}{$key};
  } else {
    grep { /^HTTP (?:_ | $ )/x } keys %{$prop->{env}}
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

sub header {
  my MY $prop = (my $glob = shift)->prop;

  ($prop->{_status}, $prop->{_response_headers}) = $glob->psgi_header(@_);

  "";
}

sub psgi_header {
  my MY $prop = (my $glob = shift)->prop;

  my Header_Opts $opts = $glob->lock_keys_as(Header_Opts, +{@_});

  my $type = ($opts->{-type} // $opts->{-content_type}) || 'text/html';

  my $charset = do {
    if (defined $opts->{-charset}) {
      $glob->charset($opts->{-charset})
    }
    elsif ($type =~ m{^text/}) {
      $glob->charset
    }
    else {
      ''
    }
  };

  if ($type ne '' and $type !~ /\bcharset\b/ and $charset ne '') {
    $type .= "; charset=$charset";
  }

  my @header;

  push @header, "Content-Type", $type if $type ne '';

  $opts->{-status} ||= "200";
  $opts->{-status} =~ s/\D*$//;

  return $opts->{-status}, \@header;
}

#========================================
{
  for my $method (qw(
    request_method
    script_name
    path_info
    request_uri
    server_name
    server_port
    server_protocol
    content_type
  )) {
    my $key = uc($method);
    my $sym = MOP4Import::Util::globref(MY, $method);
    *$sym = sub {
      shift->prop->{env}->{$key}
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

CGI::PSGI::Minimum - It's new $module

=head1 SYNOPSIS

    use CGI::PSGI::Minimum;

=head1 DESCRIPTION

CGI::PSGI::Minimum is ...

=head1 LICENSE

Copyright (C) Kobayasi, Hiroaki.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Kobayasi, Hiroaki E<lt>buribullet@gmail.comE<gt>

=cut

