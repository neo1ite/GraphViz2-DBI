use strict;
use warnings;
use Test::More;

use GraphViz2;
use GraphViz2::DBI;
use DBI;

my $dbh = DBI->connect( "dbi:SQLite:dbname=:memory:", '', '' );
$dbh->do($_) for <<'EOF', <<'EOF', <<'EOF';
CREATE TABLE "user" (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username VARCHAR(255) UNIQUE NOT NULL,
  email VARCHAR(255) NOT NULL,
  password VARCHAR(255) NOT NULL,
  access TEXT NOT NULL CHECK( access IN ( 'user', 'moderator', 'admin' ) ) DEFAULT 'user',
  age INTEGER DEFAULT NULL,
  plugin VARCHAR(50) NOT NULL DEFAULT 'password',
  avatar VARCHAR(255) NOT NULL DEFAULT '',
  created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)
EOF
CREATE TABLE blog (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username VARCHAR(255) REFERENCES "user" ( username ),
  title VARCHAR(255) NOT NULL,
  slug VARCHAR(255),
  markdown VARCHAR(255) NOT NULL,
  html VARCHAR(255),
  is_published BOOLEAN NOT NULL DEFAULT FALSE,
  published_date DATETIME DEFAULT CURRENT_TIMESTAMP
)
EOF
CREATE TABLE zap (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title VARCHAR(255) NOT NULL
)
EOF

my $g_dbi = GraphViz2::DBI->new( dbh => $dbh );
$g_dbi->create( exclude => ['zap'] );
my $g = $g_dbi->graph;

for my $t (qw(blog user)) {
	ok $g->node_hash->{$t}, "node $t present";
	my $a = $g->node_hash->{$t}{attributes};
	is $a->{shape}, 'Mrecord', "shape $t";
	like $a->{label}, qr/\Q<port0> $t\E/, "label $t";
	like $a->{color}, qr/^#[0-9a-f]{6}\z/i, "per-schema border color $t";
	ok $a->{penwidth}, "penwidth $t";
}

is_deeply(
	$g->edge_hash,
	{   blog => {
			user => [ { attributes => {}, from_port => ':"port8"', to_port => ':"port9"' } ],
		},
	},
	'edges',
);

{
	my @warn;
	local $SIG{__WARN__} = sub { push @warn, $_[0] };
	my $g2 = GraphViz2::DBI->new( dbh => $dbh );
	$g2->create(
		exclude => ['zap'],
		include => [qw(blog user)],
		debug   => 1,
	);
	ok( grep { /tables used for graph/ } @warn, 'create(debug=>1) stderr' );
	ok( grep { /trace:/ } @warn, 'create(debug=>1) trace lines' );
}

done_testing;
