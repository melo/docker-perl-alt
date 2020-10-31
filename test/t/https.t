#!perl

use Test2::V0;
use HTTP::Tiny;

my $ua = HTTP::Tiny->new(timeout => 5);

my $res = $ua->get('https://www.simplicidade.org/');
ok($res->{success}, 'HTTPS support ok');

done_testing();
