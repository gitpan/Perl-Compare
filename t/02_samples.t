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



# Define the list of samples to test
use vars qw{@SAMPLES};
BEGIN {
	@SAMPLES = qw{
		simple
		};
}

# Does everything load?
use Test::More 'tests' => (scalar(@SAMPLES) * 3);
use Perl::Compare;

foreach my $sample ( @SAMPLES ) {
	my $left  = File::Spec->catfile( 't.data', $sample . '.left' );
	my $right = File::Spec->catfile( 't.data', $sample . '.right' );
	ok( -f $left,  "Test file $left exists" );
	ok( -f $right, "Test file $right exists" );
	is( Perl::Compare->compare( $left, $right ), 1, "$left is equivalent to $right" );
}

1;
