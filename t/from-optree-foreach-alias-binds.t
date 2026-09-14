# ABOUTME: The implicit `$_` of a foreach is bound to the element it aliases.
# ABOUTME: An unbound alias reads a global nothing wrote, which is a silent wrong answer.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use SoN::Deparse;
use File::Temp qw(tempdir);

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
    unlink $f;
    my $d = eval { JSON::PP->new->decode($j) } or return undef;
    return $d->{methods}{'main::__PROGRAM__'};
}

# THE ORACLE: render the graph back to perl and RUN it. A read-side graph
# assertion cannot see the write DIRECTION -- the defect emitted a well-formed
# graph that stored the RESULT into `$_` and `undef * 10` into the element, and
# every structural check it could fail, it passed. Only running the emitted
# program against perl's own answer catches that.
sub emit ($src) {
    my $f = "$dir/e." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    my $g = eval { JSON::PP->new->decode($j) } or return undef;
    my $d = SoN::Deparse->new;
    return $d->render($g);
}

# THE ALIAS MUST BE BOUND TO THE ELEMENT. Measured on
# `my @a=(1,2); for (@a) { $_ = $_ * 10 }` -- perl gives `10 20`:
#
#      8 Subscript  in=[4, 7]        the element
#     10 EntryDef   in=[9]           $main::_, memory = MemStart
#     12 Multiply   in=[10, 11]      reads the UNBOUND alias
#     15 EntryWrite in=[13, 12, 9]   writes the RESULT into $_
#     16 Assign     in=[8, 12]       stores that into the element
#
# so the body reads `$_` at MemStart -- nothing ever binds it to
# Subscript(8) -- and the only write goes the wrong way, putting the RESULT
# into `$_` rather than the ELEMENT into it. The emitted program computed
# `undef * 10` and stored 0.
#
# An explicit loop variable (`for my $x (@a)`) is correct today, which is what
# makes this about the IMPLICIT alias rather than about foreach.
subtest 'the implicit $_ is the element' => sub {
    my $src = 'my @a = (1, 2); for (@a) { $_ = $_ * 10 } print "@a\n";';
    is run_perl($src), "10 20\n", 'perl multiplies in place' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;

    # THE MULTIPLY MUST READ THE ELEMENT. That is the binding, stated
    # positively: the body's `$_ * 10` has to consume the loop's element
    # Subscript, not a name lookup.
    #
    # NOT SPELLED AS "no EntryDef sits at MemStart". That was the first
    # version, and a bound graph makes it VACUOUS -- with the alias forwarded
    # there is no EntryDef read of `$_` left to test, so the check passed by
    # finding nothing and its companion 'the body reads $_' failed for being
    # right. An assertion that the fix deletes is not an assertion.
    my ($mul) = grep { ($_->{op} // '') eq 'Multiply' } $g->{nodes}->@*;
    ok $mul, 'the body multiplies' or return;

    my $lhs = $by{ ($mul->{inputs} // [])->[0] // -1 };
    is $lhs->{op}, 'Subscript', 'and its left operand is the element read';

    # AND THAT SUBSCRIPT IS THE LOOP'S OWN, indexed by the induction Phi --
    # any Subscript would satisfy the check above.
    my $idx = $by{ ($lhs->{inputs} // [])->[1] // -1 };
    is $idx->{op}, 'Phi', 'indexed by the loop induction variable';
};

# AN EXPLICIT LOOP VARIABLE IS CORRECT TODAY and must not regress.
subtest 'an explicit loop variable' => sub {
    my $src = 'my @a = (1, 2); for my $x (@a) { $x = $x * 10 } print "@a\n";';
    is run_perl($src), "10 20\n", 'perl multiplies in place' or return;
    ok graph_of($src), 'it translates';
};

# THE ALIAS IS A WRITE-THROUGH, END TO END. `$_` in a foreach aliases the
# element, so writing it writes the array. Measured, perl against the emitted
# program:
#
#     for (@a) { $_ = $_ * 10 }     perl 10 20     was 0 0
#     for (@a) { $_ = $_ + 100 }    perl 101 102   was 200 300
#
# The second is the one a read-side check would never reach: the unbound
# EntryDef hash-consed across iterations, so the Add folded against a value
# from the wrong pass. Both are silent wrong answers, not crashes.
subtest 'the alias writes through to the array' => sub {
    for my $src (
        'my @a = (1, 2); for (@a) { $_ = $_ * 10 } print "@a\n";',
        'my @a = (1, 2); for (@a) { $_ = $_ + 100 } print "@a\n";',
        'my @a = (1, 2); for (@a) { print $_ } print "\n";',
        'my @a = (1, 2); for my $x (@a) { $x = $x * 10 } print "@a\n";',

        # THE RANGE FORM ALIASES `$_` TOO, and the demotion behind the array
        # form's miscompile is PROGRAM-WIDE -- so a write to `$_` in ONE loop
        # broke a range loop elsewhere. The second line has no write in its
        # range loop at all and was still wrong (perl 6, emitted 3).
        'for (1..3) { $_ = $_ * 2; print $_ } print "\n";',
        'my @b = (9); for (@b) { $_ = 1 } my $s = 0;'
            . ' for (1..3) { $s = $s + $_ } print "$s\n";',
    ) {
        my $want = run_perl($src);
        my $out  = emit($src);
        ok defined $out, "it renders: $src" or next;
        is run_perl($out), $want, "round-trips: $src";
    }
};

done_testing;
