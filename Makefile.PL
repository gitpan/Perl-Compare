require 5.000;
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME'         => 'Perl::Compare',
	'VERSION_FROM' => 'lib/Perl/Compare.pm',
	'PREREQ_PM'    => {
		# Needed for Perl::Compare
		'File::Spec'      => '0.82',
		'PPI'             => '0.829',
		'Data::Dumper'    => 0,       # Whatever comes with Perl
		'Scalar::Util'    => '1.11',
		'List::Util'      => '1.11',
		'List::MoreUtils' => 0,       # Anything we can get

		# Needed for tests
		'Test::More'      => 0,
	},
	($] >= 5.005) ? (
		'AUTHOR'   => 'Adam Kennedy (cpan@ali.as)',
		'ABSTRACT' => 'Compare two perl documents for equivalence (experimental)',
	) : (),
);
