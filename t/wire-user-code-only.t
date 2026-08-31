# ABOUTME: The wire carries the user's graphs, not the producer's internals.
# ABOUTME: Scoped by $0 (what we were ASKED to compile), never by package name.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub wire ( $src, $name, $opts = '' ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json$opts $file 2>$dir/$name.err};
    die "no JSON for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

my $SRC = q{use feature 'class'; no warnings 'experimental::class';
class Counter { field $val :param = 0; method inc { $val + 1 } }
my $c = Counter->new(val => 5);
print $c->inc;};

# THE DEFECT, reported by chalk and reproduced here. Without an explicit
# package= filter the wire carried 420 graphs / 3150 nodes for this four-line
# program -- 294 of them B::SoN's and SoN::IR's own subs, because perl had
# loaded the producer into the same interpreter that is compiling the user's
# file. chalk could not tell its graphs from ours, so it could not measure
# whether USER programs still carry Unknown stamps -- the number that scopes
# its T2 pass.
#
# SCOPED BY $0, NOT BY PACKAGE NAME, and the distinction is load-bearing:
# Chalk is metacircular. When it compiles B::SoN, $0 IS B::SoN and those graphs
# are then correctly INCLUDED. Excluding the producer by name would pass this
# test and break self-hosting.
subtest 'the wire carries only graphs from the file under compilation' => sub {
    my $w = wire( $SRC, 'useronly' );
    my @g = sort keys( ( $w->{methods} // {} )->%* );

    ok scalar(@g), 'there are graphs at all' or return;
    is scalar( grep { /^(?:SoN|B::SoN)(?:::|$)/ } @g ), 0,
        'no producer-internal graphs on the wire';
    ok scalar( grep { /^Counter::/ } @g ), 'the user class is present';
    ok scalar( grep { /^main::/ } @g ),    'and the user program';
};

# THE SAME ANSWER WITH OR WITHOUT package=. The explicit filter was the only
# thing holding this back before, so a run that passes it must not differ.
subtest 'package=main gives the same graph set' => sub {
    my $bare = wire( $SRC, 'bare' );
    my $pkg  = wire( $SRC, 'pkg', ',package=main' );
    is_deeply [ sort keys( ( $bare->{methods} // {} )->%* ) ],
              [ sort keys( ( $pkg->{methods}  // {} )->%* ) ],
              'the graph set does not depend on package=';
};

# A USER SUB IN AN ARBITRARY PACKAGE IS STILL USER CODE. The predicate asks
# which FILE the CV came from, not which package it was declared in, so a
# program that declares `package Foo` keeps its graphs.
subtest 'a user sub in its own package survives the filter' => sub {
    my $w = wire( q{package Foo; sub helper { 41 + 1 } package main;
print Foo::helper();}, 'otherpkg' );
    my @g = sort keys( ( $w->{methods} // {} )->%* );
    ok scalar( grep { /^Foo::helper$/ } @g ),
        'a sub in a user-declared package is kept';
    is scalar( grep { /^(?:SoN|B::SoN)(?:::|$)/ } @g ), 0,
        'and the producer is still excluded';
};

done_testing;
