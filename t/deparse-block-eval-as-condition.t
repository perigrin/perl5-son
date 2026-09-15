# ABOUTME: A block eval refuses -- the wire records its join but not its entry.
# ABOUTME: A string eval renders, because its Region's input IS the eval.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# A BLOCK EVAL'S VALUE IS 1-OR-UNDEF, and `if (eval { ... })` reads it.
# Measured on `if (eval { $g = 1; 1 }) {...}`:
#
#     16 Region in=[10]      a SINGLE-input Region
#     17 Phi    in=[6, 1]    the block's value, or undef if it died
#     18 If     in=[16, 17]  the Phi IS the condition
#
# The Phi's region is neither a Loop (so it is not loop-carried) nor a
# two-armed branch join (so _join_phis does not own it), which is why the Phi
# rule refused it.
#
# base/rs.t's test_bad_setting is this shape eight times over:
# `if (eval { $/ = \0; 1 }) { ... } else { ... }`.
#
# THE BODY CANNOT BE DELIMITED, so this REFUSES rather than guessing. The wire
# records the eval's JOIN but not its ENTRY -- measured on
# `our $g=0; our $h=0; $h=5; if (eval { $g = 1; 1 }) {...}`:
#
#     Region(23) in=[12]
#     chain back: EntryWrite 12, 11, 10, 9, Start
#
# Four stores chain to Start and nothing marks which is inside the eval; only
# the last one is. Guessing left statements outside the block, and a `die`
# among them then escaped -- measured, the emitted program died where perl
# printed "died g=1".
#
# A block eval's whole meaning is WHICH statements it protects, so a refusal is
# the only honest answer until the producer records the entry.
subtest 'a block eval refuses, naming what is missing' => sub {
    for my $src ('our $g = 0; if (eval { $g = 1; 1 }) { print "ok\n" } else { print "died\n" }',
                 'our $g = 0; if (eval { die "x\n"; 1 }) { print "ok\n" } else { print "died\n" }') {
        my $data = graph_of($src);
        ok $data && $data->{methods}{'main::__PROGRAM__'}, 'it translates'
            or next;
        my $d = SoN::Deparse->new;
        my $out = $d->render($data);
        ok !defined $out, 'the deparse refuses it' or next;
        like $d->gap, qr/records the join but not the entry/,
            '... naming the entry as what is missing';
    }
};

# A STRING EVAL STILL RENDERS -- its Region's input IS the eval, so the body
# needs no delimiting. That is what makes this about the BLOCK form.
subtest 'a string eval still round-trips' => sub {
    round_trips(<<'SRC', 'a value-producing string eval');
my $v = eval "1+1";
print "[$v]\n";
SRC
};

# A PLAIN CONDITION MUST NOT REGRESS -- an ordinary If whose condition is a
# comparison is the common case.
subtest 'an ordinary condition still round-trips' => sub {
    round_trips(<<'SRC', 'a numeric test');
my $x = @ARGV ? 9 : 2;
if ($x > 1) { print "big\n" } else { print "small\n" }
SRC
};

done_testing;
