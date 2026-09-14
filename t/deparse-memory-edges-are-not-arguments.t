# ABOUTME: A builtin's trailing memory edge orders it; it is never an argument.
# ABOUTME: Rendering it emits the memory node as an operand, which has no spelling.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
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

# THE PRODUCER APPENDS MEMORY LAST, at three sites, and the set of names is
# wider than the emitter's list was:
#
#     FromOptree.pm:5981   keys values each
#     FromOptree.pm:6027   push unshift splice
#     FromOptree.pm:6060   shift pop
#
# The emitter filtered on `keys|values|each` only, so `shift` rendered its
# memory edge as a second argument and refused on `no rule for value node
# MemStart`. Measured on comp/package.t's `sub foo { my $s = shift; ... }`:
#
#     3 Call  in=[1,2]  name=shift    1 = ArgsSource, 2 = MemStart
#
# A NAME LIST IS THE WRONG DISCRIMINATOR -- it fails asymmetrically, silently
# dropping whichever name nobody thought of. The invariant is structural: the
# edge is a MEMORY node in the last position.
subtest 'shift does not render its memory edge' => sub {
    round_trips(<<'SRC', 'shift inside a sub');
sub foo { my $s = shift; return $s + 1 }
print foo(41), "\n";
SRC

    round_trips(<<'SRC', 'shift and pop over one array');
my @a = (1, 2, 3);
my $f = shift @a;
my $l = pop @a;
print "$f $l @a\n";
SRC
};

# THE MUTATORS TOO, from the second producer site.
subtest 'push and splice do not render theirs' => sub {
    round_trips(<<'SRC', 'push then read');
my @a = (1, 2);
push @a, 3;
print "@a\n";
SRC
};

# AND THE READERS, which is the case that already worked -- kept so a fix that
# swaps one asymmetric list for another shows up here.
subtest 'keys still does not render its memory edge' => sub {
    round_trips(<<'SRC', 'keys over a named hash');
my %h = (a => 1);
$h{b} = 2;
my @k = sort keys %h;
print "@k\n";
SRC
};

done_testing;
