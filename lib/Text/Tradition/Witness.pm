package Text::Tradition::Witness;
use Moose;
use Moose::Util::TypeConstraints;

=head1 NAME

Text::Tradition::Witness - a manuscript witness to a text tradition

=head1 SYNOPSIS

  use Text::Tradition::Witness;
  my $w = Text::Tradition::Witness->new( 
    'sigil' => 'A',
    'identifier' => 'Oxford MS Ex.1932',
    );  
    
=head1 DESCRIPTION

Text::Tradition::Witness is an object representation of a manuscript
witness to a text tradition.  A manuscript has a sigil (a short code that
represents it in the wider tradition), an identifier (e.g. the library ID),
and probably a text.

=head1 METHODS

=head2 new

Create a new witness.  Options include:

=over

=item * sigil - A short code to represent the manuscript.  Required.

=item * text - An array of strings (words) that contains the text of the
manuscript.  This should not change after the witness has been instantiated,
and the path through the collation should always match it.

=item * layertext - An array of strings (words) that contains the layered text,
if any, of the manuscript.  This should not change after the witness has been 
instantiated, and the path through the collation should always match it.

=item * source - A reference to the text, such as a filename, if it is not
given in the 'text' option.

=item * identifier - The recognized name of the manuscript, e.g. a library
identifier.

=item * other_info - A freeform string for any other description of the
manuscript.

=back

=head2 sigil

Accessor method for the witness sigil.

=head2 text

Accessor method to get and set the text array.

=head2 source

Accessor method to get and set the text source.

=head2 identifier

Accessor method for the witness identifier.

=head2 other_info

Accessor method for the general witness description.

=head2 is_layered

Boolean method to note whether the witness has layers (e.g. pre-correction 
readings) in the collation.

=begin testing

use_ok( 'Text::Tradition::Witness', "can use module" );

my @text = qw( This is a line of text );
my $wit = Text::Tradition::Witness->new( 
    'sigil' => 'A',
    'text' => \@text,
     );
is( ref( $wit ), 'Text::Tradition::Witness', 'Created a witness' );
if( $wit ) {
    is( $wit->sigil, 'A', "Witness has correct sigil" );
    is( join( ' ', @{$wit->text} ), join( ' ', @text ), "Witness has correct text" );
}

=end testing 

=cut

# Sigil. Required identifier for a witness.
has 'sigil' => (
	is => 'ro',
	isa => 'Str',
	required => 1,
	);

# Text.	 This is an array of strings (i.e. word tokens).
# TODO Think about how to handle this for the case of pre-prepared
# collations, where the tokens are in the graph already.
has 'text' => (
	is => 'rw',
	isa => 'ArrayRef[Str]',
	predicate => 'has_text',
	);
	
has 'layertext' => (
	is => 'rw',
	isa => 'ArrayRef[Str]',
	predicate => 'has_layertext',
	);

# Source.  This is where we read in the witness, if not from a
# pre-prepared collation.  It is probably a filename.
has 'source' => (
	is => 'ro',
	isa => 'Str',
	predicate => 'has_source',
	);

# Path.	 This is an array of Reading nodes that can be saved during
# initialization, but should be cleared before saving in a DB.
has 'path' => (
	is => 'rw',
	isa => 'ArrayRef[Text::Tradition::Collation::Reading]',
	predicate => 'has_path',
	clearer => 'clear_path',
	);		   

has 'uncorrected_path' => (
	is => 'rw',
	isa => 'ArrayRef[Text::Tradition::Collation::Reading]',
	clearer => 'clear_uncorrected_path',
	);
	
has 'is_layered' => (
	is => 'rw',
	isa => 'Bool',
	);

# Manuscript name or similar
has 'identifier' => (
	is => 'ro',
	isa => 'Str',
	);

# Any other info we have
has 'other_info' => (
	is => 'ro',
	isa => 'Str',
	);
	
# If we set an uncorrected path, ever, remember that we did so.
around 'uncorrected_path' => sub {
	my $orig = shift;
	my $self = shift;
	
	$self->is_layered( 1 );
	$self->$orig( @_ );
};

sub BUILD {
	my $self = shift;
	if( $self->has_source ) {
		# Read the file and initialize the text.
		my $rc;
		eval { no warnings; $rc = open( WITNESS, $self->source ); };
		# If we didn't open a file, assume it is a string.
		if( $rc ) {
			my @words;
			while(<WITNESS>) {
				chomp;
				push( @words, split( /\s+/, $_ ) );
			}
			close WITNESS;
			$self->text( \@words );
		} # else the text is in the source string, probably
		  # XML, and we are doing nothing with it.
	}
}

no Moose;
__PACKAGE__->meta->make_immutable;

=head1 BUGS / TODO

=over

=item * Get rid of either text or path, as they are redundant.

=item * Re-think the mechanism for pre-correction readings etc.

=back

=head1 LICENSE

This package is free software and is provided "as is" without express
or implied warranty.  You can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 AUTHOR

Tara L Andrews E<lt>aurum@cpan.orgE<gt>
