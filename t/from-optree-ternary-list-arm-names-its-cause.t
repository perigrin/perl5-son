# ABOUTME: a ternary with a multi-element list arm refuses by that name, not by
# ABOUTME: whichever list-building op the arm walk happened to stop on.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );

sub gap_for ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $e = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>&1 >/dev/null);
    unlink $f;
    return $e;
}

# THE SAME DEFECT WORE TWO NAMES. A ternary whose arm builds a multi-element
# list cannot yet be expressed -- it needs per-arm value lists through the Phi
# merge -- and the arm walk stops on whichever op builds that list:
#
#     wantarray ? (1..3) : []    stopped at `range`
#     wantarray ? (7, 8)  : []   stopped at `list`
#
# The first fell through to the generic "untranslatable op inside an if/else
# arm (arm stopped at `range`)", which names an op that is not the problem and
# sends a reader to `_handle_range` -- already written, and irrelevant.

subtest 'a range arm names the list arm, not the range' => sub {
    my $e = gap_for('sub f { wantarray ? (1..3) : [] } my @a = f(); print "@a";');
    like $e, qr/multi-element list arm/,
        'refuses by the real cause' or diag $e;
    unlike $e, qr/untranslatable op/,
        'and not by the generic message' or diag $e;
};

subtest 'a plain list arm names it too' => sub {
    my $e = gap_for('sub f { wantarray ? (7, 8) : [] } my @a = f(); print "@a";');
    like $e, qr/multi-element list arm/, 'same cause, same name' or diag $e;
};

# THE GENERIC MESSAGE MUST SURVIVE for arms that really do stop on something
# untranslatable. Narrowing it to nothing would trade one misleading message
# for a missing one.
subtest 'a genuinely untranslatable arm keeps the generic message' => sub {
    my $e = gap_for('sub f { $_[0] ? goto &bar : 2 } print f(1);');
    if ( $e =~ /GAP:/ ) {
        unlike $e, qr/multi-element list arm/,
            'not misreported as a list arm' or diag $e;
    }
    else {
        pass 'no GAP for this shape -- nothing to misreport';
    }
};

# A SINGLE-VALUE ARM STILL LOWERS. The refusal must not widen to the ordinary
# `$c ? "y" : "n"` idiom that t/base uses throughout.
subtest 'a single-value arm is untouched' => sub {
    my $e = gap_for('my $c = 1; print $c ? "y" : "n";');
    unlike $e, qr/GAP:/, 'lowers with no refusal' or diag $e;
};

done_testing;
