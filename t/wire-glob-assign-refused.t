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
    like $err, qr/glob/,        '... naming the construct';
    like $err, qr/symbol-table/, '... and why a value store cannot carry it';
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

done_testing;
