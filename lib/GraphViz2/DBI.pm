package GraphViz2::DBI;

use strict;
use warnings;
use warnings  qw(FATAL utf8); # Fatalize encoding glitches.

our $VERSION = '2.56';

# Localized in create() when debug is true so _trace runs without GRAPHVIZ2_DBI_DEBUG.
our $_trace_for_create;

use Carp qw(croak);
use DBIx::Admin::TableInfo;
use GraphViz2;
use List::Util qw(max min);
use Moo;
use Time::HiRes qw(time);

has dbh => (
	is       => 'rw',
	required => 1,
);

has graph => (
	default  => sub {
		GraphViz2->new(
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
	},
	is       => 'rw',
	#isa     => 'GraphViz2',
	required => 0,
);

has inheritance_graph => (
	is        => 'rw',
	predicate => 'has_inheritance_graph',
);

sub _new_inheritance_graph {
	my ($class) = @_;
	# LR + blue + light canvas, in the spirit of GraphViz2 ISA graphs (see perl-graph-isa/generate_isa_graph.pl).
	return GraphViz2->new(
		global => {
			directed              => 1,
			combine_node_and_port => 0,
		},
		graph => {
			rankdir   => 'LR',
			bgcolor   => 'transparent',
			splines   => 'true',
			pad       => '0.55',
			nodesep   => '0.42',
			ranksep   => '0.88',
			fontname  => 'Helvetica',
			fontsize  => 11,
			fontcolor => '#1e293b',
			labelloc  => 't',
			label     => 'Table inheritance (PostgreSQL INHERITS)',
		},
		node => {
			shape     => 'box',
			style     => 'rounded,filled',
			fillcolor => 'transparent',
			fontname  => 'Helvetica',
			fontsize  => 9,
		},
		edge => {
			color     => '#2563eb',
			penwidth  => 0.95,
			arrowsize => 0.72,
			style     => 'solid',
		},
	);
}

# Saturated distinct hues per inheritance root (superclass); edges use tail (parent) color.
my @INHERITANCE_ROOT_PALETTE = (
	'#b91c1c', '#2563eb', '#15803d', '#c2410c', '#7c3aed',
	'#db2777', '#0d9488', '#ca8a04', '#4f46e5', '#e11d48',
	'#0284c7', '#65a30d', '#c026d3', '#ea580c', '#6366f1',
	'#dc2626', '#0891b2', '#a855f7', '#059669', '#d946ef',
);

use constant _INHERIT_LIGHTEN_L => 0.09;

sub _hex_to_rgb1 {
	my ($hex) = @_;
	return unless defined $hex && $hex =~ /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i;
	return ( hex($1) / 255, hex($2) / 255, hex($3) / 255 );
}

sub _rgb1_to_hex {
	my ( $r, $g, $b ) = @_;
	$r = min( 1, max( 0, $r ) );
	$g = min( 1, max( 0, $g ) );
	$b = min( 1, max( 0, $b ) );
	return sprintf '#%02x%02x%02x', map { int( $_ * 255 + 0.5 ) } ( $r, $g, $b );
}

sub _rgb_to_hsl {
	my ( $r, $g, $b ) = @_;
	my $mx = max( $r, $g, $b );
	my $mn = min( $r, $g, $b );
	my $L  = ( $mx + $mn ) / 2;
	if ( $mx == $mn ) {
		return ( 0, 0, $L );
	}
	my $d = $mx - $mn;
	my $S = $L > 0.5 ? $d / ( 2 - $mx - $mn ) : $d / ( $mx + $mn );
	my $H;
	if ( $mx == $r ) {
		$H = ( ( $g - $b ) / $d + ( $g < $b ? 6 : 0 ) ) / 6;
	}
	elsif ( $mx == $g ) {
		$H = ( ( $b - $r ) / $d + 2 ) / 6;
	}
	else {
		$H = ( ( $r - $g ) / $d + 4 ) / 6;
	}
	return ( $H * 360, $S, $L );
}

sub _hue_to_rgb_ch {
	my ( $p, $q, $t ) = @_;
	$t += 1 if $t < 0;
	$t -= 1 if $t > 1;
	return $p + ( $q - $p ) * 6 * $t         if $t < 1 / 6;
	return $q                                if $t < 1 / 2;
	return $p + ( $q - $p ) * ( 2 / 3 - $t ) * 6 if $t < 2 / 3;
	return $p;
}

sub _hsl_to_rgb1 {
	my ( $h, $s, $l ) = @_;
	$h = ( ( $h % 360 ) + 360 ) % 360;
	$h /= 360;
	if ( $s == 0 ) {
		return ( $l, $l, $l );
	}
	my $q = $l < 0.5 ? $l * ( 1 + $s ) : $l + $s - $l * $s;
	my $p = 2 * $l - $q;
	return (
		_hue_to_rgb_ch( $p, $q, $h + 1 / 3 ),
		_hue_to_rgb_ch( $p, $q, $h ),
		_hue_to_rgb_ch( $p, $q, $h - 1 / 3 ),
	);
}

sub _inheritance_lighten_hex {
	my ( $hex, $delta_l ) = @_;
	$delta_l = _INHERIT_LIGHTEN_L() if !defined $delta_l;
	my @rgb = _hex_to_rgb1($hex);
	return $hex unless @rgb == 3;
	my ( $H, $S, $L ) = _rgb_to_hsl(@rgb);
	$L = min( 0.985, $L + $delta_l );
	@rgb = _hsl_to_rgb1( $H, $S, $L );
	return _rgb1_to_hex(@rgb);
}

# Circular mean for hue; arithmetic mean for S and L — analogous to mixing pigments / perceptual mix.
sub _inheritance_blend_hex {
	my (@hexes) = @_;
	my @hsl;
	for my $hx (@hexes) {
		my @rgb = _hex_to_rgb1($hx);
		next unless @rgb == 3;
		push @hsl, [ _rgb_to_hsl(@rgb) ];
	}
	return $hexes[0] if @hsl < 1;
	return _inheritance_lighten_hex( $hexes[0], 0 ) if @hsl < 2;
	my $sx = 0;
	my $sy = 0;
	my $Ssum = 0;
	my $Lsum = 0;
	my $n = 0;
	for my $t (@hsl) {
		my ( $H, $S, $L ) = @$t;
		my $rad = $H * 3.1415926535897931 / 180;
		$sx += cos($rad);
		$sy += sin($rad);
		$Ssum += $S;
		$Lsum += $L;
		$n++;
	}
	my $Hmean = atan2( $sy, $sx ) * 180 / 3.1415926535897931;
	$Hmean += 360 if $Hmean < 0;
	my $Smean = $Ssum / $n;
	my $Lmean = $Lsum / $n;
	my @rgb = _hsl_to_rgb1( $Hmean, $Smean, $Lmean );
	return _rgb1_to_hex(@rgb);
}

sub _inheritance_depth {
	my ( $parents_of, $all_nodes ) = @_;
	my %depth;
	my %vis;
	my $go;
	$go = sub {
		my ($n) = @_;
		return $depth{$n} if exists $depth{$n};
		croak "GraphViz2::DBI: cycle in pg_inherits near $n" if $vis{$n};
		$vis{$n} = 1;
		my $pars = $parents_of->{$n};
		my $d = ( !$pars || !@$pars ) ? 0 : ( max( map { $go->($_) } @$pars ) + 1 );
		delete $vis{$n};
		return $depth{$n} = $d;
	};
	$go->($_) for keys %$all_nodes;
	return \%depth;
}

# Roots: palette. One parent: parent color + one tone lighter. Several parents: blend(parents) + one tone lighter.
sub _inheritance_node_and_edge_colors {
	my ( $parents_of, $all_nodes, $edges ) = @_;
	my %is_child;
	$is_child{ $_->[1] } = 1 for @$edges;
	my @roots = sort grep { !$is_child{$_} } keys %$all_nodes;

	my %root_hex;
	my $i = 0;
	for my $r (@roots) {
		$root_hex{$r} = $INHERITANCE_ROOT_PALETTE[ $i % @INHERITANCE_ROOT_PALETTE ];
		$i++;
	}

	my $depth = _inheritance_depth( $parents_of, $all_nodes );
	my @order = sort { $depth->{$a} <=> $depth->{$b} || $a cmp $b } keys %$all_nodes;

	my %node_border;
	for my $n (@order) {
		my $pars = $parents_of->{$n};
		if ( !$pars || !@$pars ) {
			$node_border{$n} = $root_hex{$n};
		}
		elsif ( @$pars == 1 ) {
			my $ph = $node_border{ $pars->[0] };
			$node_border{$n} = _inheritance_lighten_hex($ph);
		}
		else {
			my @cols = map { $node_border{$_} } @$pars;
			my $mix = _inheritance_blend_hex(@cols);
			$node_border{$n} = _inheritance_lighten_hex($mix);
		}
	}

	return \%node_border;
}

# DBIx::Admin::TableInfo hardcodes schema => 'public' for PostgreSQL (see its dbh2schema()),
# so SET search_path alone does not change table_info(). When $ENV{DBI_SCHEMA} lists schemas,
# merge one TableInfo per schema and use qualified node names schema.table (FK names adjusted).
sub _pg_qualify_table_name {
	my ( $schem, $table, $default_schema ) = @_;
	return $table if !defined $table || $table eq '';
	return $table if $table =~ /\./;
	my $s =
		    ( defined $schem && $schem ne '' )
		? $schem
		: ( defined $default_schema && $default_schema ne '' ? $default_schema : undef );
	return defined $s ? qq{$s.$table} : $table;
}

# Qualified node names schema.table: one saturated border color per schema (readable on #f0f4f8).
sub _schema_prefix_from_table_name {
	my ($name) = @_;
	return '_default' if !defined $name || $name eq '';
	my $dot = index( $name, '.' );
	return $dot < 0 ? '_default' : substr( $name, 0, $dot );
}

sub _schema_border_color_map {
	my ($table_names) = @_;
	my %uniq;
	$uniq{ _schema_prefix_from_table_name($_) } = 1 for @$table_names;
	my @schemas = sort keys %uniq;
	my @palette = (
		'#e11d48', '#2563eb', '#16a34a', '#d97706', '#9333ea',
		'#db2777', '#0d9488', '#ea580c', '#4f46e5', '#ca8a04',
		'#dc2626', '#0284c7', '#65a30d', '#c026d3', '#059669',
		'#be185d', '#1d4ed8', '#15803d', '#a855f7', '#c2410c',
	);
	my %map;
	my $i = 0;
	for my $s (@schemas) {
		$map{$s} = $palette[ $i % @palette ];
		$i++;
	}
	return \%map;
}

sub _trace {
	return unless $ENV{GRAPHVIZ2_DBI_DEBUG} || $_trace_for_create;
	my ( $msg, $t0 ) = @_;
	if ( defined $t0 ) {
		warn sprintf "[GraphViz2::DBI] trace: $msg (%.2fs)\n", time - $t0;
	}
	else {
		warn "[GraphViz2::DBI] trace: $msg\n";
	}
}

sub _merged_table_info {
	my ($self) = @_;
	my $dbh = $self->dbh;
	my $t_all =
		( $ENV{GRAPHVIZ2_DBI_DEBUG} || $_trace_for_create ) ? time : undef;

	if ( ( $dbh->{Driver}{Name} || '' ) ne 'Pg' ) {
		_trace('TableInfo: single pass (non-Pg)');
		my $info = DBIx::Admin::TableInfo->new( dbh => $dbh )->info;
		_trace( 'TableInfo: done', $t_all ) if defined $t_all;
		return $info;
	}

	my $spec = $ENV{DBI_SCHEMA};
	if ( !defined $spec || $spec eq '' ) {
		_trace('TableInfo (Pg): single pass (default schema public)');
		my $info = DBIx::Admin::TableInfo->new( dbh => $dbh )->info;
		_trace( 'TableInfo (Pg): done', $t_all ) if defined $t_all;
		return $info;
	}

	my @schemas = grep { $_ ne '' } split /\s*,\s*/, $spec;
	_trace( 'TableInfo (Pg): merging ' . scalar(@schemas) . ' schema(s) (slow: metadata + FK probes per schema)' );
	my %merged;
	for my $sch (@schemas) {
		my $t_s =
			( $ENV{GRAPHVIZ2_DBI_DEBUG} || $_trace_for_create ) ? time : undef;
		_trace("TableInfo (Pg): schema=$sch ...");
		my $info = DBIx::Admin::TableInfo->new( dbh => $dbh, schema => $sch )->info;
		_trace( 'TableInfo (Pg): schema=' . $sch . ' done (' . ( scalar keys %$info ) . ' tables)', $t_s )
			if defined $t_s;
		for my $t ( keys %$info ) {
			my $q = qq{$sch.$t};
			$merged{$q} = $info->{$t};
			for my $fk ( @{ $merged{$q}{foreign_keys} } ) {
				if ( defined $fk->{UK_TABLE_NAME} ) {
					$fk->{UK_TABLE_NAME} = _pg_qualify_table_name(
						$fk->{UK_TABLE_SCHEM},
						$fk->{UK_TABLE_NAME},
						$sch
					);
				}
				if ( defined $fk->{FK_TABLE_NAME} ) {
					$fk->{FK_TABLE_NAME} = _pg_qualify_table_name(
						$fk->{FK_TABLE_SCHEM},
						$fk->{FK_TABLE_NAME},
						$sch
					);
				}
			}
		}
	}
	_trace( 'TableInfo (Pg): merge complete (' . ( scalar keys %merged ) . ' qualified tables)', $t_all )
		if defined $t_all;
	return \%merged;
}

sub create {
	my ($self, %arg) = @_;
	my $debug = $arg{debug} || $ENV{GRAPHVIZ2_DBI_DEBUG};
	local $_trace_for_create = $debug;
	my $t_create = $debug ? time : undef;
	my $start_info = $self->_merged_table_info;
	_trace( 'create(): metadata ready', $t_create ) if $debug && defined $t_create;
	if ($debug) {
		my $raw_n = scalar keys %$start_info;
		warn "[GraphViz2::DBI] debug: DBIx::Admin::TableInfo table count (before exclude/include) = $raw_n\n";
		if ( ($self->dbh->{Driver}{Name} || '') eq 'Pg' ) {
			my $sp = eval { $self->dbh->selectrow_array('SHOW search_path') };
			warn "[GraphViz2::DBI] debug: PostgreSQL search_path = $sp\n" if defined $sp;
		}
		if ( $raw_n && $raw_n <= 60 ) {
			warn "[GraphViz2::DBI] debug: tables: ", join( q{, }, sort keys %$start_info ), "\n";
		}
		elsif ($raw_n) {
			warn "[GraphViz2::DBI] debug: first 40 tables: ",
				join( q{, }, ( sort keys %$start_info )[ 0 .. 39 ] ), " ...\n";
		}
		else {
			warn "[GraphViz2::DBI] debug: hint: DBIx::Admin::TableInfo uses only schema 'public' unless you set \$ENV{DBI_SCHEMA} to a comma-separated list; "
				. "scripts/dbi.schema.pl sets search_path and passes schemas for merging\n";
		}
	}
	delete @$start_info{ @{ $arg{exclude} || [] } };
	my %info = map +($_=>$$start_info{$_}), @{ $arg{include} || [keys %$start_info] };
	if ($debug) {
		my $n = scalar keys %info;
		warn "[GraphViz2::DBI] debug: tables used for graph (after exclude/include) = $n\n";
	}
	my $t_nodes = $debug ? time : undef;
	_trace( 'create(): adding nodes to Graphviz graph (' . ( scalar keys %info ) . ' tables)' ) if $debug;
	my @sorted_tables = sort keys %info;
	my $border_for = _schema_border_color_map( \@sorted_tables );
	if ($debug) {
		warn "[GraphViz2::DBI] debug: schema border colors: ",
			join( q{, }, map { qq{$_ => $border_for->{$_}} } sort keys %$border_for ), "\n";
	}
	my %port;
	for my $table_name (@sorted_tables) {
		my $port = 0;
		my %thisport = map +($_ => ++$port),
			sort map{s/^"(.+)"$/$1/; $_} keys %{$info{$table_name}{columns} };
		my $sk = _schema_prefix_from_table_name($table_name);
		$self->graph->add_node(
			name     => $table_name,
			color    => $border_for->{$sk},
			penwidth => 1.35,
			label    => [
				{port => 'port0', text => $table_name},
				[ map +{
					port => "port$thisport{$_}",
					text => "$thisport{$_}: $_",
				}, sort keys %thisport ],
			],
		);
		$port{$table_name} = \%thisport;
	}
	_trace( 'create(): nodes added', $t_nodes ) if $debug && defined $t_nodes;
	my $vendor_name = uc $self->dbh->get_info(17);
	my ($temp_1, $temp_2, $temp_3);
	if ($vendor_name eq 'MYSQL') {
		$temp_1 = 'PKTABLE_NAME';
		$temp_2 = 'FKTABLE_NAME';
		$temp_3 = 'FKCOLUMN_NAME';
	} else {
		# ORACLE && POSTGRESQL && SQLITE (at least).
		$temp_1 = 'UK_TABLE_NAME';
		$temp_2 = 'FK_TABLE_NAME';
		$temp_3 = 'FK_COLUMN_NAME';
	}
	my $t_edges = $debug ? time : undef;
	my $edge_count = 0;
	_trace('create(): adding foreign-key edges') if $debug;
	for my $table_name (sort keys %info) {
		for my $item (@{ $info{$table_name}{foreign_keys} }) {
			my $pk_table_name  = $$item{$temp_1};
			my $fk_table_name  = $$item{$temp_2};
			my $fk_column_name = $$item{$temp_3};
			my $source_port    = $fk_column_name ? $port{$fk_table_name}{$fk_column_name} : 2;
			my ($primary_key_name, $destination_port);
			if ($pk_table_name) {
				if (defined($info{$table_name}{columns}{$fk_column_name}) ) {
					$primary_key_name = $fk_column_name;
				} elsif (defined($info{$table_name}{columns}{id}) ) {
					$primary_key_name = 'id';
				} else {
					die "Primary table '$pk_table_name'. Foreign table '$fk_table_name'. Unable to find primary key name for foreign key '$fk_column_name'\n"
				}
				$destination_port = ($primary_key_name eq 'id') ? '0:w' : $port{$table_name}{$primary_key_name};
			} else {
				$destination_port = 2;
			}
			# GraphViz2 escape_port() encodes ":" in a single port string (e.g. "port0:w" -> unusable).
			# For Mrecord + compass on port0, pass [ qw(port0 w) ] so dot gets port:compass correctly.
			my $tailport = "port$source_port";
			my $headport   = ( $pk_table_name && defined $primary_key_name && $primary_key_name eq 'id' )
				? [ 'port0', 'w' ]
				: "port$destination_port";
			$self->graph->add_edge(
				from => $fk_table_name,
				tailport => $tailport,
				to => $table_name,
				headport => $headport,
			);
			$edge_count++;
		}
	}
	_trace( "create(): FK edges added ($edge_count edges)", $t_edges ) if $debug && defined $t_edges;
	_trace( 'create(): finished', $t_create ) if $debug && defined $t_create;
	return $self;
}

sub create_inheritance {
	my ($self, %arg) = @_;
	my $dbh = $self->dbh;
	croak 'create_inheritance requires PostgreSQL (DBI driver must be Pg)'
		if ( $dbh->{Driver}{Name} || '' ) ne 'Pg';

	my $g = $arg{graph} || __PACKAGE__->_new_inheritance_graph;
	$self->inheritance_graph($g);

	my $schemas = $arg{schemas};
	my %schema_ok = ( defined $schemas && ref $schemas eq 'ARRAY' && @$schemas )
		? map { ( $_ => 1 ) } @$schemas
		: ();

	my $sql = q{
		SELECT
			nsp_p.nspname AS parent_nsp,
			cls_p.relname AS parent_tbl,
			nsp_c.nspname AS child_nsp,
			cls_c.relname AS child_tbl
		FROM pg_inherits
		JOIN pg_class cls_p ON cls_p.oid = inhparent
		JOIN pg_class cls_c ON cls_c.oid = inhrelid
		JOIN pg_namespace nsp_p ON nsp_p.oid = cls_p.relnamespace
		JOIN pg_namespace nsp_c ON nsp_c.oid = cls_c.relnamespace
		WHERE cls_p.relkind = 'r' AND cls_c.relkind = 'r'
		ORDER BY 1, 2, 3, 4
	};

	my $sth = $dbh->prepare($sql) or croak $dbh->errstr;
	$sth->execute() or croak $sth->errstr;

	my @edges;
	while ( my $r = $sth->fetchrow_hashref ) {
		if (%schema_ok) {
			next
				unless $schema_ok{ $r->{parent_nsp} }
				|| $schema_ok{ $r->{child_nsp} };
		}
		my $parent = qq{$r->{parent_nsp}.$r->{parent_tbl}};
		my $child  = qq{$r->{child_nsp}.$r->{child_tbl}};
		push @edges, [ $parent, $child ];
	}
	$sth->finish;

	my ( %parents_of, %all_nodes );
	for my $e (@edges) {
		my ( $p, $c ) = @$e;
		$all_nodes{$p} = 1;
		$all_nodes{$c} = 1;
		push @{ $parents_of{$c} }, $p;
	}

	my $node_border = _inheritance_node_and_edge_colors(
		\%parents_of, \%all_nodes, \@edges );

	for my $name ( sort keys %$node_border ) {
		my $b = $node_border->{$name};
		$g->add_node(
			name       => $name,
			label      => $name,
			color      => $b,
			fontcolor  => $b,
			fillcolor  => 'transparent',
			penwidth   => 1.25,
		);
	}

	for my $e (@edges) {
		my ( $parent, $child ) = @$e;
		my $ec = $node_border->{$parent};
		$g->add_edge(
			from  => $parent,
			to    => $child,
			color => $ec,
		);
	}

	return $self;
}

1;

=pod

=head1 NAME

L<GraphViz2::DBI> - Visualize a database schema as a graph

=begin html

[![MetaCPAN package](https://repology.org/badge/version-for-repo/metacpan/perl%3Agraphviz2-dbi.svg)](https://repology.org/project/perl%3Agraphviz2-dbi/versions)
[![CPAN version](https://badge.fury.io/pl/GraphViz2-DBI.svg)](https://metacpan.org/pod/GraphViz2::DBI)
[![CPAN testers](https://cpants.cpanauthors.org/dist/GraphViz2-DBI.svg)](https://cpants.cpanauthors.org/dist/GraphViz2-DBI)
[![License](https://img.shields.io/badge/license-Perl%205-blue.svg)](https://dev.perl.org/licenses/)
[![Perl](https://img.shields.io/badge/perl-5.10%2B-blue.svg)](https://www.perl.org/)
[![CI](https://github.com/neo1ite/GraphViz2-DBI/actions/workflows/ci.yml/badge.svg)](https://github.com/neo1ite/GraphViz2-DBI/actions/workflows/ci.yml)

=end html

=head1 VERSION

This document describes version 2.56 of L<GraphViz2::DBI>. The canonical version is the value of
C<$GraphViz2::DBI::VERSION> in F<lib/GraphViz2/DBI.pm> and the F<Changes> file shipped with this
distribution.

=head1 Synopsis

	use DBI;
	use GraphViz2;
	use GraphViz2::DBI;

	exit 0 if (! $ENV{DBI_DSN});

	my($attr)              = {};
	$$attr{sqlite_unicode} = 1 if ($ENV{DBI_DSN} =~ /SQLite/i);
	my($dbh)               = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS}, $attr);

	$dbh->do('PRAGMA foreign_keys = ON') if ($ENV{DBI_DSN} =~ /SQLite/i);

	# Uses the module default GraphViz2 theme (light background, Mrecord nodes, splines).
	# Pass graph => GraphViz2->new(...) to customize.
	my($g) = GraphViz2::DBI->new(dbh => $dbh);

	$g->create;

	my($format)      = shift || 'svg';
	my($output_file) = shift || File::Spec->catfile('html', "dbi.schema.$format");

	$g->graph->run(format => $format, output_file => $output_file);

See scripts/dbi.schema.pl (L<GraphViz2/Scripts Shipped with this Module>).

The image html/dbi.schema.svg was generated from the database tables of my module
L<App::Office::Contacts>.

=head1 Description

Takes a database handle, and graphs the schema.

You can write the result in any format supported by L<Graphviz|http://www.graphviz.org/>.

Here is the list of L<output formats|http://www.graphviz.org/content/output-formats>.

=head1 Constructor and Initialization

=head2 Calling new()

C<new()> is called as C< my($obj) = GraphViz2::DBI-E<gt>new(k1 =E<gt> v1, k2 =E<gt> v2, ...) >.

It returns a new object of type C<GraphViz2::DBI>.

Key-value pairs accepted in the parameter list:

=over 4

=item C<dbh =E<gt> $dbh>

This options specifies the database handle to use.

This key is mandatory.

=item C<graph =E<gt> $graphviz_object>

This option specifies the GraphViz2 object to use. This allows you to configure it as desired.

The default is a GraphViz2 instance with a light canvas, Mrecord nodes, splines, and per-schema
border colors for qualified PostgreSQL table names (see L</create>).

This key is optional.

=back

=head1 Methods

=head2 C<create(exclude =E<gt> [], include =E<gt> [])>

Creates the graph, which is accessible via the graph() method, or via the graph object you passed to
new().

Table names that look like C<schema.table> (for example after PostgreSQL multi-schema merging) get a
I<border> color per schema: one hue per distinct prefix, from a fixed bright palette that stays
readable on the default light graph background.

Returns $self to allow method chaining.

Parameters:

=over 4

=item C<exclude>

An optional arrayref of table names to exclude.

If none are listed for exclusion, I<all> tables are included.

=item C<include>

An optional arrayref of table names to include.

If none are listed for inclusion, I<all> tables are included.

=item C<debug>

If true, or if the environment variable C<GRAPHVIZ2_DBI_DEBUG> is set, diagnostics are printed to
C<STDERR>: how many tables L<DBIx::Admin::TableInfo> returned, current C<search_path> on
PostgreSQL, table names, and a C<schema =E<gt> #hex> border-color map. Trace lines
(C<[GraphViz2::DBI] trace:>) show phases with elapsed seconds: per-schema C<TableInfo> on PostgreSQL,
adding nodes and FK edges. Use this when the generated graph is empty, too small, or the run seems
to hang (often slow: many schemas, or C<GraphViz2-E<gt>run> / C<dot> on a huge graph).

=back

Environment:

=over 4

=item C<GRAPHVIZ2_DBI_DEBUG>

When set to a true value, same as C<< create(debug => 1) >>.

=back

=head2 C<graph()>

Returns the graph object, either the one supplied to new() or the one created during the call to
new().

=head2 C<create_inheritance(%options)>

Builds a I<second> diagram: PostgreSQL table inheritance (C<INHERITS>), using the catalog view
C<pg_inherits>. It does not replace the foreign-key graph from C<create()>; use the object
L</inheritance_graph> to render or export this graph.

Requires a L<DBI> handle whose driver is C<Pg>. Otherwise it throws an exception.

Returns C<$self> for method chaining.

Parameters:

=over 4

=item C<schemas =E<gt> [ 'crm', 'auth', ... ]>

Optional arrayref of schema names. If present, an inheritance edge is drawn only if the parent
table's schema or the child table's schema is in this list.

=item C<graph =E<gt> $graphviz2>

Optional L<GraphViz2> instance. If omitted, a new graph is built with rank direction left-to-right,
transparent background, rounded nodes with transparent fill: each root gets a distinct palette
color; a table with one parent is colored one step lighter than the parent; with several parents,
border and font colors are the HSL blend of the parent colors (circular mean of hues, mean
saturation and lightness) then one step lighter. Each edge uses the parent table color. Edges have
no text label.

=back

Output (SVG, PNG, etc.) is produced by calling C<< $obj->inheritance_graph->run(...) >> the same
way as for the main schema graph; see L<GraphViz2>.

=head2 C<inheritance_graph()>

Returns the L<GraphViz2> object last populated by L</create_inheritance>, or undef if that method
has not been called successfully.

=head1 FAQ

=head2 Why did I get an error about 'Unable to find primary key'?

For plotting foreign keys, the code has an algorithm to find the primary table/key pair which the
foreign table/key pair point to.

The steps are listed here, in the order they are tested. The first match stops the search.

=over 4

=item Ask the database for foreign key information

L<DBIx::Admin::TableInfo> is used for this.

=item Take a guess

Assume the foreign key points to a table with a column called C<id>, and use that as the primary
key.

=item Die with a detailed error message

=back

=head2 Which versions of the servers did you test?

See L<DBIx::Admin::TableInfo/FAQ>.

=head2 Does GraphViz2::DBI work with SQLite databases?

Yes. See L<DBIx::Admin::TableInfo/FAQ>.

=head2 What is returned by SQLite's "pragma foreign_key_list($table_name)"?

See L<DBIx::Admin::TableInfo/FAQ>.

=head2 How does GraphViz2::DBI draw edges from foreign keys to primary keys?

It uses L<DBIx::Admin::TableInfo>.

=head2 How is table inheritance drawn?

L</create_inheritance> queries C<pg_inherits> (PostgreSQL only) and adds directed edges from each
parent table to child table (no edge label). Node names are C<schema.table>. Colors follow the rules
described in L</create_inheritance>.

=head2 Why is the schema graph empty or almost empty?

For PostgreSQL, L<DBIx::Admin::TableInfo> defaults to schema C<public> only (it does not follow
C<search_path>). Set C<DBI_SCHEMA> to a comma-separated list of schemas (see
F<scripts/dbi.schema.pl>): C<GraphViz2::DBI> merges metadata per schema and uses qualified
table names (C<schema.table>). Set C<GRAPHVIZ2_DBI_DEBUG> to print table counts and
C<search_path>.

=head1 Scripts Shipped with this Module

=head2 scripts/dbi.schema.pl

Requires C<DBI_DSN> (and optionally C<DBI_USER>, C<DBI_PASS>). Builds a I<foreign-key> graph by default
(L</create>), writing C<./html/dbi.schema.svg> (or the format and path you pass as arguments).

For PostgreSQL, set C<DBI_SCHEMA> to a comma-separated list of schemas so metadata and merged table
names match your database (see L</Why is the schema graph empty or almost empty>).

Run with C<--inheritance> to build only the PostgreSQL I<table inheritance> diagram (L</create_inheritance>),
using C<pg_inherits>. Default output is C<./html/dbi.schema.inheritance.svg>. C<--help> prints usage.

Set C<GRAPHVIZ2_DBI_DEBUG> for stderr diagnostics and phase timings.

For background, see L<http://blogs.perl.org/users/ron_savage/2013/03/graphviz2-and-the-dread-musicbrainz-db.html>.

=head2 scripts/sqlite.foreign.keys.pl

Demonstrates how to find foreign key info by calling SQLite's pragma foreign_key_list.

Outputs to STDOUT.

=head1 Thanks

Many thanks to the people who chose to make L<Graphviz|http://www.graphviz.org/> Open Source.

And thanks to L<Leon Brocard|http://search.cpan.org/~lbrocard/>, who wrote L<GraphViz>, and kindly
gave me co-maint of the module.

=head1 Author

L<GraphViz2> was written by Ron Savage I<E<lt>ron@savage.net.auE<gt>> in 2011.

Home page: L<http://savage.net.au/index.html>.

=head1 Copyright

Australian copyright (c) 2011, Ron Savage.

	All Programs of mine are 'OSI Certified Open Source Software';
	you can redistribute them and/or modify them under the terms of
	The Perl License, a copy of which is available at:
	http://dev.perl.org/licenses/

=cut
