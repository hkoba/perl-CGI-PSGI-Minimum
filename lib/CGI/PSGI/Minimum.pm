package CGI::PSGI::Minimum;
use 5.010;
use strict;
use warnings;

our $VERSION = "0.01";

use constant WARN_CGI_GLOBAL_CALLS => $ENV{WARN_CGI_GLOBAL_CALLS};

use Plack::Request ();
use Plack::Response ();

use CGI::PSGI::Minimum::IOHandle -as_base
  , [fields =>
     qw(
       env
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

#========================================
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

