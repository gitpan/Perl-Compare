use inc::Module::Install;

name          ( 'Perl-Compare'                );
abstract      ( 'Normalized comparison for Perl document trees' );
author        ( 'Adam Kennedy<cpan@ali.as>'   );
version_from  ( 'lib/Perl/Compare.pm'         );
license       ( 'perl'                        );

requires      ( 'perl'             => '5.005' );
requires      ( 'File::chdir'      => '0.06'  );
requires      ( 'List::MoreUtils'  => '0.08'  );
requires      ( 'File::Find::Rule' => '0.20'  );
requires      ( 'Perl::Signature'  => '0.04'  );

build_requires( 'Test::More'       => '0.47'  );
build_requires( 'File::Spec'       => '0.82'  );

# Our test data might contain valid-looking modules.
# Don't index anything in the test data directory.
no_index      ( directory         => 't.data' );

auto_install();

&WriteAll;
