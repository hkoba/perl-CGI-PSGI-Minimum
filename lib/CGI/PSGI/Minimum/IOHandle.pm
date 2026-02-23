package CGI::PSGI::Minimum::IOHandle;
use strict;
use warnings;

use IO::Handle ();

use MOP4Import::Declare -as_base
  , [fields =>
     [encoding => no_getter => 1],
     qw(
       _buffer
     )
   ];
use MOP4Import::Util ();
use MOP4Import::Opts;

#========================================

sub declare___field {
  my ($myPack, $opts, $field_class, $name, @rest) = m4i_args(@_);
  $myPack->SUPER::declare___field(
    $opts, $field_class, $name, no_getter => 1, @rest
  );
}

#========================================

sub PROP () {__PACKAGE__}
sub prop { *{shift()}{HASH} }

sub from {
  my ($class, @args) = @_;
  (my PROP $prop, my @task) = $class->build_prop(@args);
  my $self = $class->build_fh_for($prop);
  $self;
}

sub build_prop {
  my ($class, @args) = @_;
  my $fields = MOP4Import::Util::maybe_fields_hash($class)
    or Carp::croak "Class $class does'nt have \%FIELDS";
  my PROP $prop = Hash::Util::lock_keys(my %prop, keys %$fields);
  %$prop = @args;
  $prop;
}

sub build_fh_for {
  (my $class, my PROP $prop) = splice @_, 0, 2;
  my $enc = $prop->{encoding} ? ":encoding($prop->{encoding})" : '';
  if (not defined $_[0]) {
    $prop->{_buffer} //= (\ my $str);
    $ {$prop->{_buffer}} //= "";
    open $_[0], ">$enc", $prop->{_buffer} or Carp::croak $!;
  } elsif ($enc) {
    binmode $_[0], $enc;
  }
  bless $_[0], $class;
  *{$_[0]} = $prop;
  $_[0];
}


1;
