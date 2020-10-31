#!perl

use Test2::V0;

like($ENV{PERL5LIB}, qr{^/app/lib:},        'proper PERl5LIB for main app');
like($ENV{PERL5LIB}, qr{:/app/elib/x/lib:}, 'proper PERl5LIB for submodules');

done_testing();
