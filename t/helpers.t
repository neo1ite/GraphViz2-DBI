use strict;
use warnings;
use Test::More;
use GraphViz2::DBI;

# Direct tests for private helpers (statement / branch coverage).
# Call as GraphViz2::DBI::_name(...) — not $pkg->_name(...) or the invocant shifts args.

subtest '_hex_to_rgb1' => sub {
	is_deeply [ GraphViz2::DBI::_hex_to_rgb1('#ff0000') ], [ 1, 0, 0 ], 'with hash';
	is_deeply [ GraphViz2::DBI::_hex_to_rgb1('00ff00') ], [ 0, 1, 0 ], 'without hash';
	ok !defined( scalar GraphViz2::DBI::_hex_to_rgb1(undef) ), 'undef';
	ok !defined( scalar GraphViz2::DBI::_hex_to_rgb1('') ), 'empty';
	ok !defined( scalar GraphViz2::DBI::_hex_to_rgb1('nope') ), 'invalid';
};

subtest '_rgb1_to_hex' => sub {
	is GraphViz2::DBI::_rgb1_to_hex( 1, 0, 0 ), '#ff0000', 'red';
	like GraphViz2::DBI::_rgb1_to_hex( -0.5, 2, 0.5 ), qr/^#[0-9a-f]{6}\z/i, 'clamped to 0..1';
};

subtest '_rgb_to_hsl achromatic and primaries' => sub {
	my @g = GraphViz2::DBI::_rgb_to_hsl( 0.5, 0.5, 0.5 );
	cmp_ok $g[1], '==', 0, 'gray S=0';
	my @r = GraphViz2::DBI::_rgb_to_hsl( 1, 0, 0 );
	cmp_ok $r[1], '>', 0, 'red S>0';
	cmp_ok $r[0], '==', 0, 'red H is 0°';
	my @gr = GraphViz2::DBI::_rgb_to_hsl( 0, 1, 0 );
	cmp_ok $gr[0], '>', 0, 'green H';
	my @b = GraphViz2::DBI::_rgb_to_hsl( 0, 0, 1 );
	cmp_ok $b[0], '>', 0, 'blue H';
};

subtest '_hsl_to_rgb1' => sub {
	my @g = GraphViz2::DBI::_hsl_to_rgb1( 120, 0, 0.4 );
	ok( ( $g[0] - $g[1] ) < 0.001 && ( $g[1] - $g[2] ) < 0.001, 'S=0 gray' );
	my @w = GraphViz2::DBI::_hsl_to_rgb1( -30, 0.5, 0.5 );
	ok( $w[0] >= 0 && $w[0] <= 1, 'negative hue wraps' );
};

subtest '_hue_to_rgb_ch branches' => sub {
	# Piecewise segments (t normalized inside the sub):
	ok defined( scalar GraphViz2::DBI::_hue_to_rgb_ch( 0, 1, 0.05 ) ),  't < 1/6';
	ok defined( scalar GraphViz2::DBI::_hue_to_rgb_ch( 0, 1, 0.25 ) ), '1/6 <= t < 1/2';
	ok defined( scalar GraphViz2::DBI::_hue_to_rgb_ch( 0, 1, 0.55 ) ), '1/2 <= t < 2/3';
	ok defined( scalar GraphViz2::DBI::_hue_to_rgb_ch( 0, 1, 0.85 ) ), 't >= 2/3';
	ok defined( scalar GraphViz2::DBI::_hue_to_rgb_ch( 0, 1, -0.2 ) ), 't<0 wraps';
	ok defined( scalar GraphViz2::DBI::_hue_to_rgb_ch( 0, 1, 1.2 ) ),  't>1 wraps';
};

subtest '_inheritance_lighten_hex' => sub {
	my $x = GraphViz2::DBI::_inheritance_lighten_hex('#000000');
	like $x, qr/^#[0-9a-f]{6}\z/i, 'lighten black';
	is GraphViz2::DBI::_inheritance_lighten_hex( 'bad', 0.1 ), 'bad', 'invalid hex passthrough';
};

subtest '_inheritance_blend_hex' => sub {
	is GraphViz2::DBI::_inheritance_blend_hex(), undef, 'no args';
	is GraphViz2::DBI::_inheritance_blend_hex('bad'), 'bad', 'single invalid -> first';
	my $one = GraphViz2::DBI::_inheritance_blend_hex('#ff0000');
	like $one, qr/^#[0-9a-f]{6}\z/i, 'single valid -> lighten clone';
	my $two = GraphViz2::DBI::_inheritance_blend_hex( '#ff0000', '#0000ff' );
	like $two, qr/^#[0-9a-f]{6}\z/i, 'two parents blend';
};

subtest '_pg_qualify_table_name' => sub {
	is GraphViz2::DBI::_pg_qualify_table_name( undef, 't', 'public' ), 'public.t',
		'undef schema uses default_schema';
	is GraphViz2::DBI::_pg_qualify_table_name( 's', '', 'public' ), '', 'empty table';
	is GraphViz2::DBI::_pg_qualify_table_name( 's', 'a.b', 'x' ), 'a.b', 'already qualified';
	is GraphViz2::DBI::_pg_qualify_table_name( 'crm', 'tbl', 'public' ), 'crm.tbl', 'schema + table';
	is GraphViz2::DBI::_pg_qualify_table_name( undef, 'tbl', 'app' ), 'app.tbl', 'default_schema';
	is GraphViz2::DBI::_pg_qualify_table_name( undef, 'tbl', '' ), 'tbl', 'no schema fallback';
};

subtest '_schema_prefix_from_table_name' => sub {
	is GraphViz2::DBI::_schema_prefix_from_table_name(undef), '_default', 'undef';
	is GraphViz2::DBI::_schema_prefix_from_table_name(''), '_default', 'empty';
	is GraphViz2::DBI::_schema_prefix_from_table_name('blog'), '_default', 'unqualified';
	is GraphViz2::DBI::_schema_prefix_from_table_name('crm.person'), 'crm', 'qualified';
};

subtest '_schema_border_color_map' => sub {
	my $m = GraphViz2::DBI::_schema_border_color_map( [qw(foo.bar baz.qux foo.other)] );
	is scalar keys %$m, 2, 'two schema keys';
	ok $m->{foo}, 'foo';
	ok $m->{baz}, 'baz';
};

subtest '_inheritance_depth' => sub {
	my $d1 = GraphViz2::DBI::_inheritance_depth(
		{ c => ['p'], p => [] },
		{ map { $_ => 1 } qw(p c) },
	);
	is $d1->{p}, 0, 'root depth 0';
	is $d1->{c}, 1, 'child depth 1';

	my $err;
	eval {
		GraphViz2::DBI::_inheritance_depth(
			{ a => ['b'], b => ['a'] },
			{ a => 1, b => 1 },
		);
		1;
	} or $err = $@;
	like $err, qr/cycle in pg_inherits/, 'cycle croaks';
};

subtest '_trace' => sub {
	local $ENV{GRAPHVIZ2_DBI_DEBUG};
	delete $ENV{GRAPHVIZ2_DBI_DEBUG};
	my @w;
	local $SIG{__WARN__} = sub { push @w, $_[0] };
	GraphViz2::DBI::_trace('silent');
	is scalar @w, 0, 'no env: no warn';

	$ENV{GRAPHVIZ2_DBI_DEBUG} = 1;
	GraphViz2::DBI::_trace('hello');
	GraphViz2::DBI::_trace( 'timed', time );
	ok( grep { /\[GraphViz2::DBI\] trace: hello/ } @w, 'plain message' );
	ok( grep { /\[GraphViz2::DBI\] trace: timed \(\d+\.\d+s\)/ } @w, 'timed message' );
};

done_testing;
