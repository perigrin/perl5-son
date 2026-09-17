# ABOUTME: `until COND` is `while !COND` -- same loop, inverted exit sense.
# ABOUTME: the optrees differ only in and/or, so only the Proj senses swap.
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
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
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

# THE DEFECT. `until` was refused while the identical `while` translated --
# measured, the optrees are byte-identical but for the connective:
#
#     $i++ while $i < 3      9  lt      a  and(other->b)
#     $i++ until $i >= 3     9  ge      a  or(other->b)
#
# Both reach the BODY through `other`, so the only difference is which truth
# value gets there: `and` runs the body when the condition is TRUE, `or` when
# it is FALSE. That swaps the body and exit Projs and changes nothing else --
# the refusal's own comment said as much ("an `or` condition (until) would
# need the negated sense").
round_trips( <<'SRC', 'a simple until counts up' );
my $i = 0;
$i++ until $i >= 3;
print "$i\n";
SRC

# THE INVERTED SENSE IS THE WHOLE FIX, so a condition that is already true
# must run the body ZERO times -- the case that would silently loop forever,
# or run once, if the senses were merely copied from `while`.
round_trips( <<'SRC', 'an until whose condition starts true never runs' );
my $i = 9;
my $n = 0;
$n++ until $i >= 3;
print "i=$i n=$n\n";
SRC

# THE BLOCK FORM takes the same path as the statement modifier.
round_trips( <<'SRC', 'a block until' );
my $i = 0;
until ($i >= 3) { $i++ }
print "$i\n";
SRC

# A BARE-TRUTHINESS CONDITION has no comparison to wire the control edge to,
# and the `while` path synthesizes a NumNe(cond, 0) for exactly that reason.
# `until` must reach the same synthesis rather than fall through it.
round_trips( <<'SRC', 'an until on a bare truthiness test' );
my $i = 3;
$i-- until !$i;
print "$i\n";
SRC

# AND `while` IS UNDISTURBED -- the guard against fixing one sense by
# breaking the other.
round_trips( <<'SRC', 'while still counts up' );
my $i = 0;
$i++ while $i < 3;
print "$i\n";
SRC

done_testing;
