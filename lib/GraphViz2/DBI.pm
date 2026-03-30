package GraphViz2::DBI;

use strict;
use warnings;
use warnings  qw(FATAL utf8); # Fatalize encoding glitches.

our $VERSION = '2.53';

use Carp qw(croak);
use DBIx::Admin::TableInfo;
use GraphViz2;
use Moo;

has dbh => (
	is       => 'rw',
	required => 1,
);

has graph => (
	default  => sub {
		GraphViz2->new(
			edge   => {color => 'grey'},
			global => {directed => 1, combine_node_and_port => 0},
			graph  => {rankdir => 'TB'},
			node   => {color => 'blue', shape => 'oval'},
		)
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
	return GraphViz2->new(
		edge   => {color => 'darkgreen', style => 'dashed'},
		global => {directed => 1},
		graph  => {rankdir => 'LR'},
		node   => {color => 'darkblue', shape => 'box'},
	);
}

sub create {
	my ($self, %arg) = @_;
	my $start_info = DBIx::Admin::TableInfo->new(dbh => $self->dbh)->info;
	delete @$start_info{ @{ $arg{exclude} || [] } };
	my %info = map +($_=>$$start_info{$_}), @{ $arg{include} || [keys %$start_info] };
	my %port;
	for my $table_name (sort keys %info) {
		my $port = 0;
		my %thisport = map +($_ => ++$port),
			sort map{s/^"(.+)"$/$1/; $_} keys %{$info{$table_name}{columns} };
		$self->graph->add_node(name => $table_name, label => [
			{port => 'port0', text => $table_name},
			[ map +{
				port => "port$thisport{$_}",
				text => "$thisport{$_}: $_",
			}, sort keys %thisport ],
		]);
		$port{$table_name} = \%thisport;
	}
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
			$self->graph->add_edge(
				from => $fk_table_name,
				tailport => "port$source_port",
				to => $table_name,
				headport => "port$destination_port",
			);
		}
	}
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

	my %seen_node;
	while ( my $r = $sth->fetchrow_hashref ) {
		if (%schema_ok) {
			next
				unless $schema_ok{ $r->{parent_nsp} }
				|| $schema_ok{ $r->{child_nsp} };
		}
		my $parent = qq{$r->{parent_nsp}.$r->{parent_tbl}};
		my $child  = qq{$r->{child_nsp}.$r->{child_tbl}};
		for my $n ( $parent, $child ) {
			next if $seen_node{$n}++;
			$g->add_node( name => $n, label => $n );
		}
		$g->add_edge(
			from  => $parent,
			to    => $child,
			label => 'inherits',
		);
	}
	$sth->finish;
	return $self;
}

1;

=pod

=head1 NAME

L<GraphViz2::DBI> - Visualize a database schema as a graph

=head1 Synopsis

	use DBI;
	use GraphViz2;
	use GraphViz2::DBI;

	exit 0 if (! $ENV{DBI_DSN});

	my($graph) = GraphViz2->new (
		edge   => {color => 'grey'},
		global => {directed => 1},
		graph  => {rankdir => 'TB'},
		node   => {color => 'blue', shape => 'oval'},
	);
	my($attr)              = {};
	$$attr{sqlite_unicode} = 1 if ($ENV{DBI_DSN} =~ /SQLite/i);
	my($dbh)               = DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS}, $attr);

	$dbh->do('PRAGMA foreign_keys = ON') if ($ENV{DBI_DSN} =~ /SQLite/i);

	my($g) = GraphViz2::DBI->new(dbh => $dbh, graph => $graph);

	$g->create;

	my($format)      = shift || 'svg';
	my($output_file) = shift || File::Spec->catfile('html', "dbi.schema.$format");

	$graph->run(format => $format, output_file => $output_file);

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

The default is GraphViz2->new. The default attributes are the same as in the synopsis, above,
except for the graph label of course.

This key is optional.

=back

=head1 Methods

=head2 C<create(exclude =E<gt> [], include =E<gt> [])>

Creates the graph, which is accessible via the graph() method, or via the graph object you passed to
new().

Returns $self to allow method chaining.

Parameters:

=over 4

=item C<exclude>

An optional arrayref of table names to exclude.

If none are listed for exclusion, I<all> tables are included.

=item C<include>

An optional arrayref of table names to include.

If none are listed for inclusion, I<all> tables are included.

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

=item C<schemas =E<gt> [ 'crm', 'gms', ... ]>

Optional arrayref of schema names. If present, an inheritance edge is drawn only if the parent
table's schema or the child table's schema is in this list.

=item C<graph =E<gt> $graphviz2>

Optional L<GraphViz2> instance. If omitted, a new graph is built with rank direction left-to-right,
dashed green edges, and boxed nodes (distinct from the default C<graph()> styling).

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

L</create_inheritance> queries C<pg_inherits> (PostgreSQL only) and adds edges labeled
C<inherits> from parent table to child table. Node names are C<schema.table>.

=head1 Scripts Shipped with this Module

=head2 scripts/dbi.schema.pl

If the environment vaiables DBI_DSN, DBI_USER and DBI_PASS are set (the latter 2 are optional [e.g. for SQLite]),
then this demonstrates building a graph from a database schema.

Also, for Postgres, you can set $ENV{DBI_SCHEMA} to a comma-separated list of schemas, e.g. when processing the
MusicBrainz database. See scripts/dbi.schema.pl.

For details, see L<http://blogs.perl.org/users/ron_savage/2013/03/graphviz2-and-the-dread-musicbrainz-db.html>.

Outputs to ./html/dbi.schema.svg by default.

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
