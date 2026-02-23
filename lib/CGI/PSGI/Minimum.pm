package CGI::PSGI::Minimum;
use 5.010;
use strict;
use warnings;

our $VERSION = "0.01";

use constant WARN_CGI_GLOBAL_CALLS => $ENV{WARN_CGI_GLOBAL_CALLS};

use Plack::Request ();
use Plack::Response ();

use MOP4Import::PSGIEnv;

use Tie::IxHash;
use CGI::PSGI::Minimum::IOHandle -as_base
  , [fields =>
     qw(
       env
       _request
       _parameters
       _query_parameters
     )
   ]
  ;

use MOP4Import::Util qw(
);

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
    \%params;
  }
}

#========================================
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

#========================================
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

