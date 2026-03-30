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
	ok !$o->has_inheritance_graph, 'predicate before create_inheritance';
	eval { $o->create_inheritance };
	like $@, qr/create_inheritance requires PostgreSQL/, 'non-Pg rejected';
};

subtest 'has_inheritance_graph after success' => sub {
	my $dbh = MockPgDbh->new(
		[ { parent_nsp => 's', parent_tbl => 'p', child_nsp => 's', child_tbl => 'c' } ] );
	my $o = GraphViz2::DBI->new( dbh => $dbh );
	ok !$o->has_inheritance_graph, 'predicate false before';
	$o->create_inheritance;
	ok $o->has_inheritance_graph, 'predicate true after';
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
	for my $n (
		qw(
		  crm.person_thing crm.person_contact
		  gms.grant_contest_thing gms.grant_contest
		  )
	  )
	{
		ok $g->node_hash->{$n}, "node $n";
		my $a = $g->node_hash->{$n}{attributes};
		is $a->{label}, $n, "label $n";
		like $a->{color}, qr/^#[0-9a-f]{6}\z/i, "border $n";
		is $a->{fontcolor}, $a->{color}, "fontcolor = border $n";
		is $a->{fillcolor}, 'transparent', "fillcolor $n";
	}
	my $e1 = $g->edge_hash->{'crm.person_thing'}{'crm.person_contact'}[0]{attributes};
	ok $e1, 'edge crm.person_thing -> crm.person_contact';
	ok !defined $e1->{label} || $e1->{label} eq '', 'no inherits label (crm)';
	is $e1->{color}, $g->node_hash->{'crm.person_thing'}{attributes}{color}, 'edge color = parent';
	my $e2 = $g->edge_hash->{'gms.grant_contest_thing'}{'gms.grant_contest'}[0]{attributes};
	ok $e2, 'edge gms grant_contest';
	ok !defined $e2->{label} || $e2->{label} eq '', 'no inherits label (gms)';
	is $e2->{color}, $g->node_hash->{'gms.grant_contest_thing'}{attributes}{color},
		'edge color = parent (gms)';
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

subtest 'multi-parent child color is blend, not equal to either parent' => sub {
	my $rows = [
		{   parent_nsp => 's', parent_tbl => 'a',
			child_nsp  => 's', child_tbl  => 'c',
		},
		{   parent_nsp => 's', parent_tbl => 'b',
			child_nsp  => 's', child_tbl  => 'c',
		},
	];
	my $dbh = MockPgDbh->new($rows);
	my $o   = GraphViz2::DBI->new( dbh => $dbh );
	$o->create_inheritance;
	my $g = $o->inheritance_graph;
	for my $n (qw(s.a s.b s.c)) {
		ok $g->node_hash->{$n}, "node $n";
		is $g->node_hash->{$n}{attributes}{fillcolor}, 'transparent', "transparent fill $n";
	}
	my $ca = $g->node_hash->{'s.a'}{attributes}{color};
	my $cb = $g->node_hash->{'s.b'}{attributes}{color};
	my $cc = $g->node_hash->{'s.c'}{attributes}{color};
	isnt $cc, $ca, 'child border differs from parent a';
	isnt $cc, $cb, 'child border differs from parent b';
};

done_testing;
