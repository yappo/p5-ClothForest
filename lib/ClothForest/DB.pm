package ClothForest::DB;
use strict;
use warnings;
use DBI;
use Path::Class;
use Time::Piece;

sub new {
    my($class, $data_dir) = @_;
    bless {
        data_dir => $data_dir,
    }, $class;
}

sub db_path {
    my $self = shift;
    return Path::Class::file(
        $self->{data_dir},
        'clothforest.db',
    )->cleanup;
}

sub connection {
    my $self = shift;
    my $db_path = $self->db_path;

    my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_path","","",
                            { RaiseError => 1, AutoCommit => 1 } );
    $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS graphs (
    service_name VARCHAR(255) NOT NULL,
    section_name VARCHAR(255) NOT NULL,
    graph_name   VARCHAR(255) NOT NULL,
    description  VARCHAR(255) NOT NULL,
    number       INT NOT NULL DEFAULT 0,
    sort         INT NOT NULL DEFAULT 0,
    created_at   UNSIGNED INT NOT NULL,
    updated_at   UNSIGNED INT NOT NULL,
    PRIMARY KEY  (service_name, section_name, graph_name)
);
EOF

    $dbh->do(<<EOF);
CREATE INDEX IF NOT EXISTS section_created_at ON graphs ( service_name, section_name, created_at )
EOF
    $dbh->do(<<EOF);
CREATE INDEX IF NOT EXISTS graph_created_at ON graphs ( service_name, section_name, graph_name, created_at )
EOF

    $dbh->do(<<EOF);
CREATE INDEX IF NOT EXISTS section_sort ON graphs ( service_name, section_name, sort )
EOF
    $dbh->do(<<EOF);
CREATE INDEX IF NOT EXISTS graph_sort ON graphs ( service_name, section_name, graph_name, sort )
EOF

    $dbh;
}

sub get {
    my($self, $service, $section, $graph) = @_;

    my $dbh = $self->connection;

    my $rows = $dbh->selectall_arrayref(
        q{SELECT number, created_at, updated_at FROM graphs WHERE service_name=? AND section_name=? AND graph_name=?},
        {Slice => []}, $service, $section, $graph
    );
    if (@{ $rows }) {
        my $created_at = localtime($rows->[0][1]);
        my $updated_at = localtime($rows->[0][2]);
        return +{
            number     => $rows->[0][0],
            created_at => $created_at->ymd('/') . ' ' . $created_at->hms,
            updated_at => $updated_at->ymd('/') . ' ' . $updated_at->hms,
        };
    } else {
        return;
    }
}

sub update {
    my($self, $service, $section, $graph, $number, $description, $options) = @_;
    $description ||= '';

    my $dbh = $self->connection;
    $dbh->begin_work;

    my $data = $self->get($service, $section, $graph);
    if (defined $data) {
        if ($options->{mode} eq 'count') {
            $number += $data->{number};
        }
        $dbh->do(
            q{UPDATE graphs SET description=?, number=?, updated_at=? WHERE service_name=? AND section_name=? AND graph_name=?},
            {}, $description, $number, time(), $service, $section, $graph
        );
        $dbh->commit;
        return 0;
    } else {
        $dbh->do(
            q{INSERT INTO graphs (service_name, section_name, graph_name, description, number, created_at, updated_at) VALUES(?,?,?,?,?,?,?)},
            {}, $service, $section, $graph, $description, $number, time(), time()
        );
        $dbh->commit;
        return 1;
    }
}

sub create_config {
    my $self = shift;

    my $dbh = $self->connection;

    my $rows = $dbh->selectall_arrayref(
        q{SELECT service_name, section_name, graph_name, description FROM graphs ORDER BY created_at},
        {Slice => []},
    );
    return unless @{ $rows };

    my @servers_sort;
    my $servers = {};
    my $sections = {};
    for my $row (@{ $rows }) {
        my($service_name, $section_name, $graph_name, $description) = @{ $row };
        $servers->{$service_name} ||= do {
            push @servers_sort, $service_name;
            my $data = <<DATA;
--- #$service_name
servers:
DATA
            $data;
        };

        $sections->{"$service_name/$section_name.yaml"} ||= do {
            $servers->{$service_name} .= <<DATA;
  - config: $service_name/$section_name.yaml
    hosts:
      - $section_name.$service_name $description
DATA
            my $data = <<DATA;
---
resources:
DATA
            $data;
        };
        $sections->{"$service_name/$section_name.yaml"} .= "  - clothforest_basic:$graph_name\n";
    }

    my $server = '';
    for my $key (@servers_sort) {
        $server .= $servers->{$key};
    }
    +{
        server   => $server,
        sections => $sections,
    };
}

1;

