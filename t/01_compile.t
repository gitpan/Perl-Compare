#!/usr/bin/perl -w

# Load test the Perl::Compare module and do some super-basic tests

use strict;
use lib ();
use UNIVERSAL 'isa';
use File::Spec::Functions ':ALL';
BEGIN {
	$| = 1;
	unless ( $ENV{HARNESS_ACTIVE} ) {
		require FindBin;
		chdir ($FindBin::Bin = $FindBin::Bin); # Avoid a warning
		lib->import( catdir( updir(), updir(), 'modules') );
	}
}





# Does everything load?
use Test::More 'tests' => 4;
BEGIN {
	ok( $] >= 5.005, 'Your perl is new enough' );
}

use_ok( 'Perl::Compare' );





# Basic API testing
use constant PC => 'Perl::Compare';
ok( PC->can('compare'),   "compare method exists" );
ok( PC->can('normalize'), "normalize method exists" );

1;
