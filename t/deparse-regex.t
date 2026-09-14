# ABOUTME: Regex match/substitution render with their pattern and flags intact.
# ABOUTME: A dropped flag is a different program, so the check is the match RESULT.

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

# A FLAG IS NOT COSMETIC. /i changes what matches, /g changes how many times --
# so each case is chosen where DROPPING the flag gives a different answer, and
# the match result is what the round-trip compares.
subtest 'a match carries its pattern and flags' => sub {
    round_trips('my $s = "abc"; print(($s =~ /b/) ? "y\n" : "n\n");', 'plain');
    round_trips('my $s = "ABC"; print(($s =~ /b/i) ? "y\n" : "n\n");', '/i matters');
    round_trips('my $s = "ABC"; print(($s =~ /b/) ? "y\n" : "n\n");', 'no /i matters');
    round_trips('my $s = "abc"; print(($s !~ /z/) ? "y\n" : "n\n");', 'negated');
};

# A PATTERN WITH METACHARACTERS must survive as a pattern, not as escaped text.
subtest 'patterns are not mangled' => sub {
    round_trips('my $s = "a.c"; print(($s =~ /a\.c/) ? "y\n" : "n\n");', 'escaped dot');
    round_trips('my $s = "a1c"; print(($s =~ /a\dc/) ? "y\n" : "n\n");', 'char class');
    round_trips('my $s = "aaa"; print(($s =~ /^a+$/) ? "y\n" : "n\n");', 'anchors');
};

subtest 'substitution' => sub {
    round_trips('my $s = "aaa"; $s =~ s/a/b/; print "$s\n";',  's///');
    round_trips('my $s = "aaa"; $s =~ s/a/b/g; print "$s\n";', 's///g');
    # A COUNTED s/// REFUSES when the producer folded its subject to a value.
    # The destructive form needs an lvalue, and the graph names a Constant --
    # so the emitter has nothing to substitute into. Spelling around it with a
    # temporary would emit a program modifying a DIFFERENT variable, and
    # whether the original changes is exactly what separates s/// from s///r.
    my $d = SoN::Deparse->new;
    my $data = graph_of('my $s = "aaa"; my $n = ($s =~ s/a/b/g); print "$n\n";');
    ok $data, 'the counted s/// program translates' or return;
    is $d->render($data), undef, 'a counted s/// over a folded subject refuses';
    like $d->gap, qr/no lvalue to modify/, '... naming what is missing';
};

# A CHAIN OF COUNTED SUBSTITUTIONS NEEDS THE VARIABLE, not the previous
# substitution's value. SSA threads each s/// to the one before it, which is
# the right graph: the second substitution observes the first. But a
# DESTRUCTIVE s/// needs an LVALUE, and `(... =~ s{}{}r) =~ s{}{}` is a
# compile error -- "Can't modify substitution (s///) in substitution (s///)".
#
# comp/redef.t is this shape, twenty times over: every `ok N, $warn =~ s/.../`
# substitutes into the same package scalar and reads the count.
subtest 'a chain of counted substitutions' => sub {
    round_trips(<<'SRC', 'two counted s/// on one variable');
$main::w = "aXbY";
my $a = ($main::w =~ s/X//) ? "1\n" : "0\n";
my $b = ($main::w =~ s/Y//) ? "1\n" : "0\n";
print $a, $b, "$main::w\n";
SRC
};

done_testing;
