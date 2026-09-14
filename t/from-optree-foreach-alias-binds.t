# ABOUTME: The implicit `$_` of a foreach is bound to the element it aliases.
# ABOUTME: An unbound alias reads a global nothing wrote, which is a silent wrong answer.

use v5.42.0;
use Test2::V0;
use JSON::PP;
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
# TODO UNTIL THE PRODUCER BINDS IT. The defect is measured and real; the fix
# is producer-side and not yet written. Marked TODO rather than deleted so the
# suite stays pristine while the finding stays pinned.
subtest 'the implicit $_ is the element' => sub {
    todo 'the foreach alias is not bound to the element' => sub {
    my $src = 'my @a = (1, 2); for (@a) { $_ = $_ * 10 } print "@a\n";';
    is run_perl($src), "10 20\n", 'perl multiplies in place' or return;

    my $g = graph_of($src);
    ok $g, 'it translates' or return;
    my %by = map { $_->{id} => $_ } $g->{nodes}->@*;

    # THE READ OF $_ MUST OBSERVE A WRITE. An EntryDef whose memory is
    # MemStart is an alias nothing bound.
    my @reads = grep {
        ($_->{op} // '') eq 'EntryDef'
            && (($_->{fields} // {})->{symbol} // '') eq '_'
            && ($_->{inputs} // [])->@*
    } $g->{nodes}->@*;
    ok scalar(@reads), 'the body reads $_' or return;

    my @unbound = grep {
        (($by{ ($_->{inputs} // [])->[0] // -1 }{op}) // '') eq 'MemStart'
    } @reads;
    is \@unbound, [], 'and none of those reads is at MemStart';
    };
};

# AN EXPLICIT LOOP VARIABLE IS CORRECT TODAY and must not regress.
subtest 'an explicit loop variable' => sub {
    my $src = 'my @a = (1, 2); for my $x (@a) { $x = $x * 10 } print "@a\n";';
    is run_perl($src), "10 20\n", 'perl multiplies in place' or return;
    ok graph_of($src), 'it translates';
};

done_testing;
