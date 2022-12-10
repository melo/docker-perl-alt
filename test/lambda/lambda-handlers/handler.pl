#!perl

use strict;
use warnings;
use JSON::MaybeXS;

sub echo {
  my ($payload, $context) = @_;

  return encode_json({ payload => $payload, context => { %$context } });
}

1;
