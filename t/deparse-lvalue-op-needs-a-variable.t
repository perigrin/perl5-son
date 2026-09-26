# ABOUTME: lock/pos/tied need a MODIFIABLE operand, so a binding they read must
# ABOUTME: be emitted as a variable rather than inlined as its value.
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
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
        diag $err;
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

# PERL REJECTS AN EXPRESSION IN THESE SLOTS AT COMPILE TIME. Measured, each of
# lock, pos, tied and chomp given `(1 // 7)`:
#
#     Can't modify constant item in lock
#     Can't modify constant item in match position
#     Can't modify constant item in tied
#     Can't modify constant item in chomp
#
# and given a plain `$x`, all four accept it. So the operand must be a
# MODIFIABLE thing, not a value.
#
# The emitter inlines a binding whose value is cheap, which is right everywhere
# else and wrong here -- measured on `my $n = $ENV{N} // 7; lock($n)`:
#
#     my $eff6 = lock(($ENV{'N'} // 7));
#
# The source's `my $n` dissolved into its value and perl refused to compile the
# result. Five of the corpus's DIFFERS cases fail exactly this way, which is the
# largest single cause among them -- and an emission that does not compile is
# worse than one that prints the wrong thing, because nothing downstream can
# even run it.

subtest 'lock takes a variable' => sub {
    round_trips( <<'SRC', 'lock on a bound scalar' );
my $n = 7;
lock($n);
print "locked $n\n";
SRC
};

# POS NAMES THE VARIABLE, which is this cause; whether the graph still HOLDS
# the match that set the position is a separate defect, recorded in
# docs/plans/2026-09-26-a-void-g-match-is-dropped.md. So this asserts the
# SPELLING of the operand, which is what the arity guard owns.
subtest 'pos names its variable rather than inlining a value' => sub {
    my $src = <<'SRC';
my $s = "abcabc";
my $a = pos($s);
print defined($a) ? "p$a\n" : "undef\n";
SRC
    my ( $data, $err ) = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail 'translates';
        diag $err;
        return;
    }
    my $out = eval { SoN::Deparse->new->render($data) };
    unless ( defined $out ) { fail 'renders'; diag $@; return }
    like $out, qr/\bpos\(\s*\$\w+\s*\)/,
        'the operand is a variable, not a parenthesised value'
        or diag $out;

    # AND IT COMPILES. `pos((...))` is the failure this guards; perl rejects it
    # with `Can't modify constant item in match position`.
    my $f = "$dir/c." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $out;
    close $fh;
    my $chk = qx($^X -c $f 2>&1);
    unlink $f;
    like $chk, qr/syntax OK/, 'the emission compiles' or diag $chk;
};

subtest 'tied takes a variable' => sub {
    round_trips( <<'SRC', 'tied on an untied scalar' );
my $x = 1;
print defined(tied($x)) ? "t\n" : "u\n";
SRC
};

# AN ORDINARY INLINE MUST BE UNDISTURBED. The emitter inlining a cheap value is
# correct everywhere that does not need an lvalue, and a fix that stopped doing
# it would change every emission in the suite.
subtest 'an ordinary read still inlines' => sub {
    round_trips( <<'SRC', 'a plain binding used in an expression' );
my $n = 7;
print $n + 1, "\n";
SRC
};

done_testing;
