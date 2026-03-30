# NAME

[GraphViz2::DBI](https://metacpan.org/pod/GraphViz2%3A%3ADBI) - Visualize a database schema as a graph

# Synopsis

```perl
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

    The default is GraphViz2->new. The default attributes are the same as in the synopsis, above,
    except for the graph label of course.

    This key is optional.

# Methods

## `create(exclude => [], include => [])`

Creates the graph, which is accessible via the graph() method, or via the graph object you passed to
new().

Returns $self to allow method chaining.

Parameters:

- `exclude`

    An optional arrayref of table names to exclude.

    If none are listed for exclusion, _all_ tables are included.

- `include`

    An optional arrayref of table names to include.

    If none are listed for inclusion, _all_ tables are included.

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

- `schemas => [ 'crm', 'gms', ... ]`

    Optional arrayref of schema names. If present, an inheritance edge is drawn only if the parent
    table's schema or the child table's schema is in this list.

- `graph => $graphviz2`

    Optional [GraphViz2](https://metacpan.org/pod/GraphViz2) instance. If omitted, a new graph is built with rank direction left-to-right,
    dashed green edges, and boxed nodes (distinct from the default `graph()` styling).

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

["create\_inheritance"](#create_inheritance) queries `pg_inherits` (PostgreSQL only) and adds edges labeled
`inherits` from parent table to child table. Node names are `schema.table`.

# Scripts Shipped with this Module

## scripts/dbi.schema.pl

If the environment vaiables DBI\_DSN, DBI\_USER and DBI\_PASS are set (the latter 2 are optional \[e.g. for SQLite\]),
then this demonstrates building a graph from a database schema.

Also, for Postgres, you can set $ENV{DBI\_SCHEMA} to a comma-separated list of schemas, e.g. when processing the
MusicBrainz database. See scripts/dbi.schema.pl.

For details, see [http://blogs.perl.org/users/ron\_savage/2013/03/graphviz2-and-the-dread-musicbrainz-db.html](http://blogs.perl.org/users/ron_savage/2013/03/graphviz2-and-the-dread-musicbrainz-db.html).

Outputs to ./html/dbi.schema.svg by default.

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
