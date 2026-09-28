# ABOUTME: a glob binding aliases a slot; rendering it as a store is a wrong answer.
# ABOUTME: `*crackers = \@SRC` must come back as a glob assignment, not `@crackers = ...`.
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

# THE DEFECT. A glob assignment is a BINDING -- it aliases a symbol-table slot
# -- and the producer now records it as an EntryWrite into the slot the RHS
# type selects. Rendered as an ordinary store the emitted program is wrong,
# not merely different:
#
#     perl     *crackers = \@SRC;          ->  @crackers is 1 2 3
#     emitted  @main::crackers = \(@SRC);  ->  a one-element array of a ref
#
# which printed nothing where perl prints "1 2 3". A store PUTS A VALUE IN a
# slot; a binding makes the NAME refer to the referent. That distinction is
# the whole construct, so the renderer has to keep it.
# BLOCKED ON A SEPARATE DEFECT, and the cause recorded here first was WRONG.
# It said `\@SRC` over an `our` array loses the initialiser. It does not --
# measured, all three of these emit `@main::SRC = (1, 2, 3);` correctly:
#
#     our @SRC=(1,2,3);
#     our @SRC=(1,2,3); my $r=\@SRC;
#     our @SRC=(1,2,3); *c=\@SRC;
#
# (The original evidence for that claim was `print scalar(@$r)` emitting
# nothing, which turned out to be a scalar-context rv2av with no handler --
# fixed separately, t/wire-deref-count-in-scalar-context.t.)
#
# What actually drops the initialiser is the glob binding PLUS A READ THROUGH
# THE BOUND NAME: the binding renders correctly
# (`*main::crackers = \@main::SRC;`) and `@main::SRC` is never filled in. A
# narrower interaction than recorded, and still open.
{
    my $todo = todo 'a glob binding read through its bound name drops the initialiser';
    round_trips( <<'SRC', 'an array binding aliases the array' );
our @SRC = (1,2,3);
*crackers = \@SRC;
print "@crackers\n";
SRC
}

# A CODE BINDING INSTALLS A SUB under the new name, which is what makes the
# later call resolve at all.
# A CALL THROUGH A BOUND NAME RENDERS. The renderer refuses a call to a sub
# that is not in the graph, because emitting one would produce a program that
# dies -- but a name installed by a glob binding is defined at runtime, and
# the graph says so: the binding is an EntryWrite into the name's `&` slot.
# _defined_at_runtime reads exactly that. These were TODO while the check
# did not know it.
round_trips( <<'SRC', 'a code binding installs the sub' );
sub SRC { "code" }
*foo3 = \&SRC;
print foo3(), "\n";
SRC

round_trips( <<'SRC', 'an anon sub binding installs the sub' );
*foo4 = sub { 42 };
print foo4(), "\n";
SRC

# A SCALAR BINDING ALIASES THE SCALAR. Rendered as a store it printed
# SCALAR(0x...) -- the reference itself -- where perl prints what it points at.
round_trips( <<'SRC', 'a scalar binding aliases the scalar' );
our $S = "x";
*d = \$S;
print "$d\n";
SRC

# THE ALIAS IS LIVE, which is what separates a binding from a copy: a later
# write through either name is visible through both.
{
    my $todo = todo 'a glob binding read through its bound name drops the initialiser';
    round_trips( <<'SRC', 'the alias is live, not a copy' );
our @SRC = (1,2,3);
*crackers = \@SRC;
push @SRC, 4;
print "@crackers\n";
SRC
}

done_testing;
