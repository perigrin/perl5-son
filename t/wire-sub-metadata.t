# ABOUTME: The wire carries per-sub METADATA, not just a node list.
# ABOUTME: params/uses_args come from the CV walk so consumers never scan the graph.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

# Compile $src through B::SoN and return the decoded wire structure.
sub wire_for ($src, $name, %opt) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    # package=main keeps the emitted set small, but it also EXCLUDES any other
    # package -- so a test about a non-main class must drop the filter or it
    # asserts against a section the filter removed, not against the feature.
    my $filter = $opt{no_filter} ? '' : ',package=main';
    my $json = qx{$PERL -Ilib -MO=SoN,json$filter $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

# The `subs` record hangs off the owning class. Every sub has one -- a
# file-level sub belongs to class `main`, because all code belongs to a class.
sub sub_record ($wire, $class, $name) {
    my $cls = $wire->{classes}{$class} or return undef;
    return ($cls->{subs} // {})->{$name};
}

subtest 'a file-level sub is recorded under class main' => sub {
    my $wire = wire_for('sub f { 42 } print f(), "\n";', 'plain');
    ok exists $wire->{classes}, 'the wire carries a classes section';
    my $rec = sub_record($wire, 'main', 'f');
    ok defined $rec, 'sub f is recorded under main'
        or diag explain $wire->{classes};
};

# uses_args is the CALLEE property the calling convention keys on: materialise
# @_ only when the body actually touches it. Recorded by the CV walk, which
# knows -- NOT recovered by scanning the graph, which cannot be done reliably
# (@_ has three IR spellings and vanishes entirely for `my ($a,$b) = @_`).
subtest 'uses_args is recorded per callee' => sub {
    my %want = (
        'sub f { 42 }'                      => 0,   # no @_ at all
        'sub f { my $n = shift; $n+1 }'     => 1,   # shift @_
        'sub f { $_[0] + 1 }'               => 1,   # positional subscript
        'sub f { my ($a,$b) = @_; $a+$b }'  => 1,   # list-assign (vanishes in IR!)
        'sub f { scalar @_ }'               => 1,   # reflective
    );
    my $i = 0;
    for my $body (sort keys %want) {
        $i++;
        my $wire = wire_for("$body\nprint 1;", "ua$i");
        my $rec  = sub_record($wire, 'main', 'f');
        ok defined $rec, "record exists for: $body" or next;
        is !!$rec->{uses_args}, !!$want{$body},
            sprintf('uses_args=%d for: %s', $want{$body}, $body);
    }
};

# Arity is metadata too. The backend's current arity check COUNTS positional
# reads in the callee graph; that is the scan this record exists to retire.
subtest 'declared arity is recorded' => sub {
    my $wire = wire_for('sub f { my ($a,$b) = @_; $a+$b } print f(1,2), "\n";', 'arity');
    my $rec  = sub_record($wire, 'main', 'f');
    ok defined $rec, 'record exists' or return;
    ok exists $rec->{params}, 'a params key is present';
};

# A sub in a real class keeps working -- the subs record must not disturb the
# existing methods/fields replay.
subtest 'a class still carries its methods' => sub {
    my $wire = wire_for(<<'PERL', 'cls', no_filter => 1);
package Counter { sub bump { 1 } }
print Counter::bump(), "\n";
PERL
    my $rec = sub_record($wire, 'Counter', 'bump');
    ok defined $rec, 'a package sub is recorded under its own class'
        or diag explain $wire->{classes};
};

done_testing;
