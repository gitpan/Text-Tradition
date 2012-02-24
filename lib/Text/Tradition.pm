package Text::Tradition;

use Module::Load;
use Moose;
use Text::Tradition::Collation;
use Text::Tradition::Stemma;
use Text::Tradition::Witness;

use vars qw( $VERSION );
$VERSION = "0.2";

has 'collation' => (
    is => 'ro',
    isa => 'Text::Tradition::Collation',
    writer => '_save_collation',
    );

has 'witness_hash' => (
    traits => ['Hash'],
    isa => 'HashRef[Text::Tradition::Witness]',
    handles => {
        witness     => 'get',
        add_witness => 'set',
        del_witness => 'delete',
        has_witness => 'exists',
        witnesses   => 'values',
    },
    default => sub { {} },
    );

has 'name' => (
    is => 'rw',
    isa => 'Str',
    default => 'Tradition',
    );
    
has 'language' => (
	is => 'ro',
	isa => 'Str',
	);
    
has 'stemmata' => (
	traits => ['Array'],
	isa => 'ArrayRef[Text::Tradition::Stemma]',
	handles => {
		stemmata => 'elements',
		_add_stemma => 'push',
		stemma => 'get',
		stemma_count => 'count',
		clear_stemmata => 'clear',
	},
	default => sub { [] },
	);
  
# Create the witness before trying to add it
around 'add_witness' => sub {
    my $orig = shift;
    my $self = shift;
    # TODO allow add of a Witness object?
    my $new_wit = Text::Tradition::Witness->new( @_ );
    $self->$orig( $new_wit->sigil => $new_wit );
    return $new_wit;
};

# Allow deletion of witness by object as well as by sigil
around 'del_witness' => sub {
    my $orig = shift;
    my $self = shift;
    my @key_args;
    foreach my $arg ( @_ ) {
        push( @key_args, 
              ref( $arg ) eq 'Text::Tradition::Witness' ? $arg->sigil : $arg );
    }
    return $self->$orig( @key_args );
};

# Don't allow an empty hash value
around 'witness' => sub {
    my( $orig, $self, $arg ) = @_;
    return unless $self->has_witness( $arg );
    return $self->$orig( $arg );
};

=head1 NAME

Text::Tradition - a software model for a set of collated texts

=head1 SYNOPSIS

  use Text::Tradition;
  my $t = Text::Tradition->new( 
    'name' => 'this is a text',
    'input' => 'TEI',
    'file' => '/path/to/tei_parallel_seg_file.xml' );

  my @text_wits = $t->witnesses();
  my $manuscript_a = $t->witness( 'A' );
  my $new_ms = $t->add_witness( 'sigil' => 'B' );
  
  my $text_path_svg = $t->collation->as_svg();
  ## See Text::Tradition::Collation for more on text collation itself
    
=head1 DESCRIPTION

Text::Tradition is a library for representation and analysis of collated
texts, particularly medieval ones.  A 'tradition' refers to the aggregation
of surviving versions of a text, generally preserved in multiple
manuscripts (or 'witnesses').  A Tradition object thus has one more more
Witnesses, as well as a Collation that represents the unity of all versions
of the text.

=head1 METHODS

=head2 new

Creates and returns a new text tradition object.  The following options are
accepted.

General options:

=over 4

=item B<name> - The name of the text.

=back

Initialization based on a collation file:

=over 4

=item B<input> - The input format of the collation file.  Can be one of the
following:

=over 4

=item * Self - a GraphML format produced by this module

=item * CollateX - a GraphML format produced by CollateX

=item * CTE - a TEI XML format produced by Classical Text Editor

=item * JSON - an alignment table in JSON format, as produced by CollateX and other tools

=item * KUL - a specific CSV format for variants, not documented here

=item * TEI - a TEI parallel segmentation format file

=item * Tabular - a comma- or tab-separated collation.  Takes an additional
option, 'sep_char', which defaults to the tab character.

=back

=item B<file> - The name of the file that contains the data.  One of 'file'
or 'string' should be specified.

=item B<string> - A text string that contains the data.  One of 'file' or
'string' should be specified.

=item B<base> - The name of a text file that contains the base text, to be
used with input formats that require it (currently only KUL).

=back

Initialization based on a list of witnesses [NOT YET IMPLEMENTED]:

=over 4

=item B<witnesses> - A reference to an array of Text::Tradition::Witness
objects that carry the text to be collated.

=item B<collator> - A reference to a collation program that will accept
Witness objects.

=back

=head2 B<witnesses>

Return the Text::Tradition::Witness objects associated with this tradition,
as an array.

=head2 B<witness>( $sigil )

Returns the Text::Tradition::Witness object whose sigil is $sigil, or undef
if there is no such object within the tradition.

=head2 B<add_witness>( %opts )

Instantiate a new witness with the given options (see documentation for
Text::Tradition::Witness) and add it to the tradition.

=head2 B<del_witness>( $sigil )

Delete the witness with the given sigil from the tradition.  Returns the
witness object for the deleted witness.

=begin testing

use_ok( 'Text::Tradition', "can use module" );

my $t = Text::Tradition->new( 'name' => 'empty' );
is( ref( $t ), 'Text::Tradition', "initialized an empty Tradition object" );
is( $t->name, 'empty', "object has the right name" );
is( scalar $t->witnesses, 0, "object has no witnesses" );

my $simple = 't/data/simple.txt';
my $s = Text::Tradition->new( 
    'name'  => 'inline', 
    'input' => 'Tabular',
    'file'  => $simple,
    );
is( ref( $s ), 'Text::Tradition', "initialized a Tradition object" );
is( $s->name, 'inline', "object has the right name" );
is( scalar $s->witnesses, 3, "object has three witnesses" );

my $wit_a = $s->witness('A');
is( ref( $wit_a ), 'Text::Tradition::Witness', "Found a witness A" );
if( $wit_a ) {
    is( $wit_a->sigil, 'A', "Witness A has the right sigil" );
}
is( $s->witness('X'), undef, "There is no witness X" );
ok( !exists $s->{'witnesses'}->{'X'}, "Witness key X not created" );

my $wit_d = $s->add_witness( 'sigil' => 'D' );
is( ref( $wit_d ), 'Text::Tradition::Witness', "new witness created" );
is( $wit_d->sigil, 'D', "witness has correct sigil" );
is( scalar $s->witnesses, 4, "object now has four witnesses" );

my $del = $s->del_witness( 'D' );
is( $del, $wit_d, "Deleted correct witness" );
is( scalar $s->witnesses, 3, "object has three witnesses again" );

# TODO test initialization by witness list when we have it

=end testing

=cut
    

sub BUILD {
    my( $self, $init_args ) = @_;

    if( exists $init_args->{'witnesses'} ) {
        # We got passed an uncollated list of witnesses.  Make a
        # witness object for each witness, and then send them to the
        # collator.
        my $autosigil = 0;
        foreach my $wit ( %{$init_args->{'witnesses'}} ) {
            # Each item in the list is either a string or an arrayref.
            # If it's a string, it is a filename; if it's an arrayref,
            # it is a tuple of 'sigil, file'.  Handle either case.
            my $args;
            if( ref( $wit ) eq 'ARRAY' ) {
                $args = { 'sigil' => $wit->[0],
                          'file' => $wit->[1] };
            } else {
                $args = { 'sigil' => chr( $autosigil+65 ),
                          'file' => $wit };
                $autosigil++;
            }
            $self->witnesses->add_witness( $args );
            # TODO Now how to collate these?
        }
    } else {
        # Else we need to parse some collation data.  Make a Collation object
        my $collation = Text::Tradition::Collation->new( %$init_args,
                                                        'tradition' => $self );
        $self->_save_collation( $collation );

        # Call the appropriate parser on the given data
        my @format_standalone = qw/ Self CollateText CollateX CTE JSON TEI Tabular /;
        my @format_basetext = qw/ KUL /;
        my $use_base;
        my $format = $init_args->{'input'};
        if( $format && !( grep { $_ eq $format } @format_standalone )
            && !( grep { $_ eq $format } @format_basetext ) ) {
            warn "Unrecognized input format $format; not parsing";
            return;
        }
        if( $format && grep { $_ eq $format } @format_basetext ) {
            $use_base = 1;
            if( !exists $init_args->{'base'} ) {
                warn "Cannot make a collation from $format without a base text";
                return;
            }
        }

        # Now do the parsing. 
        if( $format ) {
            if( $use_base ) { 
                $format = 'BaseText';   # Use the BaseText module for parsing,
                                        # but retain the original input arg.
            }
            my $mod = "Text::Tradition::Parser::$format";
            load( $mod );
            $mod->can('parse')->( $self, $init_args );
        }
    }
}

=head2 add_stemma( $dotfile )

Initializes a Text::Tradition::Stemma object from the given dotfile,
and associates it with the tradition.

=begin testing

use Text::Tradition;

my $t = Text::Tradition->new( 
    'name'  => 'simple test', 
    'input' => 'Tabular',
    'file'  => 't/data/simple.txt',
    );

is( $t->stemma_count, 0, "No stemmas added yet" );
my $s;
ok( $s = $t->add_stemma( dotfile => 't/data/simple.dot' ), "Added a simple stemma" );
is( ref( $s ), 'Text::Tradition::Stemma', "Got a stemma object returned" );
is( $t->stemma_count, 1, "Tradition claims to have a stemma" );
is( $t->stemma(0), $s, "Tradition hands back the right stemma" );

=end testing

=cut

sub add_stemma {
	my $self = shift;
	my %opts = @_;
	my $stemma_fh;
	if( $opts{'dotfile'} ) {
		open $stemma_fh, '<', $opts{'dotfile'}
			or warn "Could not open file " . $opts{'dotfile'};
	} elsif( $opts{'dot'} ) {
		my $str = $opts{'dot'};
		open $stemma_fh, '<', \$str;
	}
	# Assume utf-8
	binmode $stemma_fh, ':utf8';
	my $stemma = Text::Tradition::Stemma->new( 
		'collation' => $self->collation,
		'dot' => $stemma_fh );
	$self->_add_stemma( $stemma ) if $stemma;
	return $stemma;
}

no Moose;
__PACKAGE__->meta->make_immutable;


=head1 BUGS / TODO

=over

=item * Allow tradition to be initialized via passing to a collator.

=back

=head1 LICENSE

This package is free software and is provided "as is" without express
or implied warranty.  You can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 AUTHOR

Tara L Andrews E<lt>aurum@cpan.orgE<gt>