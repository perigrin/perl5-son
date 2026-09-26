# ABOUTME: IsaOp and Parameter reach the wire from ordinary Perl and had no
# ABOUTME: deparser rule, so any graph containing either refused outright.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );

sub run_perl ($src) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        return;
    }
    my $d   = SoN::Deparse->new;
    my $out = eval { $d->render($data) };
    unless ( defined $out ) {
        my $g = $d->gap // $@ // '(no reason)';
        $g =~ s/\n.*//s;
        fail "$name: renders";
        diag $g;
        return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# BOTH ARE REACHABLE AND NEITHER HAD A RULE. Found by diffing our round-trip
# results against pvm's ratchet over the same 212 programs: both cases are ones
# a working Perl implementation handles, so neither is blocked on a question
# about Perl.
#
#     IsaOp      `$o isa Foo`  -- in=[object, class-name], a plain binary
#     Parameter  a signature parameter, carrying index/name/sigil
#
# t/op-coverage.t already had fixtures producing both, which is that gate's
# stated limit showing up twice more: observing a node kind is not verifying it.

subtest 'isa is an infix operator' => sub {
    round_trips( <<'SRC', 'isa against a true and a false class' );
use v5.36;
package Foo;
package Bar;
package main;
my $o = bless {}, "Foo";
my $yes = $o isa Foo;
my $no  = $o isa Bar;
print "$yes$no|\n";
SRC

    round_trips( <<'SRC', 'isa on a runtime-chosen class' );
use v5.36;
package Foo;
package main;
my $name = "Foo";
my $o = bless {}, $name;
print(($o isa Foo) ? "y\n" : "n\n");
SRC
};

subtest 'a signature names its parameters' => sub {
    # A DEFAULT IS NOT ON THE WIRE, so no deparser rule can recover it. The
    # graph for `sub add_up ($a, $b = 3)` is
    #
    #     1 Parameter index=0 name=$a sigil=$
    #     2 Parameter index=1 name=$b sigil=$
    #     3 Add       in=[1,2]
    #
    # with the `3` nowhere. So `add_up(1)` emits `$_[0] + $_[1]`, reads undef
    # for the missing argument and gives 1 where perl gives 4. A PRODUCER
    # defect: the Parameter node carries index, name and sigil and has no
    # slot for a default, and perl's own lowering of a signature default is a
    # conditional assignment the walker is not recording.
    {
        my $todo = todo 'a signature default is absent from the wire (producer)';
        round_trips( <<'SRC', 'two parameters, one with a default' );
use v5.36;
sub add_up ($a, $b = 3) { $a + $b }
print add_up(1), " ", add_up(1, 10), "\n";
SRC
    }

    round_trips( <<'SRC', 'a signature with no default' );
use v5.36;
sub pair ($x, $y) { return "$x-$y" }
print pair("a", "b"), "\n";
SRC
};

done_testing;
