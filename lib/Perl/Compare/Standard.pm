package Perl::Compare::Standard;

# The package provides a standard set of Perl::Compare
# normalization transforms.

use strict;
use UNIVERSAL 'isa';
use Perl::Compare   ();
use Scalar::Util 'refaddr';
use List::MoreUtils ();
use Data::Dumper    ();

use vars qw{$VERSION};
BEGIN {
	$VERSION = '0.07';
}

# Register the transforms.
# Since whitespace is by far the statistically most common thing,
# they go first.
sub import {
	my @transforms = map { __PACKAGE__ . "::$_" } qw{
		remove_whitespace
		remove_end
		remove_data
		remove_pod
		remove_insignificant_tokens
		remove_null_statements
		remove_statement_terminators
		remove_useless_pragma
		remove_empty_method_args
		remove_forward_sub_declarations
		commify_list_digraph
		optimize_literal_quotes
		canonicalize_symbols
		};

	Perl::Compare->register_transforms( @transforms );
}





#####################################################################
# Transforms

sub remove_end {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune( 'PPI::Statement::End' );
}

sub remove_data {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune( 'PPI::Statement::Data' );
}

sub remove_pod {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune( 'PPI::Token::Pod' );
}

sub remove_whitespace {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune('PPI::Token::Whitespace');
}

sub remove_insignificant_tokens {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune( sub { ! $_[1]->significant } );
}

sub remove_null_statements {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune('PPI::Statement::Null');
}

sub remove_statement_terminators {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune( sub {
		my $Element = $_[1];
		return '' unless $Element->isa('PPI::Token::Structure');
		return '' unless $Element->content eq ';';
		return '' unless $Element->parent;
		my $last_child = $Element->parent->schild(-1);
		refaddr($Element) == refaddr($last_child);
		} );
}

sub remove_useless_pragma {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune( sub {
		return '' unless $_[1]->isa('PPI::Statement::Include');

		# Remove version dependencies
		my $include = $_[1];
		$DB::single = 1;
		return 1 if $include->version;

		# Remove a limited, specific, set of pragmas
		my $pragma = $include->pragma or return '';
		$pragma =~ /^(?:strict|warnings|diagnostics)$/ ? 1 : '';
		} );
}

# Change ->method() to ->method
sub remove_empty_method_args {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune( sub {
		my $List = $_[1];
		return '' unless isa($List, 'PPI::Structure::List');

		# It should be empty
		return '' if List::MoreUtils::any { $_->significant } $List->children;

		# It must have a -> operator and either a word or $symbol before it
		my $first = $List->sprevious_sibling or return '';
		my $second = $first->sprevious_sibling or return '';
		return '' unless isa($second, 'PPI::Token::Operator');
		return '' unless $second->content eq '=>';
		return 1      if isa($first, 'PPI::Token::Word');
		return '' unless isa($first, 'PPI::Token::Symbol');
		$first->raw_type eq '$' ? 1 : '';
		} );
}

sub remove_forward_sub_declarations {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;
	$Document->prune( sub {
		return '' unless isa($_[1], 'PPI::Statement::Sub');
		$_[1]->forward;
		} );
}

sub commify_list_digraph {
	my $Document = isa(ref $_[0], 'PPI::Document') ? shift : return undef;

	# Find all "=>" digraph list operators
	my $commas = $Document->find( 
		sub {
			UNIVERSAL::isa($_[1], 'PPI::Token::Operator')
			and $_[1]->content eq '=>'
		} );
	return undef unless defined $commas; # Error
	return 0 unless $commas; # None

	# Convert them to commas
	foreach ( @$commas ) {
		$_->{content} = ',';
	}

	scalar @$commas;
}

sub optimize_literal_quotes {
	my $Document = shift;

	# Lets start with the '' literal quotes
	my $single = $Document->find( 'PPI::Token::Quote::Single' );
	return undef unless defined $single;
	return 0 unless $single;

	# Convert them to doubles
	foreach my $Token ( @$single ) {
		# Get the actual value
		my $value;
		eval "\$value = $Token->{content};";
		return undef if $@;

		# Pass it through Data::Dumper::qquote
		$Token->{content} = Data::Dumper::qquote( $value );
		$Token->{seperator} = '"';
		bless $Token, 'PPI::Token::Quote::Double';
	}

	scalar(@$single);
}

sub canonicalize_symbols {
	my $Document = shift;

	# Find all the PPI::Token::Symbol objects
	my $symbols = $Document->find('PPI::Token::Symbol');
	return undef unless defined $symbols;
	return 0 unless $symbols;

	foreach my $Symbol ( @$symbols ) {
		# Set the content to the canonical value if they differ
		my $canon = $Symbol->canonical or return undef;
		$Symbol->{content} = $canon if $Symbol->content ne $canon;
	}

	scalar(@$symbols);
}

1;
