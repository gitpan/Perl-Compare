package Perl::Compare;

# This package takes two "documents" of perl source code, in either filename,
# raw source or PPI::Document form. It uses a number or methods to try to
# determine if the two documents are functionally equivalent.

# In general, the way it does this is by applying a number of transformations
# to the perl documents. Initially, this simply consists of removing all
# "non-signficant" tokens and comparing what is left.

# Thus, changes in whitespace, newlines, comments, pod and __END__ material
# are all ignored.

use strict;
use UNIVERSAL 'isa';
use List::Util   ();
use Scalar::Util ();
use PPI          ();

# Load the standard normalization transforms
use Perl::Compare::Standard ();

use vars qw{$VERSION @TRANSFORMS};
BEGIN {
	$VERSION = '0.07';

	# A normalisation transform is a function that takes a PPI::Document
	# and transforms it in a way that will leave two document objects
	# with different content but the same meaning in the same state.
	@TRANSFORMS = ();
}

# Register transforms
sub register_transforms {
	my $class = shift;
	foreach my $transform ( @_ ) {
		# Is it registered already
		next if List::Util::first { $transform eq $_ } @TRANSFORMS;

		# Does it exist?
		unless ( defined \&{"$transform"} ) {
			die "Tried to register non-existant function $transform as a Perl::Compare transform";
		}

		push @TRANSFORMS, $transform;
	}

	1;
}

# Call the import method for Perl::Compare::Standard to register
# the standard transforms.
Perl::Compare::Standard->import;





#####################################################################
# Constructor

sub compare {
	my $class = ref $_[0] ? ref shift : shift;
	my ($left, $right) = (shift, shift);
	my $options = $class->_options_param(@_) or return undef;
	$left  = $class->_document_param($left,  $options) or return undef;
	$right = $class->_document_param($right, $options) or return undef;

	# Process both sides
	$class->normalize($left,  $options) or return undef;
	$class->normalize($right, $options) or return undef;

	# Create a new comparitor
	my $Comparitor = Perl::Compare::_Compare->new($left, $right) or return undef;
	$Comparitor->compare;
}

sub normalize {
	my $class = shift;
	my $Document = isa($_[0], 'PPI::Document') ? shift : return undef;
	my $options  = $class->_options_param(@_) or return undef;

	# Strip out the token positions, if there are any
	$Document->flush_locations;

	# Call each of the transforms in turn
	my $changes = 0;
	no strict 'refs';
	foreach my $function ( @TRANSFORMS ) {
		my $rv = &{"$function"}( $Document );
		unless ( defined $rv ) {
			warn("Normalization Transform $function errored");
			return undef;
		}
		$changes += $rv;
	}

	# Now convert to a ::_NormalizedDocument object
	Perl::Compare::_NormalizedDocument->new( $Document ) or return undef;

	$changes;
}





#####################################################################
# Support Methods

# Clean up the options
sub _options_param {
	my $class = shift;
	return shift if ref $_[0] eq 'HASH';
	my %options = @_;

	# Apply defaults
	$options{destructive} = 1 unless defined $options{destructive};
	$options{data}        = 0 unless defined $options{data};

	# Clean up values
	foreach ( keys %options ) {
		$options{$_} = !! $options{$_};
	}

	\%options;
}

# We work with PPI::Document object, but are able to take arguments in a
# variety of different forms.
sub _document_param {
	my $class   = shift;
	my $it      = defined $_[0] ? shift : return undef;
	my $options = shift || {};

	# Ideally, we have just been given a PPI object we can work with easily.
	return $it if isa(ref $it, 'Perl::Compare::_NormalizedDocument');

	my $Document = undef;
	if ( isa(ref $it, 'PPI::Document') ) {
		# Because we test destructively, clone the document first
		# if they have set the "nondestructive" option.
		$Document = $options->{destructive} ? $it : $it->clone;

	} elsif ( ! ref $it ) {
		# A simple string is a filename
		return undef unless length $it;
		$Document = PPI::Lexer->lex_file( $it );

	} elsif ( Scalar::Util::reftype $it eq 'SCALAR' ) {
		# If we have been given a reference to a scalar, it is source code.
		$Document = PPI::Lexer->lex_source( $$it );
	}

	# Pass up errors
	return undef unless $Document;

	# Strip out line/col locations
	$Document->flush_locations or return undef;

	$Document;
}





#####################################################################
package Perl::Compare::_NormalizedDocument;

# A normalized document is a PPI document after normalisation. It's
# used as a convenience, to allow a function that plans on repeatedly
# comparing the same document on one side to pre-normalise and cache the
# results, to reduce processing time.

use base 'PPI::Document';

use vars qw{$VERSION};
BEGIN {
	$VERSION = '0.06';
}

# The constructor takes a PPI::Document object, and returns an
# identical ::_NormalizedDocument object.
# This constructor IS destructive. If you don't want this, clone the
# document first.
sub new {
	my $Document = UNIVERSAL::isa(ref $_[1], 'PPI::Document') ? $_[1] : return undef;
	bless $Document, 'Perl::Compare::_NormalizedDocument';
}







package Perl::Compare::_Compare;

# Package to implement the actual comparison algorithm

use UNIVERSAL 'isa';
use Scalar::Util 'refaddr', 'reftype', 'blessed';

sub new {
	my $class = ref $_[0] ? ref shift : shift;
	my $this = isa(ref $_[0], 'Perl::Compare::_NormalizedDocument') ? shift : return undef;
	my $that = isa(ref $_[0], 'Perl::Compare::_NormalizedDocument') ? shift : return undef;

	# Create the comparison object
	my $self = bless {
		seen => {},
		this => $this,
		that => $that,
		}, $class;

	$self;
}

# Execute the comparison
sub compare {
	my $self = shift;
	$self->_compare_blessed( $self->{this}, $self->{that} );
}

# Check that two objects are matched
sub _compare_blessed {
	my ($self, $this, $that) = @_;
	my ($bthis, $bthat) = (blessed $this, blessed $that);
	$bthis and $bthat and $bthis eq $bthat or return '';

	# Check the object as a reference
	$self->_compare_ref( $this, $that );
}

# Check that two references match their types
sub _compare_ref {
	my ($self, $this, $that) = @_;
	my ($rthis, $rthat) = (refaddr $this, refaddr $that);
	$rthis and $rthat or return undef;

	# If we have seen this before, are the pointing
	# is it the same one we saw in both sides
	my $seen = $self->{seen}->{$rthis};
	if ( $seen and $seen ne $rthat ) {
		return '';
	}

	# Check the reference types
	my ($tthis, $tthat) = (reftype $this, reftype $that);
	$tthis and $tthat and $tthis eq $tthat or return undef;

	# Check the children of the reference type
	$self->{seen}->{$rthis} = $rthat;
	my $method = "_compare_$tthat";
	my $rv = $self->$method( $this, $that );
	delete $self->{seen}->{$rthis};
	$rv;
}

# Compare the children of two SCALAR references
sub _compare_SCALAR {
	my ($self, $this, $that) = @_;
	my ($cthis, $cthat) = ($$this, $$that);
	return $self->_compare_blessed( $cthis, $cthat ) if blessed $cthis;
	return $self->_compare_ref( $cthis, $cthat )     if ref $cthis;
	return (defined $cthat and $cthis eq $cthat)     if defined $cthis;
	! defined $cthat;
}

# For completeness sake, lets just treat REF as a specialist SCALAR case
BEGIN {
	*_compare_REF = *_compare_SCALAR;
}

# Compare the children of two ARRAY references
sub _compare_ARRAY {
	my ($self, $this, $that) = @_;

	# Compare the number of elements
	scalar(@$this) == scalar(@$that) or return '';

	# Check each element in the array.
	# Descend depth-first.
	foreach my $i ( 0 .. scalar(@$this) ) {
		my ($cthis, $cthat) = ($this->[$i], $that->[$i]);
		if ( blessed $cthis ) {
			return '' unless $self->_compare_blessed( $cthis, $cthat );
		} elsif ( ref $cthis ) {
			return '' unless $self->_compare_ref( $cthis, $cthat );
		} elsif ( defined $cthis ) {
			return '' unless (defined $cthat and $cthis eq $cthat);
		} else {
			return '' if defined $cthat;
		}
	}

	1;
}

# Compare the children of a HASH reference
sub _compare_HASH {
	my ($self, $this, $that) = @_;

	# Compare the number of keys
	return '' unless scalar(keys %$this) == scalar(keys %$that);

	# Compare each key, descending depth-first.
	foreach my $k ( keys %$this ) {
		return '' unless exists $that->{$k};
		my ($cthis, $cthat) = ($this->{$k}, $that->{$k});
		if ( blessed $cthis ) {
			return '' unless $self->_compare_blessed( $cthis, $cthat );
		} elsif ( ref $cthis ) {
			return '' unless $self->_compare_ref( $cthis, $cthat );
		} elsif ( defined $cthis ) {
			return '' unless (defined $cthat and $cthis eq $cthat);
		} else {
			return '' if defined $cthat;
		}
	}

	1;
}		

# We do not support GLOB comparisons
sub _compare_GLOB {
	my ($self, $this, $that) = @_;
	warn("GLOB comparisons are not supported");
	'';
}

# We do not support CODE comparisons
sub _compare_CODE {
	my ($self, $this, $that) = @_;
	refaddr $this == refaddr $that;
}

# We don't support IO comparisons
sub _compare_IO {
	my ($self, $this, $that) = @_;
	warn("CODE comparisons are not supported");
	'';
}

1;

=pod

=head1 NAME

Perl::Compare - Compare two perl documents for equivalence

=head1 SYNOPSIS

  use Perl::Compare;
  
  # Compare my file to yours, to see if they are functionally equivalent
  Perl::Compare->compare( 'my/file.pl', 'your/file.pl' );

=head1 DESCRIPTION

Perl::Compare module takes  perl documents, as a file name, raw source or
an existing L<PPI::Document|PPI::Document> object, and compares the two to
see if they are functionally identical.

The two documents (however they are provided) are loaded into fully lexed
PPI::Document structures. These are then destructively modified to factor
out anything that may have different content but be functionally equivalent.

At the most basic level, the non-significant Elements are stripped out,
and some others converted into  some lowest common form. Beyond that, a
number of additional transforms are done, using a pseudo-plugin system.

At the end of the normalization process, the two normalised documents are
compared with a normal deep structu comparison.

=head1 METHODS

=head2 compare $left, $right, option => value, ...

The C<compare> method is the primary method for doing a comparison between
two Perl documents. It's provided with two arguments, and an optional
set of options.

Each comparitor can be either a L<PPI::Document|PPI::Document> object,
a C<Perl::Compare::_NormalizedDocument> object, a file name, or a
reference to a scalar containing raw perl source code. Each comparitor
will be loaded, parsed and normalized as needed to get two
Perl::Compare::_NormalizedDocument objects, which are then compared
using Data::Compare.

The list of options will be documented once this module is actually useful.

Returns true is the two perl items are equivalent, false if not, or C<undef>
on error.

=head2 normalize $PPI::Document, option => value, ...

The C<normalize> method does the actual normalization of a single
L<PPI::Document|PPI::Document> object. The method takes as argument
a single PPI::Document object, and a set of options compatible with the
C<compare> method above, and returns a Perl::Compare::_NormalizeDocument
object, which is the munged and destroyed result of the normalization
process.

Although primarily used internally, its main public use it to pre-normalize
a Document object, when it will be compared a large number of times.

=head1 Perl::Compare::_NormalizedDocument

Perl::Compare::_NormalizedDocument is the internal class used to flag a
L<PPI::Document|PPI::Document> object as being fully normalized.

It has no special properties, or methods (But its completely destroyed in
the normalization process of course, so don't try to do anything with it).

=head1 TO DO

Create a proper extention mechanism, document it, maybe autodetect plugins,
and possibly break it up into multiple phases, so that the simple transforms
can be isolated from the more complex ones.

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Perl%3A%3ACompare>

For other issues, contact the author.

=head1 AUTHOR

Adam Kennedy (Maintainer), L<http://ali.as/>, cpan@ali.as

=head1 COPYRIGHT

Thank you to Phase N (L<http://phase-n.com/>) for permitting
the Open Sourcing and release of this distribution.

Copyright (c) 2004 Adam Kennedy. All rights reserved.
This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
