# NAME

[GraphViz2::DBI](https://metacpan.org/pod/GraphViz2%3A%3ADBI) - Visualize a database schema as a graph

[![MetaCPAN package](https://repology.org/badge/version-for-repo/metacpan/perl%3Agraphviz2-dbi.svg)](https://repology.org/project/perl%3Agraphviz2-dbi/versions)
[![CPAN version](https://badge.fury.io/pl/GraphViz2-DBI.svg)](https://metacpan.org/pod/GraphViz2::DBI)
[![CPAN testers](https://cpants.cpanauthors.org/dist/GraphViz2-DBI.svg)](https://cpants.cpanauthors.org/dist/GraphViz2-DBI)
[![License](https://img.shields.io/badge/license-Perl%205-blue.svg)](https://dev.perl.org/licenses/)
[![Perl](https://img.shields.io/badge/perl-5.10%2B-blue.svg)](https://www.perl.org/)
[![CI](https://github.com/neo1ite/GraphViz2-DBI/actions/workflows/ci.yml/badge.svg)](https://github.com/neo1ite/GraphViz2-DBI/actions/workflows/ci.yml)

# VERSION

This document describes version 2.56 of [GraphViz2::DBI](https://metacpan.org/pod/GraphViz2%3A%3ADBI). The canonical version is the value of
`$GraphViz2::DBI::VERSION` in `lib/GraphViz2/DBI.pm` and the `Changes` file shipped with this
distribution.

# Synopsis

```perl
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
```

See scripts/dbi.schema.pl (["Scripts Shipped with this Module" in GraphViz2](https://metacpan.org/pod/GraphViz2#Scripts-Shipped-with-this-Module)).

The image html/dbi.schema.svg was generated from the database tables of my module
[App::Office::Contacts](https://metacpan.org/pod/App%3A%3AOffice%3A%3AContacts).

# Description

Takes a database handle, and graphs the schema.

You can write the result in any format supported by [Graphviz](http://www.graphviz.org/).

Here is the list of [output formats](http://www.graphviz.org/content/output-formats).

# Constructor and Initialization

## Calling new()

`new()` is called as ` my($obj) = GraphViz2::DBI->new(k1 => v1, k2 => v2, ...) `.

It returns a new object of type `GraphViz2::DBI`.

Key-value pairs accepted in the parameter list:

- `dbh => $dbh`

    This options specifies the database handle to use.

    This key is mandatory.

- `graph => $graphviz_object`

    This option specifies the GraphViz2 object to use. This allows you to configure it as desired.

    The default is a GraphViz2 instance with a light canvas, Mrecord nodes, splines, and per-schema
    border colors for qualified PostgreSQL table names (see ["create"](#create)).

    This key is optional.

# Methods

## `create(exclude => [], include => [])`

Creates the graph, which is accessible via the graph() method, or via the graph object you passed to
new().

Table names that look like `schema.table` (for example after PostgreSQL multi-schema merging) get a
_border_ color per schema: one hue per distinct prefix, from a fixed bright palette that stays
readable on the default light graph background.

Returns $self to allow method chaining.

Parameters:

- `exclude`

    An optional arrayref of table names to exclude.

    If none are listed for exclusion, _all_ tables are included.

- `include`

    An optional arrayref of table names to include.

    If none are listed for inclusion, _all_ tables are included.

- `debug`

    If true, or if the environment variable `GRAPHVIZ2_DBI_DEBUG` is set, diagnostics are printed to
    `STDERR`: how many tables [DBIx::Admin::TableInfo](https://metacpan.org/pod/DBIx%3A%3AAdmin%3A%3ATableInfo) returned, current `search_path` on
    PostgreSQL, table names, and a `schema => #hex` border-color map. Trace lines
    (`[GraphViz2::DBI] trace:`) show phases with elapsed seconds: per-schema `TableInfo` on PostgreSQL,
    adding nodes and FK edges. Use this when the generated graph is empty, too small, or the run seems
    to hang (often slow: many schemas, or `GraphViz2->run` / `dot` on a huge graph).

Environment:

- `GRAPHVIZ2_DBI_DEBUG`

    When set to a true value, same as `create(debug => 1)`.

## `graph()`

Returns the graph object, either the one supplied to new() or the one created during the call to
new().

## `create_inheritance(%options)`

Builds a _second_ diagram: PostgreSQL table inheritance (`INHERITS`), using the catalog view
`pg_inherits`. It does not replace the foreign-key graph from `create()`; use the object
["inheritance\_graph"](#inheritance_graph) to render or export this graph.

Requires a [DBI](https://metacpan.org/pod/DBI) handle whose driver is `Pg`. Otherwise it throws an exception.

Returns `$self` for method chaining.

Parameters:

- `schemas => [ 'crm', 'auth', ... ]`

    Optional arrayref of schema names. If present, an inheritance edge is drawn only if the parent
    table's schema or the child table's schema is in this list.

- `graph => $graphviz2`

    Optional [GraphViz2](https://metacpan.org/pod/GraphViz2) instance. If omitted, a new graph is built with rank direction left-to-right,
    transparent background, rounded nodes with transparent fill: each root gets a distinct palette
    color; a table with one parent is colored one step lighter than the parent; with several parents,
    border and font colors are the HSL blend of the parent colors (circular mean of hues, mean
    saturation and lightness) then one step lighter. Each edge uses the parent table color. Edges have
    no text label.

Output (SVG, PNG, etc.) is produced by calling `$obj->inheritance_graph->run(...)` the same
way as for the main schema graph; see [GraphViz2](https://metacpan.org/pod/GraphViz2).

## `inheritance_graph()`

Returns the [GraphViz2](https://metacpan.org/pod/GraphViz2) object last populated by ["create\_inheritance"](#create_inheritance), or undef if that method
has not been called successfully.

# FAQ

## Why did I get an error about 'Unable to find primary key'?

For plotting foreign keys, the code has an algorithm to find the primary table/key pair which the
foreign table/key pair point to.

The steps are listed here, in the order they are tested. The first match stops the search.

- Ask the database for foreign key information

    [DBIx::Admin::TableInfo](https://metacpan.org/pod/DBIx%3A%3AAdmin%3A%3ATableInfo) is used for this.

- Take a guess

    Assume the foreign key points to a table with a column called `id`, and use that as the primary
    key.

- Die with a detailed error message

## Which versions of the servers did you test?

See ["FAQ" in DBIx::Admin::TableInfo](https://metacpan.org/pod/DBIx%3A%3AAdmin%3A%3ATableInfo#FAQ).

## Does GraphViz2::DBI work with SQLite databases?

Yes. See ["FAQ" in DBIx::Admin::TableInfo](https://metacpan.org/pod/DBIx%3A%3AAdmin%3A%3ATableInfo#FAQ).

## What is returned by SQLite's "pragma foreign\_key\_list($table\_name)"?

See ["FAQ" in DBIx::Admin::TableInfo](https://metacpan.org/pod/DBIx%3A%3AAdmin%3A%3ATableInfo#FAQ).

## How does GraphViz2::DBI draw edges from foreign keys to primary keys?

It uses [DBIx::Admin::TableInfo](https://metacpan.org/pod/DBIx%3A%3AAdmin%3A%3ATableInfo).

## How is table inheritance drawn?

["create\_inheritance"](#create_inheritance) queries `pg_inherits` (PostgreSQL only) and adds directed edges from each
parent table to child table (no edge label). Node names are `schema.table`. Colors follow the rules
described in ["create\_inheritance"](#create_inheritance).

## Why is the schema graph empty or almost empty?

For PostgreSQL, [DBIx::Admin::TableInfo](https://metacpan.org/pod/DBIx%3A%3AAdmin%3A%3ATableInfo) defaults to schema `public` only (it does not follow
`search_path`). Set `DBI_SCHEMA` to a comma-separated list of schemas (see
`scripts/dbi.schema.pl`): `GraphViz2::DBI` merges metadata per schema and uses qualified
table names (`schema.table`). Set `GRAPHVIZ2_DBI_DEBUG` to print table counts and
`search_path`.

# Scripts Shipped with this Module

## scripts/dbi.schema.pl

Requires `DBI_DSN` (and optionally `DBI_USER`, `DBI_PASS`). Builds a _foreign-key_ graph by default
(["create"](#create)), writing `./html/dbi.schema.svg` (or the format and path you pass as arguments).

For PostgreSQL, set `DBI_SCHEMA` to a comma-separated list of schemas so metadata and merged table
names match your database (see ["Why is the schema graph empty or almost empty"](#why-is-the-schema-graph-empty-or-almost-empty)).

Run with `--inheritance` to build only the PostgreSQL _table inheritance_ diagram (["create\_inheritance"](#create_inheritance)),
using `pg_inherits`. Default output is `./html/dbi.schema.inheritance.svg`. `--help` prints usage.

Set `GRAPHVIZ2_DBI_DEBUG` for stderr diagnostics and phase timings.

For background, see [http://blogs.perl.org/users/ron\_savage/2013/03/graphviz2-and-the-dread-musicbrainz-db.html](http://blogs.perl.org/users/ron_savage/2013/03/graphviz2-and-the-dread-musicbrainz-db.html).

## scripts/sqlite.foreign.keys.pl

Demonstrates how to find foreign key info by calling SQLite's pragma foreign\_key\_list.

Outputs to STDOUT.

# Thanks

Many thanks to the people who chose to make [Graphviz](http://www.graphviz.org/) Open Source.

And thanks to [Leon Brocard](http://search.cpan.org/~lbrocard/), who wrote [GraphViz](https://metacpan.org/pod/GraphViz), and kindly
gave me co-maint of the module.

# Author

[GraphViz2](https://metacpan.org/pod/GraphViz2) was written by Ron Savage _<ron@savage.net.au>_ in 2011.

Home page: [http://savage.net.au/index.html](http://savage.net.au/index.html).

# Copyright

Australian copyright (c) 2011, Ron Savage.

```
    All Programs of mine are 'OSI Certified Open Source Software';
    you can redistribute them and/or modify them under the terms of
    The Perl License, a copy of which is available at:
    http://dev.perl.org/licenses/
```
