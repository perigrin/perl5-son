# ABOUTME: Every binary operator the corpus uses must render to its Perl spelling.
# ABOUTME: Checked by RUNNING the rendered program, not by matching the emitted text.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# ROUND-TRIP OR SAY WHY. A rendering that differs is a producer or emitter
# defect; a rendering that refuses names the missing rule. Both are reported,
# neither is silent.
sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}

# PERL FOLDS CONSTANT OPERANDS BEFORE B::SoN SEES THEM, so `1 == 1` builds NO
# comparison node at all -- measured, it is Start/Constant/Constant/Print/Return
# and the whole operator vanishes. An earlier version of this file used literal
# operands and every comparison "passed" while testing nothing. Bind the
# operands to pad variables so the operator survives into the graph. See the
# memory note graph-correctness-needs-the-optree-not-the-source.
#
# THE OPERATORS ARE NOT INTERCHANGEABLE, and a wrong spelling is a wrong answer
# rather than a cosmetic slip: `==` for `eq` agrees on numbers and disagrees on
# strings, which is the Int/Str confusion the stamp lattice exists to track.
# Each case uses operands where the WRONG spelling gives a different result.
my $P = 'my ($a, $b) = (2, 3); ';

subtest 'numeric comparisons' => sub {
    round_trips($P.'print $a == $b ? "y\n" : "n\n";',  'NumEq');
    round_trips($P.'print $a != $b ? "y\n" : "n\n";',  'NumNe');
    round_trips($P.'print $a >  $b ? "y\n" : "n\n";',  'NumGt');
    round_trips($P.'print $a <  $b ? "y\n" : "n\n";',  'NumLt');
    round_trips($P.'print $a <= $b ? "y\n" : "n\n";',  'NumLe');
    round_trips($P.'print $a >= $b ? "y\n" : "n\n";',  'NumGe');
};

subtest 'string comparisons' => sub {
    my $S = 'my ($a, $b) = ("x", "y"); ';
    round_trips($S.'print $a eq $b ? "y\n" : "n\n";',  'StrEq');
    round_trips($S.'print $a ne $b ? "y\n" : "n\n";',  'StrNe');
};

subtest 'arithmetic' => sub {
    round_trips($P.'print $a + $b, "\n";',  'Add');
    round_trips($P.'print $a - $b, "\n";',  'Subtract');
    round_trips($P.'print $a * $b, "\n";',  'Multiply');
};

# `.` on two numbers gives "23" where `+` gives 5, so a wrong spelling here is
# caught by the OUTPUT rather than by reading the emitted source.
subtest 'string operators' => sub {
    round_trips($P.'print $a . $b, "\n";',   'Concat');
    round_trips('my $a = "ab"; my $b = 2; print $a x $b, "\n";', 'Repeat');
};

subtest 'bitwise' => sub {
    my $B = 'my ($a, $b) = (6, 3); ';
    round_trips($B.'print $a & $b, "\n";',  'BitAnd');
    round_trips($B.'print $a | $b, "\n";',  'BitOr');
    round_trips($B.'print $a ^ $b, "\n";',  'BitXor');
};

done_testing;
