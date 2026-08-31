# ABOUTME: `local` rebinds for a scope and RESTORES the old binding at exit.
# ABOUTME: Under SSA a package variable is a binding, so restore is a rebind.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub nodes ( $w ) {
    return [ map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# THE DEFECT. `local` was refused outright, on the grounds that "the temporary
# binding must be restored at scope exit" -- which is the right requirement and
# was simply not wired. perl is unambiguous about what it costs to get wrong:
#
#     our $g = 1; { local $g = 2; print $g } print $g;   # prints 21
#
# 2 inside the scope, 1 after. Without the restore the second read sees 2.
#
# UNDER SSA THIS IS A REBIND, NOT A SAVE/RESTORE OF MEMORY. A package scalar is
# a value binding in the scope map (`$g = 2` rebinds main::$g to a new node --
# measured, the graph for `our $g=1; $g=2; print $g` has no cell at all), so
# restoring means putting the OLD binding back at scope exit. The block's extent
# is visible: a bare block compiles to enterloop/leaveloop with nextop == lastop,
# which the walker already discriminates from a real loop.
subtest 'local on a package scalar translates' => sub {
    my ( $w, $err ) = translate(
        'our $g = 1; { local $g = 2; print $g; } print $g;', 'local-scalar' );
    ok $w, 'it translates rather than GAPping' or diag($err), return;
    unlike $err, qr/`local`/, 'no local GAP';
};

# THE RESTORE MUST ACTUALLY HAPPEN. Two Prints, and they must NOT read the same
# node: the first sees the localized value, the second the restored one. A
# translation that dropped the restore would still build two Prints.
subtest 'the read after the scope sees the restored binding' => sub {
    my ( $w, $err ) = translate(
        'our $g = 1; { local $g = 2; print $g; } print $g;', 'local-restore' );
    ok $w, 'it translates' or diag($err), return;

    my $ns = nodes($w);
    my %by = map { $_->{id} => $_ } $ns->@*;
    my @print = grep { ( $_->{op} // '' ) eq 'Print' } $ns->@*;
    is scalar(@print), 2, 'both prints survive' or return;

    my @vals = map {
        my $n = $by{ ( $_->{inputs} // [] )->[0] // -1 };
        # A Print's operand is a Coerce over the value; unwrap it.
        ( ( $n->{op} // '' ) eq 'Coerce' )
            ? $by{ ( $n->{inputs} // [] )->[0] // -1 } : $n;
    } @print;

    ok $vals[0] && $vals[1], 'both prints have a value' or return;
    isnt $vals[0]{id}, $vals[1]{id},
        'the two prints read DIFFERENT nodes -- the restore happened';
    is $vals[1]{fields}{value}, 1,
        'and the second reads the pre-local value';
};

# local ON A PACKAGE ARRAY is the rs.t case (`local @INC = (...)`), and takes
# the same path -- the binding is keyed the same way, sigil included.
subtest 'local on a package array translates' => sub {
    my ( $w, $err ) = translate(
        'our @a = (1); { local @a = (2); print scalar(@a); } print scalar(@a);',
        'local-array' );
    ok $w, 'it translates' or diag($err), return;
    unlike $err, qr/`local`/, 'no local GAP';
};

# A LOOP BODY IS STILL REFUSED, and this is the guard that keeps the fix
# honest. `local` there restores once per ITERATION -- measured,
# `for (1..3) { print $g; local $g = $g+1; print $g }` prints 121212, each pass
# starting from the outer value -- while a scope-exit rebind would give every
# iteration the last pass's value. Before the guard the graph built a
# loop-carried Phi for $g, which is the opposite recurrence and silently wrong.
subtest 'local inside a loop body is refused' => sub {
    my ( undef, $err ) = translate(
        'our $g = 1;
for my $i (1..3) { print $g; local $g = $g + 1; print $g; }
print $g;', 'local-loop' );
    like $err, qr/GAP:/, 'refused';
    like $err, qr/per ITERATION/,
        '... naming the recurrence it cannot express';
};

done_testing;
