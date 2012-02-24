#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => 'Test::Pod::Coverage 1.04 required' if $@;
plan skip_all => 'set TEST_POD to enable this test' unless $ENV{TEST_POD};

my %mods;
map { $mods{$_} = 1 } all_modules();
if( -e 'MANIFEST.SKIP' ) {
	open( SKIP, 'MANIFEST.SKIP' ) or die "Could not open skip file";
	while(<SKIP>) {
		chomp;
		next unless /^lib/;
		s/^lib\///;
		s/\.pm//;
		s/\//::/g;
		delete $mods{$_};
	}
	close SKIP;
}
		
foreach my $mod ( keys %mods ) {
	pod_coverage_ok( $mod, { also_private => [ qw/ BUILD throw / ] } );
}

done_testing();