# -*- mode: perl -*-

requires 'perl', '5.008001';

requires 'Plack::Request';
requires 'Plack::Response';
requires 'Tie::IxHash';
requires 'URI::Escape';

requires 'MOP4Import::Declare'; # For MOP4Import::Base::IOHandle

on 'test' => sub {
    requires 'Test::More', '0.98';
};

