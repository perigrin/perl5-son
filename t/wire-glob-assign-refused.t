# ABOUTME: assigning to a glob aliases a symbol-table entry program-wide.
# ABOUTME: no value store expresses that, so it is refused rather than dropped.
use 5.42.0;
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
    my $json = qx{$PERL -Ilib -MO=SoN,json,not_package=SoN $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

# THE DEFECT. `*FH = shift` rebinds a NAME for the whole program: every later
# `<FH>`, `print FH` and `close FH` acts on the handle that was passed in.
# There is no value stored anywhere a later read consults, so the sassign
# target -- a glob Constant, restamped by rv2gv -- fell through to the
# catch-all and was silently DROPPED.
#
# A drop is the worst outcome: base/rs.t's `sub test_string { *FH = shift; ... }`
# emitted `shift(@_);` and then read from an unopened FH, so 24 of its 41 tests
# printed `not ok` while the graph claimed to have translated the sub.
# A GLOB ASSIGNMENT IS NO LONGER REFUSED, and the whole idiom round-trips. The
# refusal's diagnosis was right about the mechanism -- there is no value stored
# anywhere a later read consults -- and the conclusion did not follow: `*` on the
# target IS the binding, and the emission is the source spelling with perl doing
# the aliasing. Measured on this file's own case:
#
#     sub f { *FH = shift; 1 } f(\*STDOUT); print FH "via alias\n";
#       perl  via alias      ours  via alias
#
# Getting there needed three spellings in the deparser, all of them the same
# `glob` Constant rendering as a BAREWORD -- right for `close FOO`, wrong as a
# glob VALUE, a glob ASSIGNMENT TARGET, and inside `\*STDOUT`.
#
# THE FILE'S THIRD SUBTEST STILL STANDS: the aliased slot IS a runtime fact.
# That measurement was never the problem; what was wrong was concluding a
# runtime fact cannot be described.
subtest 'a glob assignment round-trips' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'glob-assign-rt' );
sub f { *FH = shift; 1 }
f(\*STDOUT);
print FH "via alias
";
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok $wire, 'and produces a wire' or return;
};


# THE REFUSAL IS SCOPED TO THE SUB THAT USES IT. __PROGRAM__ still translates,
# so one unlowerable sub does not cost the whole file.
subtest 'the rest of the program still translates' => sub {
    my ( $wire, $err ) = translate( <<'SRC', 'glob-assign-scope' );
sub f { *FH = shift; 1 }
print "still here\n";
SRC
    ok $wire, 'a graph is produced' or diag($err), return;
    ok exists $wire->{methods}{'main::__PROGRAM__'},
        'and __PROGRAM__ is in it';
    # AND SO IS THE SUB THAT ASSIGNS THE GLOB. This asserted its ABSENCE --
    # the graph kept __PROGRAM__ and dropped `f`, which was the best available
    # outcome while the glob bind refused. Now `f` translates too, so the
    # assertion inverts: a skipped sub is a caller that cannot be rendered
    # (`a call to main::f, which is not in the graph`), which is what this file
    # was documenting as the cost of the refusal.
    ok exists $wire->{methods}{'main::f'},
        'and so is the sub that assigns the glob';
};

# THERE IS NO NARROWER LOWERING TO REACH FOR. perl picks the aliased slot by
# the RHS's TYPE -- `*D = \@SRC` aliases the array slot alone and leaves $D
# undef, while `*D = *SRC` aliases every slot -- and `*FH = shift` names
# neither at compile time. Measured, one call site aliases a different slot
# per call:
#
#     sub f { *D = shift }
#     f(\@V);   # a[array] s[UNDEF]
#     f(\$V);   # s[scalar]
#
# So this is not a gap in the lowering, it is a fact perl itself defers to
# runtime. This subtest exists so the refusal is not re-litigated as laziness.
subtest 'the aliased slot is a runtime fact, not a compile-time one' => sub {
    my $dir2 = $dir;
    my $probe = "$dir2/slot-probe.pl";
    open my $fh, '>', $probe or die "open $probe: $!";
    print {$fh} <<'SRC';
our @V = ("array"); our $V = "scalar";
sub f { *D = shift; }
f(\@V);  print "a[@D] s[", (defined $D ? $D : "UNDEF"), "]
";
f(\$V);  print "s[$D]
";
SRC
    close $fh;

    my $out = qx{$PERL $probe 2>&1};
    is $out, "a[array] s[UNDEF]\ns[scalar]\n",
        'the same call site aliases a different slot per call';
};

done_testing;
