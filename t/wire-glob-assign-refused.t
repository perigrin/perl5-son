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
subtest 'a glob assignment is refused, and says why' => sub {
    my ( undef, $err ) = translate( <<'SRC', 'glob-assign' );
sub f { *FH = shift; 1 }
f(\*STDOUT);
SRC
    like $err, qr/GAP:/, 'it is refused';
    like $err, qr/glob/, '... naming the construct';
    # THE REASON IS SPECIFIC TO THIS SHAPE. A glob binding whose RHS type IS
    # known is lowered (t/wire-glob-assign-typed-binding.t); what refuses here
    # is the one whose slot nothing in the graph can name, and the message has
    # to say THAT rather than a blanket "no value store expresses it" -- the
    # two refusals are different facts and conflating them hid the decidable
    # case behind the undecidable one.
    like $err, qr/not known until runtime/,
        '... and that the slot is what is missing';
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
    ok !exists $wire->{methods}{'main::f'},
        'while the sub that assigns the glob is not';
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
