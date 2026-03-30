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
use Getopt::Long qw(GetOptions);
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

GetOptions(
	'inheritance' => \my $opt_inheritance,
	'help'        => \my $opt_help,
) or exit 2;

if ($opt_help) {
	print <<'USAGE';
Usage: dbi.schema.pl [options] [format [output_file]]

  Without options: builds a foreign-key graph (tables and FK edges from DB metadata).

Options:
  --inheritance   PostgreSQL only: graph of table inheritance (pg_inherits / INHERITS),
                  not foreign keys. Optional DBI_SCHEMA filters edges touching listed schemas.
  --help          This text.

Environment:
  DBI_DSN, DBI_USER, DBI_PASS — connection (required)
  DBI_SCHEMA       — comma-separated PostgreSQL schemas (search_path; also filters inheritance)

Examples:
  dbi.schema.pl
  dbi.schema.pl --inheritance
  dbi.schema.pl --inheritance svg html/inherits.svg
USAGE
	exit 0;
}

if ( $ENV{GRAPHVIZ2_DBI_DEBUG} ) {
	print STDERR "# GraphViz2::DBI $GraphViz2::DBI::VERSION from $INC{'GraphViz2/DBI.pm'}\n";
}

if ( ! $ENV{DBI_DSN} ) {
	print "DBI_DSN etc not set\n";
	exit 1;
}

if ( $opt_inheritance && $ENV{DBI_DSN} !~ /dbi:Pg:/i ) {
	print STDERR "dbi.schema.pl: --inheritance requires PostgreSQL (dbi:Pg in DBI_DSN)\n";
	exit 1;
}

# Visual theme for FK schema SVG/PNG: light canvas, filled Mrecord nodes, soft edges.
my $fk_graph = GraphViz2->new(
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
my $attr = {};
$$attr{sqlite_unicode} = 1 if ( $ENV{DBI_DSN} =~ /SQLite/i );

my $t_script = $ENV{GRAPHVIZ2_DBI_DEBUG} ? time : undef;
script_trace('DBI->connect ...');
my $dbh = DBI->connect( $ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS}, $attr );
exit 1 if !$dbh;
script_trace( 'DBI connected', $t_script ) if defined $t_script;

$dbh->do('PRAGMA foreign_keys = ON') if $ENV{DBI_DSN} =~ /SQLite/i;
# PostgreSQL: comma-separated schema list, e.g. public,crm,gms (must match TableInfo / search_path)
if ( $ENV{DBI_DSN} =~ /dbi:Pg:/i && $ENV{DBI_SCHEMA} ) {
	script_trace("SET search_path TO $ENV{DBI_SCHEMA}");
	$dbh->do("SET search_path TO $ENV{DBI_SCHEMA}");
}

my $format      = shift @ARGV || 'svg';
my $output_file = shift @ARGV;

if ($opt_inheritance) {
	script_trace('GraphViz2::DBI->new (inheritance mode)');
	my $g = GraphViz2::DBI->new( dbh => $dbh );
	my @schemas = ();
	if ( $ENV{DBI_SCHEMA} ) {
		@schemas = grep { $_ ne '' } split /\s*,\s*/, $ENV{DBI_SCHEMA};
	}
	my $t_inh = $ENV{GRAPHVIZ2_DBI_DEBUG} ? time : undef;
	script_trace('GraphViz2::DBI->create_inheritance (pg_inherits)');
	if (@schemas) {
		$g->create_inheritance( schemas => \@schemas );
	}
	else {
		$g->create_inheritance;
	}
	script_trace( 'GraphViz2::DBI->create_inheritance done', $t_inh ) if defined $t_inh;

	$output_file ||= File::Spec->catfile( 'html', "dbi.schema.inheritance.$format" );
	script_trace("output: format=$format file=$output_file");

	my $out_dir = dirname($output_file);
	if ( $out_dir ne '.' && $out_dir ne '' ) {
		script_trace("make_path($out_dir)");
		make_path($out_dir);
	}

	my $t_run = $ENV{GRAPHVIZ2_DBI_DEBUG} ? time : undef;
	script_trace('inheritance_graph->run (Graphviz/dot)');
	$g->inheritance_graph->run( format => $format, output_file => $output_file );
	script_trace( 'inheritance_graph->run finished', $t_run ) if defined $t_run;
}
else {
	# Empty SVG often means no tables in search_path — try: GRAPHVIZ2_DBI_DEBUG=1 DBI_SCHEMA=public,...

	script_trace('GraphViz2::DBI->new');
	my $g = GraphViz2::DBI->new( dbh => $dbh, graph => $fk_graph );

	my $t_create = $ENV{GRAPHVIZ2_DBI_DEBUG} ? time : undef;
	script_trace('GraphViz2::DBI->create (metadata + graph build; can take minutes on large DBs)');
	$g->create;
	script_trace( 'GraphViz2::DBI->create done', $t_create ) if defined $t_create;

	$output_file ||= File::Spec->catfile( 'html', "dbi.schema.$format" );
	script_trace("output: format=$format file=$output_file");

	my $out_dir = dirname($output_file);
	if ( $out_dir ne '.' && $out_dir ne '' ) {
		script_trace("make_path($out_dir)");
		make_path($out_dir);
	}

	my $t_run = $ENV{GRAPHVIZ2_DBI_DEBUG} ? time : undef;
	script_trace('GraphViz2->run (invokes Graphviz/dot; large graphs are slow here)');
	$fk_graph->run( format => $format, output_file => $output_file );
	script_trace( 'GraphViz2->run finished', $t_run ) if defined $t_run;
}

script_trace( 'script finished', $t_script ) if defined $t_script;

# Return 0 for OK and 1 for error.

exit 0;
