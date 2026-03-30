use strict;
use warnings;
use Test::More;
use GraphViz2;
use GraphViz2::DBI;

BEGIN {
	package MockPgSth;

	sub execute {
		$_[0]{idx} = 0;
		1;
	}

	sub fetchrow_hashref {
		my $s = shift;
		my $r = $s->{dbh}{rows}[ $s->{idx}++ ];
		return $r;
	}

	sub finish { 1 }

	package MockPgDbh;

	sub new {
		my ( $class, $rows ) = @_;
		bless {
			Driver => { Name => 'Pg' },
			rows   => $rows || [],
		}, $class;
	}

	sub prepare {
		my ( $self, $sql ) = @_;
		bless { dbh => $self, idx => 0, sql => $sql }, 'MockPgSth';
	}

	sub errstr { undef }
}

subtest 'non-PostgreSQL dies' => sub {
	my $dbh = bless { Driver => { Name => 'SQLite' } }, 'MockNonPg';
	my $o   = GraphViz2::DBI->new( dbh => $dbh );
	eval { $o->create_inheritance };
	like $@, qr/create_inheritance requires PostgreSQL/, 'non-Pg rejected';
};

subtest 'PostgreSQL inheritance graph' => sub {
	my $rows = [
		{   parent_nsp  => 'crm',
			parent_tbl  => 'person_thing',
			child_nsp   => 'crm',
			child_tbl   => 'person_contact',
		},
		{   parent_nsp  => 'gms',
			parent_tbl  => 'grant_contest_thing',
			child_nsp   => 'gms',
			child_tbl   => 'grant_contest',
		},
	];
	my $dbh = MockPgDbh->new($rows);
	my $o   = GraphViz2::DBI->new( dbh => $dbh );
	$o->create_inheritance;
	my $g = $o->inheritance_graph;
	ok $g, 'inheritance_graph set';
	is_deeply $g->node_hash,
	  {   'crm.person_thing' => {
				attributes => { label => 'crm.person_thing' },
			},
		  'crm.person_contact' => {
				attributes => { label => 'crm.person_contact' },
			},
		  'gms.grant_contest_thing' => {
				attributes => { label => 'gms.grant_contest_thing' },
			},
		  'gms.grant_contest' => {
				attributes => { label => 'gms.grant_contest' },
			},
	  },
	  'nodes';
	is_deeply $g->edge_hash,
	  {   'crm.person_thing' => {
				'crm.person_contact' => [
					{   attributes => { label => 'inherits' },
						from_port  => '',
						to_port    => '',
					},
				],
			},
		  'gms.grant_contest_thing' => {
				'gms.grant_contest' => [
					{   attributes => { label => 'inherits' },
						from_port  => '',
						to_port    => '',
					},
				],
			},
	  },
	  'edges';
};

subtest 'schemas filter' => sub {
	my $rows = [
		{   parent_nsp => 'public',
			parent_tbl   => 'a',
			child_nsp    => 'crm',
			child_tbl    => 'b',
		},
		{   parent_nsp => 'orm',
			parent_tbl   => '_traceable',
			child_nsp    => 'gms',
			child_tbl    => 'event',
		},
	];
	my $dbh = MockPgDbh->new($rows);
	my $o   = GraphViz2::DBI->new( dbh => $dbh );
	$o->create_inheritance( schemas => [qw(crm)] );
	my $g = $o->inheritance_graph;
	is scalar keys %{ $g->node_hash }, 2, 'only crm edge (public.a -> crm.b)';
	ok $g->node_hash->{'public.a'}, 'public parent kept';
	ok $g->node_hash->{'crm.b'},    'crm child kept';
	ok !$g->node_hash->{'orm._traceable'}, 'orm filtered out';
};

subtest 'custom inheritance GraphViz2' => sub {
	my $custom = GraphViz2->new( global => { directed => 1 } );
	my $rows   = [
		{   parent_nsp => 'x', parent_tbl => 'p',
			child_nsp  => 'x', child_tbl  => 'c',
		},
	];
	my $dbh = MockPgDbh->new($rows);
	my $o   = GraphViz2::DBI->new( dbh => $dbh );
	$o->create_inheritance( graph => $custom );
	is $o->inheritance_graph, $custom, 'same object stored';
};

done_testing;
