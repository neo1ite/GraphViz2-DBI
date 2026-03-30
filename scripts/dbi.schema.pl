#!/usr/bin/env perl
#
# Note: t/test.t searches for the next line.
# Annotation: Demonstrates graphing a database schema.

use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use Time::HiRes qw(time);

use DBI;
use DBIx::Admin::TableInfo;
use GraphViz2;
use GraphViz2::DBI;

sub script_trace {
	return unless $ENV{GRAPHVIZ2_DBI_DEBUG};
	my ( $msg, $t0 ) = @_;
	if ( defined $t0 ) {
		warn sprintf "[dbi.schema.pl] trace: $msg (%.2fs)\n", time - $t0;
	}
	else {
		warn "[dbi.schema.pl] trace: $msg\n";
	}
}

if ( $ENV{GRAPHVIZ2_DBI_DEBUG} ) {
	print STDERR "# GraphViz2::DBI $GraphViz2::DBI::VERSION from $INC{'GraphViz2/DBI.pm'}\n";
}

if (! $ENV{DBI_DSN})
{
	print "DBI_DSN etc not set\n";

	# Return 0 for OK and 1 for error.

	exit 1;
}

# Visual theme for schema SVG/PNG: light canvas, filled Mrecord nodes, soft edges.
my $graph = GraphViz2->new(
	global => {
		directed              => 1,
		combine_node_and_port => 0,
	},
	graph => {
		rankdir   => 'TB',
		bgcolor   => '#f0f4f8',
		splines   => 'true',
		pad       => '0.55',
		nodesep   => '0.48',
		ranksep   => '0.95',
		fontname  => 'Helvetica',
		fontsize  => 11,
		fontcolor => '#1e293b',
		labelloc  => 't',
		label     => 'Database schema',
	},
	node => {
		shape     => 'Mrecord',
		style     => 'filled',
		fillcolor => '#ffffff',
		color     => '#94a3b8',
		penwidth  => 1.1,
		fontname  => 'Helvetica',
		fontsize  => 9,
		fontcolor => '#0f172a',
	},
	edge => {
		color     => '#64748b',
		penwidth  => 0.85,
		arrowsize => 0.65,
		fontname  => 'Helvetica',
		fontsize  => 8,
		fontcolor => '#64748b',
	},
);
my($attr)              = {};
$$attr{sqlite_unicode} = 1 if ($ENV{DBI_DSN} =~ /SQLite/i);

my $t_script = $ENV{GRAPHVIZ2_DBI_DEBUG} ? time : undef;
script_trace('DBI->connect ...');
my($dbh) = DBI->connect( $ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS}, $attr );
exit 1 if !$dbh;
script_trace( 'DBI connected', $t_script ) if defined $t_script;

$dbh->do('PRAGMA foreign_keys = ON') if $ENV{DBI_DSN} =~ /SQLite/i;
# PostgreSQL: comma-separated schema list, e.g. public,crm,gms (must match TableInfo / search_path)
if ( $ENV{DBI_DSN} =~ /dbi:Pg:/i && $ENV{DBI_SCHEMA} ) {
	script_trace("SET search_path TO $ENV{DBI_SCHEMA}");
	$dbh->do("SET search_path TO $ENV{DBI_SCHEMA}");
}

# Empty SVG often means no tables in search_path — try: GRAPHVIZ2_DBI_DEBUG=1 DBI_SCHEMA=public,...

script_trace('GraphViz2::DBI->new');
my($g) = GraphViz2::DBI->new( dbh => $dbh, graph => $graph );

my $t_create = $ENV{GRAPHVIZ2_DBI_DEBUG} ? time : undef;
script_trace('GraphViz2::DBI->create (metadata + graph build; can take minutes on large DBs)');
$g->create;
script_trace( 'GraphViz2::DBI->create done', $t_create ) if defined $t_create;

my($format)      = shift || 'svg';
my($output_file) = shift || File::Spec -> catfile('html', "dbi.schema.$format");

script_trace("output: format=$format file=$output_file");

my $out_dir = dirname($output_file);
if ( $out_dir ne '.' && $out_dir ne '' ) {
	script_trace("make_path($out_dir)");
	make_path($out_dir);
}

my $t_run = $ENV{GRAPHVIZ2_DBI_DEBUG} ? time : undef;
script_trace('GraphViz2->run (invokes Graphviz/dot; large graphs are slow here)');
$graph->run( format => $format, output_file => $output_file );
script_trace( 'GraphViz2->run finished', $t_run ) if defined $t_run;
script_trace( 'script finished', $t_script ) if defined $t_script;

# Return 0 for OK and 1 for error.

exit 0;
