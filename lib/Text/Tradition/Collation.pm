package Text::Tradition::Collation;

use Encode qw( decode_utf8 );
use File::Temp;
use File::Which;
use Graph;
use IPC::Run qw( run binary );
use Text::CSV_XS;
use Text::Tradition::Collation::Reading;
use Text::Tradition::Collation::RelationshipStore;
use Text::Tradition::Error;
use XML::LibXML;
use XML::LibXML::XPathContext;
use Moose;

has 'sequence' => (
    is => 'ro',
    isa => 'Graph',
    default => sub { Graph->new() },
    handles => {
    	paths => 'edges',
    },
    );
    
has 'relations' => (
	is => 'ro',
	isa => 'Text::Tradition::Collation::RelationshipStore',
	handles => {
		relationships => 'relationships',
		related_readings => 'related_readings',
		get_relationship => 'get_relationship',
		del_relationship => 'del_relationship',
	},
	writer => '_set_relations',
	);

has 'tradition' => (
    is => 'ro',
    isa => 'Text::Tradition',
    weak_ref => 1,
    );

has 'readings' => (
	isa => 'HashRef[Text::Tradition::Collation::Reading]',
	traits => ['Hash'],
    handles => {
        reading     => 'get',
        _add_reading => 'set',
        del_reading => 'delete',
        has_reading => 'exists',
        readings   => 'values',
    },
    default => sub { {} },
	);

has 'wit_list_separator' => (
    is => 'rw',
    isa => 'Str',
    default => ', ',
    );

has 'baselabel' => (
    is => 'rw',
    isa => 'Str',
    default => 'base text',
    );

has 'linear' => (
    is => 'rw',
    isa => 'Bool',
    default => 1,
    );
    
has 'ac_label' => (
    is => 'rw',
    isa => 'Str',
    default => ' (a.c.)',
    );
    
has 'wordsep' => (
	is => 'rw',
	isa => 'Str',
	default => ' ',
	);
    
has 'start' => (
	is => 'ro',
	isa => 'Text::Tradition::Collation::Reading',
	writer => '_set_start',
	weak_ref => 1,
	);

has 'end' => (
	is => 'ro',
	isa => 'Text::Tradition::Collation::Reading',
	writer => '_set_end',
	weak_ref => 1,
	);
	
has 'cached_svg' => (
	is => 'rw',
	isa => 'Str',
	predicate => 'has_cached_svg',
	clearer => 'wipe_svg',
	);
	
has 'cached_table' => (
	is => 'rw',
	isa => 'HashRef',
	predicate => 'has_cached_table',
	clearer => 'wipe_table',
	);
	
has '_graphcalc_done' => (
	is => 'rw',
	isa => 'Bool',
	default => undef,
	); 

=head1 NAME

Text::Tradition::Collation - a software model for a text collation

=head1 SYNOPSIS

  use Text::Tradition;
  my $t = Text::Tradition->new( 
    'name' => 'this is a text',
    'input' => 'TEI',
    'file' => '/path/to/tei_parallel_seg_file.xml' );

  my $c = $t->collation;
  my @readings = $c->readings;
  my @paths = $c->paths;
  my @relationships = $c->relationships;
  
  my $svg_variant_graph = $t->collation->as_svg();
    
=head1 DESCRIPTION

Text::Tradition is a library for representation and analysis of collated
texts, particularly medieval ones.  The Collation is the central feature of
a Tradition, where the text, its sequence of readings, and its relationships
between readings are actually kept.

=head1 CONSTRUCTOR

=head2 new

The constructor.  Takes a hash or hashref of the following arguments:

=over

=item * tradition - The Text::Tradition object to which the collation 
belongs. Required.

=item * linear - Whether the collation should be linear; that is, whether 
transposed readings should be treated as two linked readings rather than one, 
and therefore whether the collation graph is acyclic.  Defaults to true.

=item * baselabel - The default label for the path taken by a base text 
(if any). Defaults to 'base text'.

=item * wit_list_separator - The string to join a list of witnesses for 
purposes of making labels in display graphs.  Defaults to ', '.

=item * ac_label - The extra label to tack onto a witness sigil when 
representing another layer of path for the given witness - that is, when
a text has more than one possible reading due to scribal corrections or
the like.  Defaults to ' (a.c.)'.

=item * wordsep - The string used to separate words in the original text.
Defaults to ' '.

=back

=head1 ACCESSORS

=head2 tradition

=head2 linear

=head2 wit_list_separator

=head2 baselabel

=head2 ac_label

=head2 wordsep

Simple accessors for collation attributes.

=head2 start

The meta-reading at the start of every witness path.

=head2 end

The meta-reading at the end of every witness path.

=head2 readings

Returns all Reading objects in the graph.

=head2 reading( $id )

Returns the Reading object corresponding to the given ID.

=head2 add_reading( $reading_args )

Adds a new reading object to the collation. 
See L<Text::Tradition::Collation::Reading> for the available arguments.

=head2 del_reading( $object_or_id )

Removes the given reading from the collation, implicitly removing its
paths and relationships.

=head2 merge_readings( $main, $second, $concatenate, $with_str )

Merges the $second reading into the $main one. If $concatenate is true, then
the merged node will carry the text of both readings, concatenated with either
$with_str (if specified) or a sensible default (the empty string if the
appropriate 'join_*' flag is set on either reading, or else $self->wordsep.)

The first two arguments may be either readings or reading IDs.

=head2 has_reading( $id )

Predicate to see whether a given reading ID is in the graph.

=head2 reading_witnesses( $object_or_id )

Returns a list of sigils whose witnesses contain the reading.

=head2 paths

Returns all reading paths within the document - that is, all edges in the 
collation graph.  Each path is an arrayref of [ $source, $target ] reading IDs.

=head2 add_path( $source, $target, $sigil )

Links the given readings in the collation in sequence, under the given witness
sigil.  The readings may be specified by object or ID.

=head2 del_path( $source, $target, $sigil )

Links the given readings in the collation in sequence, under the given witness
sigil.  The readings may be specified by object or ID.

=head2 has_path( $source, $target );

Returns true if the two readings are linked in sequence in any witness.  
The readings may be specified by object or ID.

=head2 relationships

Returns all Relationship objects in the collation.

=head2 add_relationship( $reading, $other_reading, $options )

Adds a new relationship of the type given in $options between the two readings,
which may be specified by object or ID.  Returns a value of ( $status, @vectors)
where $status is true on success, and @vectors is a list of relationship edges
that were ultimately added.
See L<Text::Tradition::Collation::Relationship> for the available options.

=cut 

sub BUILD {
    my $self = shift;
    $self->_set_relations( Text::Tradition::Collation::RelationshipStore->new( 'collation' => $self ) );
    $self->_set_start( $self->add_reading( { 'collation' => $self, 'is_start' => 1 } ) );
    $self->_set_end( $self->add_reading( { 'collation' => $self, 'is_end' => 1 } ) );
}

### Reading construct/destruct functions

sub add_reading {
	my( $self, $reading ) = @_;
	unless( ref( $reading ) eq 'Text::Tradition::Collation::Reading' ) {
		my %args = %$reading;
		$reading = Text::Tradition::Collation::Reading->new( 
			'collation' => $self,
			%args );
	}
	# First check to see if a reading with this ID exists.
	if( $self->reading( $reading->id ) ) {
		throw( "Collation already has a reading with id " . $reading->id );
	}
	$self->_graphcalc_done(0);
	$self->_add_reading( $reading->id => $reading );
	# Once the reading has been added, put it in both graphs.
	$self->sequence->add_vertex( $reading->id );
	$self->relations->add_reading( $reading->id );
	return $reading;
};

around del_reading => sub {
	my $orig = shift;
	my $self = shift;
	my $arg = shift;
	
	if( ref( $arg ) eq 'Text::Tradition::Collation::Reading' ) {
		$arg = $arg->id;
	}
	# Remove the reading from the graphs.
	$self->_graphcalc_done(0);
	$self->_clear_cache; # Explicitly clear caches to GC the reading
	$self->sequence->delete_vertex( $arg );
	$self->relations->delete_reading( $arg );
	
	# Carry on.
	$self->$orig( $arg );
};

=begin testing

use Text::Tradition;

my $cxfile = 't/data/Collatex-16.xml';
my $t = Text::Tradition->new( 
    'name'  => 'inline', 
    'input' => 'CollateX',
    'file'  => $cxfile,
    );
my $c = $t->collation;

my $rno = scalar $c->readings;
# Split n21 for testing purposes
my $new_r = $c->add_reading( { 'id' => 'n21p0', 'text' => 'un', 'join_next' => 1 } );
my $old_r = $c->reading( 'n21' );
$old_r->alter_text( 'to' );
$c->del_path( 'n20', 'n21', 'A' );
$c->add_path( 'n20', 'n21p0', 'A' );
$c->add_path( 'n21p0', 'n21', 'A' );
$c->flatten_ranks();
ok( $c->reading( 'n21p0' ), "New reading exists" );
is( scalar $c->readings, $rno, "Reading add offset by flatten_ranks" );

# Combine n3 and n4
$c->merge_readings( 'n3', 'n4', 1 );
ok( !$c->reading('n4'), "Reading n4 is gone" );
is( $c->reading('n3')->text, 'with his', "Reading n3 has both words" );

# Collapse n25 and n26
$c->merge_readings( 'n25', 'n26' );
ok( !$c->reading('n26'), "Reading n26 is gone" );
is( $c->reading('n25')->text, 'rood', "Reading n25 has an unchanged word" );

# Combine n21 and n21p0
my $remaining = $c->reading('n21');
$remaining ||= $c->reading('n22');  # one of these should still exist
$c->merge_readings( 'n21p0', $remaining, 1 );
ok( !$c->reading('n21'), "Reading $remaining is gone" );
is( $c->reading('n21p0')->text, 'unto', "Reading n21p0 merged correctly" );

=end testing

=cut

sub merge_readings {
	my $self = shift;

	# We only need the IDs for adding paths to the graph, not the reading
	# objects themselves.
    my( $kept, $deleted, $combine, $combine_char ) = $self->_stringify_args( @_ );
	$self->_graphcalc_done(0);

    # The kept reading should inherit the paths and the relationships
    # of the deleted reading.
	foreach my $path ( $self->sequence->edges_at( $deleted ) ) {
		my @vector = ( $kept );
		push( @vector, $path->[1] ) if $path->[0] eq $deleted;
		unshift( @vector, $path->[0] ) if $path->[1] eq $deleted;
		next if $vector[0] eq $vector[1]; # Don't add a self loop
		my %wits = %{$self->sequence->get_edge_attributes( @$path )};
		$self->sequence->add_edge( @vector );
		my $fwits = $self->sequence->get_edge_attributes( @vector );
		@wits{keys %$fwits} = values %$fwits;
		$self->sequence->set_edge_attributes( @vector, \%wits );
	}
	$self->relations->merge_readings( $kept, $deleted, $combine_char );
	
	# Do the deletion deed.
	if( $combine ) {
		my $kept_obj = $self->reading( $kept );
		my $del_obj = $self->reading( $deleted );
		my $joinstr = $combine_char;
		unless( defined $joinstr ) {
			$joinstr = '' if $kept_obj->join_next || $del_obj->join_prior;
			$joinstr = $self->wordsep unless defined $joinstr;
		}
		$kept_obj->alter_text( join( $joinstr, $kept_obj->text, $del_obj->text ) );
	}
	$self->del_reading( $deleted );
}


# Helper function for manipulating the graph.
sub _stringify_args {
	my( $self, $first, $second, @args ) = @_;
    $first = $first->id
        if ref( $first ) eq 'Text::Tradition::Collation::Reading';
    $second = $second->id
        if ref( $second ) eq 'Text::Tradition::Collation::Reading';        
    return( $first, $second, @args );
}

# Helper function for manipulating the graph.
sub _objectify_args {
	my( $self, $first, $second, $arg ) = @_;
    $first = $self->reading( $first )
        unless ref( $first ) eq 'Text::Tradition::Collation::Reading';
    $second = $self->reading( $second )
        unless ref( $second ) eq 'Text::Tradition::Collation::Reading';        
    return( $first, $second, $arg );
}
### Path logic

sub add_path {
	my $self = shift;

	# We only need the IDs for adding paths to the graph, not the reading
	# objects themselves.
    my( $source, $target, $wit ) = $self->_stringify_args( @_ );

	$self->_graphcalc_done(0);
	# Connect the readings
    $self->sequence->add_edge( $source, $target );
    # Note the witness in question
    $self->sequence->set_edge_attribute( $source, $target, $wit, 1 );
};

sub del_path {
	my $self = shift;
	my @args;
	if( ref( $_[0] ) eq 'ARRAY' ) {
		my $e = shift @_;
		@args = ( @$e, @_ );
	} else {
		@args = @_;
	}

	# We only need the IDs for adding paths to the graph, not the reading
	# objects themselves.
    my( $source, $target, $wit ) = $self->_stringify_args( @args );

	$self->_graphcalc_done(0);
	if( $self->sequence->has_edge_attribute( $source, $target, $wit ) ) {
		$self->sequence->delete_edge_attribute( $source, $target, $wit );
	}
	unless( keys %{$self->sequence->get_edge_attributes( $source, $target )} ) {
		$self->sequence->delete_edge( $source, $target );
	}
}


# Extra graph-alike utility
sub has_path {
	my $self = shift;
    my( $source, $target, $wit ) = $self->_stringify_args( @_ );
	return undef unless $self->sequence->has_edge( $source, $target );
	return $self->sequence->has_edge_attribute( $source, $target, $wit );
}

=head2 clear_witness( @sigil_list )

Clear the given witnesses out of the collation entirely, removing references
to them in paths, and removing readings that belong only to them.  Should only
be called via $tradition->del_witness.

=cut

sub clear_witness {
	my( $self, @sigils ) = @_;

	$self->_graphcalc_done(0);
	# Clear the witness(es) out of the paths
	foreach my $e ( $self->paths ) {
		foreach my $sig ( @sigils ) {
			$self->del_path( $e, $sig );
		}
	}
	
	# Clear out the newly unused readings
	foreach my $r ( $self->readings ) {
		unless( $self->reading_witnesses( $r ) ) {
			$self->del_reading( $r );
		}
	}
}

sub add_relationship {
	my $self = shift;
    my( $source, $target, $opts ) = $self->_stringify_args( @_ );
    my( @vectors ) = $self->relations->add_relationship( $source, 
    	$self->reading( $source ), $target, $self->reading( $target ), $opts );
	$self->_graphcalc_done(0);
    return @vectors;
}

around qw/ get_relationship del_relationship / => sub {
	my $orig = shift;
	my $self = shift;
	my @args = @_;
	if( @args == 1 && ref( $args[0] ) eq 'ARRAY' ) {
		@args = @{$_[0]};
	}
	my( $source, $target ) = $self->_stringify_args( @args );
	$self->$orig( $source, $target );
};

=head2 reading_witnesses( $reading )

Return a list of sigils corresponding to the witnesses in which the reading appears.

=cut

sub reading_witnesses {
	my( $self, $reading ) = @_;
	# We need only check either the incoming or the outgoing edges; I have
	# arbitrarily chosen "incoming".  Thus, special-case the start node.
	if( $reading eq $self->start ) {
		return map { $_->sigil } $self->tradition->witnesses;
	}
	my %all_witnesses;
	foreach my $e ( $self->sequence->edges_to( $reading ) ) {
		my $wits = $self->sequence->get_edge_attributes( @$e );
		@all_witnesses{ keys %$wits } = 1;
	}
	my $acstr = $self->ac_label;
	foreach my $acwit ( grep { $_ =~ s/^(.*)\Q$acstr\E$/$1/ } keys %all_witnesses ) {
		delete $all_witnesses{$acwit.$acstr} if exists $all_witnesses{$acwit};
	}
	return keys %all_witnesses;
}

=head1 OUTPUT METHODS

=head2 as_svg( \%options )

Returns an SVG string that represents the graph, via as_dot and graphviz.
See as_dot for a list of options.  Must have GraphViz (dot) installed to run.

=cut

sub as_svg {
    my( $self, $opts ) = @_;
    throw( "Need GraphViz installed to output SVG" )
    	unless File::Which::which( 'dot' );
    my $want_subgraph = exists $opts->{'from'} || exists $opts->{'to'};
    $self->calculate_ranks() unless $self->_graphcalc_done;
    if( !$self->has_cached_svg || $opts->{'recalc'}	|| $want_subgraph ) {        
		my @cmd = qw/dot -Tsvg/;
		my( $svg, $err );
		my $dotfile = File::Temp->new();
		## USE FOR DEBUGGING
		# $dotfile->unlink_on_destroy(0);
		binmode $dotfile, ':utf8';
		print $dotfile $self->as_dot( $opts );
		push( @cmd, $dotfile->filename );
		run( \@cmd, ">", binary(), \$svg );
		$svg = decode_utf8( $svg );
		$self->cached_svg( $svg ) unless $want_subgraph;
		return $svg;
	} else {
		return $self->cached_svg;
	}
}


=head2 as_dot( \%options )

Returns a string that is the collation graph expressed in dot
(i.e. GraphViz) format.  Options include:

=over 4

=item * from

=item * to

=item * color_common

=back

=cut

sub as_dot {
    my( $self, $opts ) = @_;
    my $startrank = $opts->{'from'} if $opts;
    my $endrank = $opts->{'to'} if $opts;
    my $color_common = $opts->{'color_common'} if $opts;
    my $STRAIGHTENHACK = !$startrank && !$endrank && $self->end->rank 
       && $self->end->rank > 100;

    # Check the arguments
    if( $startrank ) {
    	return if $endrank && $startrank > $endrank;
    	return if $startrank > $self->end->rank;
	}
	if( defined $endrank ) {
		return if $endrank < 0;
		$endrank = undef if $endrank == $self->end->rank;
	}
	
    my $graph_name = $self->tradition->name;
    $graph_name =~ s/[^\w\s]//g;
    $graph_name = join( '_', split( /\s+/, $graph_name ) );

    my %graph_attrs = (
    	'rankdir' => 'LR',
    	'bgcolor' => 'none',
    	);
    my %node_attrs = (
    	'fontsize' => 14,
    	'fillcolor' => 'white',
    	'style' => 'filled',
    	'shape' => 'ellipse'
    	);
    my %edge_attrs = ( 
    	'arrowhead' => 'open',
    	'color' => '#000000',
    	'fontcolor' => '#000000',
    	);

    my $dot = sprintf( "digraph %s {\n", $graph_name );
    $dot .= "\tgraph " . _dot_attr_string( \%graph_attrs ) . ";\n";
    $dot .= "\tnode " . _dot_attr_string( \%node_attrs ) . ";\n";

	# Output substitute start/end readings if necessary
	if( $startrank ) {
		$dot .= "\t\"#SUBSTART#\" [ label=\"...\" ];\n";
	}
	if( $endrank ) {
		$dot .= "\t\"#SUBEND#\" [ label=\"...\" ];\n";	
	}
	if( $STRAIGHTENHACK ) {
		## HACK part 1
		$dot .= "\tsubgraph { rank=same \"#START#\" \"#SILENT#\" }\n";  
		$dot .= "\t\"#SILENT#\" [ shape=diamond,color=white,penwidth=0,label=\"\" ];"
	}
	my %used;  # Keep track of the readings that actually appear in the graph
	# Sort the readings by rank if we have ranks; this speeds layout.
	my @all_readings = $self->end->has_rank 
		? sort { $a->rank <=> $b->rank } $self->readings
		: $self->readings;
	# TODO Refrain from outputting lacuna nodes - just grey out the edges.
    foreach my $reading ( @all_readings ) {
    	# Only output readings within our rank range.
    	next if $startrank && $reading->rank < $startrank;
    	next if $endrank && $reading->rank > $endrank;
        $used{$reading->id} = 1;
        # Need not output nodes without separate labels
        next if $reading->id eq $reading->text;
        my $rattrs;
        my $label = $reading->text;
        $label .= '-' if $reading->join_next;
        $label = "-$label" if $reading->join_prior;
        $label =~ s/\"/\\\"/g;
		$rattrs->{'label'} = $label;
		$rattrs->{'fillcolor'} = '#b3f36d' if $reading->is_common && $color_common;
        $dot .= sprintf( "\t\"%s\" %s;\n", $reading->id, _dot_attr_string( $rattrs ) );
    }
    
	# Add the real edges. Need to weight one edge per rank jump, in a
	# continuous line.
	# my $weighted = $self->_add_edge_weights;
    my @edges = $self->paths;
	my( %substart, %subend );
    foreach my $edge ( @edges ) {
    	# Do we need to output this edge?
    	if( $used{$edge->[0]} && $used{$edge->[1]} ) {
    		my $label = $self->_path_display_label( $self->path_witnesses( $edge ) );
			my $variables = { %edge_attrs, 'label' => $label };
			
			# Account for the rank gap if necessary
			my $rank0 = $self->reading( $edge->[0] )->rank
				if $self->reading( $edge->[0] )->has_rank;
			my $rank1 = $self->reading( $edge->[1] )->rank
				if $self->reading( $edge->[1] )->has_rank;
			if( defined $rank0 && defined $rank1 && $rank1 - $rank0 > 1 ) {
				$variables->{'minlen'} = $rank1 - $rank0;
			}
			
			# Add the calculated edge weights
			# if( exists $weighted->{$edge->[0]} 
			# 	&& $weighted->{$edge->[0]} eq $edge->[1] ) {
			# 	# $variables->{'color'} = 'red';
			# 	$variables->{'weight'} = 3.0;
			# }

			# EXPERIMENTAL: make edge width reflect no. of witnesses
			my $extrawidth = scalar( $self->path_witnesses( $edge ) ) * 0.2;
			$variables->{'penwidth'} = $extrawidth + 0.8; # gives 1 for a single wit

			my $varopts = _dot_attr_string( $variables );
			$dot .= sprintf( "\t\"%s\" -> \"%s\" %s;\n", 
				$edge->[0], $edge->[1], $varopts );
        } elsif( $used{$edge->[0]} ) {
        	$subend{$edge->[0]} = 1;
        } elsif( $used{$edge->[1]} ) {
        	$substart{$edge->[1]} = 1;
        }
    }
    # Add substitute start and end edges if necessary
    foreach my $node ( keys %substart ) {
    	my $witstr = $self->_path_display_label ( $self->reading_witnesses( $self->reading( $node ) ) );
    	my $variables = { %edge_attrs, 'label' => $witstr };
        my $varopts = _dot_attr_string( $variables );
        $dot .= "\t\"#SUBSTART#\" -> \"$node\" $varopts;";
	}
    foreach my $node ( keys %subend ) {
    	my $witstr = $self->_path_display_label ( $self->reading_witnesses( $self->reading( $node ) ) );
    	my $variables = { %edge_attrs, 'label' => $witstr };
        my $varopts = _dot_attr_string( $variables );
        $dot .= "\t\"$node\" -> \"#SUBEND#\" $varopts;";
	}
	# HACK part 2
	if( $STRAIGHTENHACK ) {
		$dot .= "\t\"#END#\" -> \"#SILENT#\" [ color=white,penwidth=0 ];\n";
	}       

    $dot .= "}\n";
    return $dot;
}

sub _dot_attr_string {
	my( $hash ) = @_;
	my @attrs;
	foreach my $k ( sort keys %$hash ) {
		my $v = $hash->{$k};
		push( @attrs, $k.'="'.$v.'"' );
	}
	return( '[ ' . join( ', ', @attrs ) . ' ]' );
}

sub _add_edge_weights {
	my $self = shift;
	# Walk the graph from START to END, choosing the successor node with
	# the largest number of witness paths each time.
	my $weighted = {};
	my $curr = $self->start->id;
	my $ranked = $self->end->has_rank;
	while( $curr ne $self->end->id ) {
		my $rank = $ranked ? $self->reading( $curr )->rank : 0;
		my @succ = sort { $self->path_witnesses( $curr, $a )
							<=> $self->path_witnesses( $curr, $b ) } 
			$self->sequence->successors( $curr );
		my $next = pop @succ;
		my $nextrank = $ranked ? $self->reading( $next )->rank : 0;
		# Try to avoid lacunae in the weighted path.
		while( @succ && 
			   ( $self->reading( $next )->is_lacuna ||
			   	 $nextrank - $rank > 1 ) ){
			$next = pop @succ;
		}
		$weighted->{$curr} = $next;
		$curr = $next;
	}
	return $weighted;	
}

=head2 path_witnesses( $edge )

Returns the list of sigils whose witnesses are associated with the given edge.
The edge can be passed as either an array or an arrayref of ( $source, $target ).

=cut

sub path_witnesses {
	my( $self, @edge ) = @_;
	# If edge is an arrayref, cope.
	if( @edge == 1 && ref( $edge[0] ) eq 'ARRAY' ) {
		my $e = shift @edge;
		@edge = @$e;
	}
	my @wits = keys %{$self->sequence->get_edge_attributes( @edge )};
	return @wits;
}

sub _path_display_label {
	my $self = shift;
	my @wits = sort @_;
	my $maj = scalar( $self->tradition->witnesses ) * 0.6;
	if( scalar @wits > $maj ) {
		# TODO break out a.c. wits
		return 'majority';
	} else {
		return join( ', ', @wits );
	}
}

=head2 witnesses_at_rank

Returns a list of witnesses that are not lacunose, for a given rank.

=cut

sub witnesses_at_rank {
	my( $self, $rank ) = @_;
}		

=head2 as_graphml

Returns a GraphML representation of the collation.  The GraphML will contain 
two graphs. The first expresses the attributes of the readings and the witness 
paths that link them; the second expresses the relationships that link the 
readings.  This is the native transfer format for a tradition.

=begin testing

use Text::Tradition;

my $READINGS = 311;
my $PATHS = 361;

my $datafile = 't/data/florilegium_tei_ps.xml';
my $tradition = Text::Tradition->new( 'input' => 'TEI',
                                      'name' => 'test0',
                                      'file' => $datafile,
                                      'linear' => 1 );

ok( $tradition, "Got a tradition object" );
is( scalar $tradition->witnesses, 13, "Found all witnesses" );
ok( $tradition->collation, "Tradition has a collation" );

my $c = $tradition->collation;
is( scalar $c->readings, $READINGS, "Collation has all readings" );
is( scalar $c->paths, $PATHS, "Collation has all paths" );
is( scalar $c->relationships, 0, "Collation has all relationships" );

# Add a few relationships
$c->add_relationship( 'w123', 'w125', { 'type' => 'collated' } );
$c->add_relationship( 'w193', 'w196', { 'type' => 'collated' } );
$c->add_relationship( 'w257', 'w262', { 'type' => 'transposition' } );

# Now write it to GraphML and parse it again.

my $graphml = $c->as_graphml;
my $st = Text::Tradition->new( 'input' => 'Self', 'string' => $graphml );
is( scalar $st->collation->readings, $READINGS, "Reparsed collation has all readings" );
is( scalar $st->collation->paths, $PATHS, "Reparsed collation has all paths" );
is( scalar $st->collation->relationships, 3, "Reparsed collation has new relationships" );

=end testing

=cut

sub as_graphml {
    my( $self ) = @_;
	$self->calculate_ranks unless $self->_graphcalc_done;
	
    # Some namespaces
    my $graphml_ns = 'http://graphml.graphdrawing.org/xmlns';
    my $xsi_ns = 'http://www.w3.org/2001/XMLSchema-instance';
    my $graphml_schema = 'http://graphml.graphdrawing.org/xmlns ' .
        'http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd';

    # Create the document and root node
    my $graphml = XML::LibXML->createDocument( "1.0", "UTF-8" );
    my $root = $graphml->createElementNS( $graphml_ns, 'graphml' );
    $graphml->setDocumentElement( $root );
    $root->setNamespace( $xsi_ns, 'xsi', 0 );
    $root->setAttributeNS( $xsi_ns, 'schemaLocation', $graphml_schema );

    # Add the data keys for the graph
    my %graph_data_keys;
    my $gdi = 0;
    my @graph_attributes = qw/ version wit_list_separator baselabel linear ac_label /;
    foreach my $datum ( @graph_attributes ) {
    	$graph_data_keys{$datum} = 'dg'.$gdi++;
        my $key = $root->addNewChild( $graphml_ns, 'key' );
        $key->setAttribute( 'attr.name', $datum );
        $key->setAttribute( 'attr.type', $datum eq 'linear' ? 'boolean' : 'string' );
        $key->setAttribute( 'for', 'graph' );
        $key->setAttribute( 'id', $graph_data_keys{$datum} );    	
    }

    # Add the data keys for nodes
    my %node_data_keys;
    my $ndi = 0;
    my %node_data = ( 
    	id => 'string',
    	text => 'string',
    	rank => 'string',
    	is_start => 'boolean',
    	is_end => 'boolean',
    	is_lacuna => 'boolean',
    	is_common => 'boolean',
    	join_prior => 'boolean',
    	join_next => 'boolean',
    	);
    foreach my $datum ( keys %node_data ) {
        $node_data_keys{$datum} = 'dn'.$ndi++;
        my $key = $root->addNewChild( $graphml_ns, 'key' );
        $key->setAttribute( 'attr.name', $datum );
        $key->setAttribute( 'attr.type', $node_data{$datum} );
        $key->setAttribute( 'for', 'node' );
        $key->setAttribute( 'id', $node_data_keys{$datum} );
    }

    # Add the data keys for edges, i.e. witnesses
    my $edi = 0;
    my %edge_data_keys;
    my %edge_data = (
    	class => 'string',				# Class, deprecated soon
    	witness => 'string',			# ID/label for a path
    	relationship => 'string',		# ID/label for a relationship
    	extra => 'boolean',				# Path key
    	scope => 'string',				# Relationship key
    	annotation => 'string',			# Relationship key
    	non_correctable => 'boolean',	# Relationship key
    	non_independent => 'boolean',	# Relationship key
    	);
    foreach my $datum ( keys %edge_data ) {
        $edge_data_keys{$datum} = 'de'.$edi++;
        my $key = $root->addNewChild( $graphml_ns, 'key' );
        $key->setAttribute( 'attr.name', $datum );
        $key->setAttribute( 'attr.type', $edge_data{$datum} );
        $key->setAttribute( 'for', 'edge' );
        $key->setAttribute( 'id', $edge_data_keys{$datum} );
    }

    # Add the collation graph itself
    my $sgraph = $root->addNewChild( $graphml_ns, 'graph' );
    $sgraph->setAttribute( 'edgedefault', 'directed' );
    $sgraph->setAttribute( 'id', $self->tradition->name );
    $sgraph->setAttribute( 'parse.edgeids', 'canonical' );
    $sgraph->setAttribute( 'parse.edges', scalar($self->paths) );
    $sgraph->setAttribute( 'parse.nodeids', 'canonical' );
    $sgraph->setAttribute( 'parse.nodes', scalar($self->readings) );
    $sgraph->setAttribute( 'parse.order', 'nodesfirst' );
    	    
    # Collation attribute data
    foreach my $datum ( @graph_attributes ) {
    	my $value = $datum eq 'version' ? '3.0' : $self->$datum;
		_add_graphml_data( $sgraph, $graph_data_keys{$datum}, $value );
	}

    my $node_ctr = 0;
    my %node_hash;
    # Add our readings to the graph
    foreach my $n ( sort { $a->id cmp $b->id } $self->readings ) {
    	# Add to the main graph
        my $node_el = $sgraph->addNewChild( $graphml_ns, 'node' );
        my $node_xmlid = 'n' . $node_ctr++;
        $node_hash{ $n->id } = $node_xmlid;
        $node_el->setAttribute( 'id', $node_xmlid );
        foreach my $d ( keys %node_data ) {
        	my $nval = $n->$d;
        	_add_graphml_data( $node_el, $node_data_keys{$d}, $nval )
        		if defined $nval;
        }
    }

    # Add the path edges to the sequence graph
    my $edge_ctr = 0;
    foreach my $e ( sort { $a->[0] cmp $b->[0] } $self->sequence->edges() ) {
    	# We add an edge in the graphml for every witness in $e.
    	foreach my $wit ( sort $self->path_witnesses( $e ) ) {
			my( $id, $from, $to ) = ( 'e'.$edge_ctr++,
										$node_hash{ $e->[0] },
										$node_hash{ $e->[1] } );
			my $edge_el = $sgraph->addNewChild( $graphml_ns, 'edge' );
			$edge_el->setAttribute( 'source', $from );
			$edge_el->setAttribute( 'target', $to );
			$edge_el->setAttribute( 'id', $id );
			
			# It's a witness path, so add the witness
			my $base = $wit;
			my $key = $edge_data_keys{'witness'};
			# Is this an ante-corr witness?
			my $aclabel = $self->ac_label;
			if( $wit =~ /^(.*)\Q$aclabel\E$/ ) {
				# Keep the base witness
				$base = $1;
				# ...and record that this is an 'extra' reading path
				_add_graphml_data( $edge_el, $edge_data_keys{'extra'}, $aclabel );
			}
			_add_graphml_data( $edge_el, $edge_data_keys{'witness'}, $base );
			_add_graphml_data( $edge_el, $edge_data_keys{'class'}, 'path' );
		}
	}
	
	# Add the relationship graph to the XML
	$self->relations->_as_graphml( $graphml_ns, $root, \%node_hash, 
		$node_data_keys{'id'}, \%edge_data_keys );

    # Save and return the thing
    my $result = decode_utf8( $graphml->toString(1) );
    return $result;
}

sub _add_graphml_data {
    my( $el, $key, $value ) = @_;
    return unless defined $value;
    my $data_el = $el->addNewChild( $el->namespaceURI, 'data' );
    $data_el->setAttribute( 'key', $key );
    $data_el->appendText( $value );
}

=head2 as_csv

Returns a CSV alignment table representation of the collation graph, one
row per witness (or witness uncorrected.) 

=cut

sub as_csv {
    my( $self ) = @_;
    my $table = $self->alignment_table;
    my $csv = Text::CSV_XS->new( { binary => 1, quote_null => 0 } );    
    my @result;
    # Make the header row
    $csv->combine( map { $_->{'witness'} } @{$table->{'alignment'}} );
	push( @result, decode_utf8( $csv->string ) );
    # Make the rest of the rows
    foreach my $idx ( 0 .. $table->{'length'} - 1 ) {
    	my @rowobjs = map { $_->{'tokens'}->[$idx] } @{$table->{'alignment'}};
    	my @row = map { $_ ? $_->{'t'}->text : $_ } @rowobjs;
        $csv->combine( @row );
        push( @result, decode_utf8( $csv->string ) );
    }
    return join( "\n", @result );
}

=head2 alignment_table( $use_refs, $include_witnesses )

Return a reference to an alignment table, in a slightly enhanced CollateX
format which looks like this:

 $table = { alignment => [ { witness => "SIGIL", 
                             tokens => [ { t => "TEXT" }, ... ] },
                           { witness => "SIG2", 
                             tokens => [ { t => "TEXT" }, ... ] },
                           ... ],
            length => TEXTLEN };

If $use_refs is set to 1, the reading object is returned in the table 
instead of READINGTEXT; if not, the text of the reading is returned.

If $include_witnesses is set to a hashref, only the witnesses whose sigil
keys have a true hash value will be included.

=cut

sub alignment_table {
    my( $self ) = @_;
    $self->calculate_ranks() unless $self->_graphcalc_done;
    return $self->cached_table if $self->has_cached_table;
    
    # Make sure we can do this
	throw( "Need a linear graph in order to make an alignment table" )
		unless $self->linear;
	$self->calculate_ranks unless $self->end->has_rank;
	
    my $table = { 'alignment' => [], 'length' => $self->end->rank - 1 };
    my @all_pos = ( 1 .. $self->end->rank - 1 );
    foreach my $wit ( sort { $a->sigil cmp $b->sigil } $self->tradition->witnesses ) {
        # print STDERR "Making witness row(s) for " . $wit->sigil . "\n";
        my @wit_path = $self->reading_sequence( $self->start, $self->end, $wit->sigil );
        my @row = _make_witness_row( \@wit_path, \@all_pos );
        push( @{$table->{'alignment'}}, 
        	{ 'witness' => $wit->sigil, 'tokens' => \@row } );
        if( $wit->is_layered ) {
        	my @wit_ac_path = $self->reading_sequence( $self->start, $self->end, 
        		$wit->sigil.$self->ac_label );
            my @ac_row = _make_witness_row( \@wit_ac_path, \@all_pos );
			push( @{$table->{'alignment'}},
				{ 'witness' => $wit->sigil.$self->ac_label, 'tokens' => \@ac_row } );
        }           
    }
    $self->cached_table( $table );
    return $table;
}

sub _make_witness_row {
    my( $path, $positions ) = @_;
    my %char_hash;
    map { $char_hash{$_} = undef } @$positions;
    my $debug = 0;
    foreach my $rdg ( @$path ) {
        my $rtext = $rdg->text;
        $rtext = '#LACUNA#' if $rdg->is_lacuna;
        print STDERR "rank " . $rdg->rank . "\n" if $debug;
        # print STDERR "No rank for " . $rdg->id . "\n" unless defined $rdg->rank;
        $char_hash{$rdg->rank} = { 't' => $rdg };
    }
    my @row = map { $char_hash{$_} } @$positions;
    # Fill in lacuna markers for undef spots in the row
    my $last_el = shift @row;
    my @filled_row = ( $last_el );
    foreach my $el ( @row ) {
        # If we are using node reference, make the lacuna node appear many times
        # in the table.  If not, use the lacuna tag.
        if( $last_el && $last_el->{'t'}->is_lacuna && !defined $el ) {
            $el = $last_el;
        }
        push( @filled_row, $el );
        $last_el = $el;
    }
    return @filled_row;
}

=head1 NAVIGATION METHODS

=head2 reading_sequence( $first, $last, $sigil, $backup )

Returns the ordered list of readings, starting with $first and ending
with $last, for the witness given in $sigil. If a $backup sigil is 
specified (e.g. when walking a layered witness), it will be used wherever
no $sigil path exists.  If there is a base text reading, that will be
used wherever no path exists for $sigil or $backup.

=cut

# TODO Think about returning some lazy-eval iterator.
# TODO Get rid of backup; we should know from what witness is whether we need it.

sub reading_sequence {
    my( $self, $start, $end, $witness ) = @_;

    $witness = $self->baselabel unless $witness;
    my @readings = ( $start );
    my %seen;
    my $n = $start;
    while( $n && $n->id ne $end->id ) {
        if( exists( $seen{$n->id} ) ) {
            throw( "Detected loop for $witness at " . $n->id );
        }
        $seen{$n->id} = 1;
        
        my $next = $self->next_reading( $n, $witness );
        unless( $next ) {
            throw( "Did not find any path for $witness from reading " . $n->id );
        }
        push( @readings, $next );
        $n = $next;
    }
    # Check that the last reading is our end reading.
    my $last = $readings[$#readings];
    throw( "Last reading found from " . $start->text .
        " for witness $witness is not the end!" ) # TODO do we get this far?
        unless $last->id eq $end->id;
    
    return @readings;
}

=head2 next_reading( $reading, $sigil );

Returns the reading that follows the given reading along the given witness
path.  

=cut

sub next_reading {
    # Return the successor via the corresponding path.
    my $self = shift;
    my $answer = $self->_find_linked_reading( 'next', @_ );
	return undef unless $answer;
    return $self->reading( $answer );
}

=head2 prior_reading( $reading, $sigil )

Returns the reading that precedes the given reading along the given witness
path.  

=cut

sub prior_reading {
    # Return the predecessor via the corresponding path.
    my $self = shift;
    my $answer = $self->_find_linked_reading( 'prior', @_ );
    return $self->reading( $answer );
}

sub _find_linked_reading {
    my( $self, $direction, $node, $path ) = @_;
    
    # Get a backup if we are dealing with a layered witness
    my $alt_path;
    my $aclabel = $self->ac_label;
    if( $path && $path =~ /^(.*)\Q$aclabel\E$/ ) {
    	$alt_path = $1;
    }
    
    my @linked_paths = $direction eq 'next' 
        ? $self->sequence->edges_from( $node ) 
        : $self->sequence->edges_to( $node );
    return undef unless scalar( @linked_paths );
    
    # We have to find the linked path that contains all of the
    # witnesses supplied in $path.
    my( @path_wits, @alt_path_wits );
    @path_wits = sort( $self->_witnesses_of_label( $path ) ) if $path;
    @alt_path_wits = sort( $self->_witnesses_of_label( $alt_path ) ) if $alt_path;
    my $base_le;
    my $alt_le;
    foreach my $le ( @linked_paths ) {
        if( $self->sequence->has_edge_attribute( @$le, $self->baselabel ) ) {
            $base_le = $le;
        }
		my @le_wits = sort $self->path_witnesses( $le );
		if( _is_within( \@path_wits, \@le_wits ) ) {
			# This is the right path.
			return $direction eq 'next' ? $le->[1] : $le->[0];
		} elsif( _is_within( \@alt_path_wits, \@le_wits ) ) {
			$alt_le = $le;
		}
    }
    # Got this far? Return the alternate path if it exists.
    return $direction eq 'next' ? $alt_le->[1] : $alt_le->[0]
        if $alt_le;

    # Got this far? Return the base path if it exists.
    return $direction eq 'next' ? $base_le->[1] : $base_le->[0]
        if $base_le;

    # Got this far? We have no appropriate path.
    warn "Could not find $direction node from " . $node->id 
        . " along path $path";
    return undef;
}

# Some set logic.
sub _is_within {
    my( $set1, $set2 ) = @_;
    my $ret = @$set1; # will be 0, i.e. false, if set1 is empty
    foreach my $el ( @$set1 ) {
        $ret = 0 unless grep { /^\Q$el\E$/ } @$set2;
    }
    return $ret;
}

# Return the string that joins together a list of witnesses for
# display on a single path.
sub _witnesses_of_label {
    my( $self, $label ) = @_;
    my $regex = $self->wit_list_separator;
    my @answer = split( /\Q$regex\E/, $label );
    return @answer;
}

=head2 common_readings

Returns the list of common readings in the graph (i.e. those readings that are
shared by all non-lacunose witnesses.)

=cut

sub common_readings {
	my $self = shift;
	my @common = grep { $_->is_common } $self->readings;
	return @common;
}

=head2 path_text( $sigil, $mainsigil [, $start, $end ] )

Returns the text of a witness (plus its backup, if we are using a layer)
as stored in the collation.  The text is returned as a string, where the
individual readings are joined with spaces and the meta-readings (e.g.
lacunae) are omitted.  Optional specification of $start and $end allows
the generation of a subset of the witness text.

=cut

sub path_text {
	my( $self, $wit, $start, $end ) = @_;
	$start = $self->start unless $start;
	$end = $self->end unless $end;
	my @path = grep { !$_->is_meta } $self->reading_sequence( $start, $end, $wit );
	my $pathtext = '';
	my $last;
	foreach my $r ( @path ) {
		if( $r->join_prior || !$last || $last->join_next ) {
			$pathtext .= $r->text;
		} else {
			$pathtext .= ' ' . $r->text;
		}
		$last = $r;
	}
	return $pathtext;
}

=head1 INITIALIZATION METHODS

These are mostly for use by parsers.

=head2 make_witness_path( $witness )

Link the array of readings contained in $witness->path (and in 
$witness->uncorrected_path if it exists) into collation paths.
Clear out the arrays when finished.

=head2 make_witness_paths

Call make_witness_path for all witnesses in the tradition.

=cut

# For use when a collation is constructed from a base text and an apparatus.
# We have the sequences of readings and just need to add path edges.
# When we are done, clear out the witness path attributes, as they are no
# longer needed.
# TODO Find a way to replace the witness path attributes with encapsulated functions?

sub make_witness_paths {
    my( $self ) = @_;
    foreach my $wit ( $self->tradition->witnesses ) {
        # print STDERR "Making path for " . $wit->sigil . "\n";
        $self->make_witness_path( $wit );
    }
}

sub make_witness_path {
    my( $self, $wit ) = @_;
    my @chain = @{$wit->path};
    my $sig = $wit->sigil;
    foreach my $idx ( 0 .. $#chain-1 ) {
        $self->add_path( $chain[$idx], $chain[$idx+1], $sig );
    }
    if( $wit->is_layered ) {
        @chain = @{$wit->uncorrected_path};
        foreach my $idx( 0 .. $#chain-1 ) {
            my $source = $chain[$idx];
            my $target = $chain[$idx+1];
            $self->add_path( $source, $target, $sig.$self->ac_label )
                unless $self->has_path( $source, $target, $sig );
        }
    }
    $wit->clear_path;
    $wit->clear_uncorrected_path;
}

=head2 calculate_ranks

Calculate the reading ranks (that is, their aligned positions relative
to each other) for the graph.  This can only be called on linear collations.

=begin testing

use Text::Tradition;

my $cxfile = 't/data/Collatex-16.xml';
my $t = Text::Tradition->new( 
    'name'  => 'inline', 
    'input' => 'CollateX',
    'file'  => $cxfile,
    );
my $c = $t->collation;

# Make an svg
my $table = $c->alignment_table;
ok( $c->has_cached_table, "Alignment table was cached" );
is( $c->alignment_table, $table, "Cached table returned upon second call" );
$c->calculate_ranks;
is( $c->alignment_table, $table, "Cached table retained with no rank change" );
$c->add_relationship( 'n9', 'n23', { 'type' => 'spelling' } );
isnt( $c->alignment_table, $table, "Alignment table changed after relationship add" );

=end testing

=cut

sub calculate_ranks {
    my $self = shift;
    # Save the existing ranks, in case we need to invalidate the cached SVG.
    my %existing_ranks;
    # Walk a version of the graph where every node linked by a relationship 
    # edge is fundamentally the same node, and do a topological ranking on
    # the nodes in this graph.
    my $topo_graph = Graph->new();
    my %rel_containers;
    my $rel_ctr = 0;
    # Add the nodes
    foreach my $r ( $self->readings ) {
        next if exists $rel_containers{$r->id};
        my @rels = $r->related_readings( 'colocated' );
        if( @rels ) {
            # Make a relationship container.
            push( @rels, $r );
            my $rn = 'rel_container_' . $rel_ctr++;
            $topo_graph->add_vertex( $rn );
            foreach( @rels ) {
                $rel_containers{$_->id} = $rn;
            }
        } else {
            # Add a new node to mirror the old node.
            $rel_containers{$r->id} = $r->id;
            $topo_graph->add_vertex( $r->id );
        }
    }

    # Add the edges.
    foreach my $r ( $self->readings ) {
		$existing_ranks{$r} = $r->rank;
        foreach my $n ( $self->sequence->successors( $r->id ) ) {
        	my( $tfrom, $tto ) = ( $rel_containers{$r->id},
        		$rel_containers{$n} );
        	# $DB::single = 1 unless $tfrom && $tto;
            $topo_graph->add_edge( $tfrom, $tto );
        }
    }
    
    # Now do the rankings, starting with the start node.
    my $topo_start = $rel_containers{$self->start->id};
    my $node_ranks = { $topo_start => 0 };
    my @curr_origin = ( $topo_start );
    # A little iterative function.
    while( @curr_origin ) {
        @curr_origin = _assign_rank( $topo_graph, $node_ranks, @curr_origin );
    }
    # Transfer our rankings from the topological graph to the real one.
    foreach my $r ( $self->readings ) {
        if( defined $node_ranks->{$rel_containers{$r->id}} ) {
            $r->rank( $node_ranks->{$rel_containers{$r->id}} );
        } else {
        	# Die. Find the last rank we calculated.
        	my @all_defined = sort { $node_ranks->{$rel_containers{$a->id}}
        			 <=> $node_ranks->{$rel_containers{$b->id}} }
        		$self->readings;
        	my $last = pop @all_defined;
            throw( "Ranks not calculated after $last - do you have a cycle in the graph?" );
        }
    }
    # Do we need to invalidate the cached data?
    if( $self->has_cached_svg || $self->has_cached_table ) {
    	foreach my $r ( $self->readings ) {
    		next if defined( $existing_ranks{$r} ) 
    			&& $existing_ranks{$r} == $r->rank;
    		# Something has changed, so clear the cache
    		$self->_clear_cache;
			# ...and recalculate the common readings.
			$self->calculate_common_readings();
    		last;
    	}
    }
	# The graph calculation information is now up to date.
	$self->_graphcalc_done(1);
}

sub _assign_rank {
    my( $graph, $node_ranks, @current_nodes ) = @_;
    # Look at each of the children of @current_nodes.  If all the child's 
    # parents have a rank, assign it the highest rank + 1 and add it to 
    # @next_nodes.  Otherwise skip it; we will return when the highest-ranked
    # parent gets a rank.
    my @next_nodes;
    foreach my $c ( @current_nodes ) {
        warn "Current reading $c has no rank!"
            unless exists $node_ranks->{$c};
        # print STDERR "Looking at child of node $c, rank " 
        #     . $node_ranks->{$c} . "\n";
        foreach my $child ( $graph->successors( $c ) ) {
            next if exists $node_ranks->{$child};
            my $highest_rank = -1;
            my $skip = 0;
            foreach my $parent ( $graph->predecessors( $child ) ) {
                if( exists $node_ranks->{$parent} ) {
                    $highest_rank = $node_ranks->{$parent} 
                        if $highest_rank <= $node_ranks->{$parent};
                } else {
                    $skip = 1;
                    last;
                }
            }
            next if $skip;
            my $c_rank = $highest_rank + 1;
            # print STDERR "Assigning rank $c_rank to node $child \n";
            $node_ranks->{$child} = $c_rank;
            push( @next_nodes, $child );
        }
    }
    return @next_nodes;
}

sub _clear_cache {
	my $self = shift;
	$self->wipe_svg if $self->has_cached_svg;
	$self->wipe_table if $self->has_cached_table;
}	


=head2 flatten_ranks

A convenience method for parsing collation data.  Searches the graph for readings
with the same text at the same rank, and merges any that are found.

=cut

sub flatten_ranks {
    my $self = shift;
    my %unique_rank_rdg;
    foreach my $rdg ( $self->readings ) {
        next unless $rdg->has_rank;
        my $key = $rdg->rank . "||" . $rdg->text;
        if( exists $unique_rank_rdg{$key} ) {
            # Combine!
        	# print STDERR "Combining readings at same rank: $key\n";
            $self->merge_readings( $unique_rank_rdg{$key}, $rdg );
            # TODO see if this now makes a common point.
        } else {
            $unique_rank_rdg{$key} = $rdg;
        }
    }
}
	

=head2 calculate_common_readings

Goes through the graph identifying the readings that appear in every witness 
(apart from those with lacunae at that spot.) Marks them as common and returns
the list.

=begin testing

use Text::Tradition;

my $cxfile = 't/data/Collatex-16.xml';
my $t = Text::Tradition->new( 
    'name'  => 'inline', 
    'input' => 'CollateX',
    'file'  => $cxfile,
    );
my $c = $t->collation;

my @common = $c->calculate_common_readings();
is( scalar @common, 8, "Found correct number of common readings" );
my @marked = sort $c->common_readings();
is( scalar @common, 8, "All common readings got marked as such" );
my @expected = qw/ n1 n12 n16 n19 n20 n5 n6 n7 /;
is_deeply( \@marked, \@expected, "Found correct list of common readings" );

=end testing

=cut

sub calculate_common_readings {
	my $self = shift;
	my @common;
	map { $_->is_common( 0 ) } $self->readings;
	# Implicitly calls calculate_ranks
	my $table = $self->alignment_table;
	foreach my $idx ( 0 .. $table->{'length'} - 1 ) {
		my @row = map { $_->{'tokens'}->[$idx] 
							? $_->{'tokens'}->[$idx]->{'t'} : '' } 
					@{$table->{'alignment'}};
		my %hash;
		foreach my $r ( @row ) {
			if( $r ) {
				$hash{$r->id} = $r unless $r->is_meta;
			} else {
				$hash{'UNDEF'} = $r;
			}
		}
		if( keys %hash == 1 && !exists $hash{'UNDEF'} ) {
			my( $r ) = values %hash;
			$r->is_common( 1 );
			push( @common, $r );
		}
	}
	return @common;
}

=head2 text_from_paths

Calculate the text array for all witnesses from the path, for later consistency
checking.  Only to be used if there is no non-graph-based way to know the
original texts.

=cut

sub text_from_paths {
	my $self = shift;
    foreach my $wit ( $self->tradition->witnesses ) {
    	my @text = split( /\s+/, 
    		$self->reading_sequence( $self->start, $self->end, $wit->sigil ) );
    	$wit->text( \@text );
    	if( $wit->is_layered ) {
			my @uctext = split( /\s+/, 
				$self->reading_sequence( $self->start, $self->end, 
					$wit->sigil.$self->ac_label ) );
			$wit->text( \@uctext );
    	}
    }    
}

=head1 UTILITY FUNCTIONS

=head2 common_predecessor( $reading_a, $reading_b )

Find the last reading that occurs in sequence before both the given readings.

=head2 common_successor( $reading_a, $reading_b )

Find the first reading that occurs in sequence after both the given readings.
    
=begin testing

use Text::Tradition;

my $cxfile = 't/data/Collatex-16.xml';
my $t = Text::Tradition->new( 
    'name'  => 'inline', 
    'input' => 'CollateX',
    'file'  => $cxfile,
    );
my $c = $t->collation;

is( $c->common_predecessor( 'n9', 'n23' )->id, 
    'n20', "Found correct common predecessor" );
is( $c->common_successor( 'n9', 'n23' )->id, 
    '#END#', "Found correct common successor" );

is( $c->common_predecessor( 'n19', 'n17' )->id, 
    'n16', "Found correct common predecessor for readings on same path" );
is( $c->common_successor( 'n21', 'n26' )->id, 
    '#END#', "Found correct common successor for readings on same path" );

=end testing

=cut

## Return the closest reading that is a predecessor of both the given readings.
sub common_predecessor {
	my $self = shift;
	my( $r1, $r2 ) = $self->_objectify_args( @_ );
	return $self->_common_in_path( $r1, $r2, 'predecessors' );
}

sub common_successor {
	my $self = shift;
	my( $r1, $r2 ) = $self->_objectify_args( @_ );
	return $self->_common_in_path( $r1, $r2, 'successors' );
}

sub _common_in_path {
	my( $self, $r1, $r2, $dir ) = @_;
	my $iter = $r1->rank > $r2->rank ? $r1->rank : $r2->rank;
	$iter = $self->end->rank - $iter if $dir eq 'successors';
	my @candidates;
	my @last_checked = ( $r1, $r2 );
	my %all_seen;
	while( !@candidates ) {
		my @new_lc;
		foreach my $lc ( @last_checked ) {
			foreach my $p ( $lc->$dir ) {
				if( $all_seen{$p->id} ) {
					push( @candidates, $p );
				} else {
					$all_seen{$p->id} = 1;
					push( @new_lc, $p );
				}
			}
		}
		@last_checked = @new_lc;
	}
	my @answer = sort { $a->rank <=> $b->rank } @candidates;
	return $dir eq 'predecessors' ? pop( @answer ) : shift ( @answer );
}

sub throw {
	Text::Tradition::Error->throw( 
		'ident' => 'Collation error',
		'message' => $_[0],
		);
}

no Moose;
__PACKAGE__->meta->make_immutable;

=head1 LICENSE

This package is free software and is provided "as is" without express
or implied warranty.  You can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 AUTHOR

Tara L Andrews E<lt>aurum@cpan.orgE<gt>