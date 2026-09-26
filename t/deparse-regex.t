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
    # A COUNTED s/// ON A LEXICAL ROUND-TRIPS. It used to refuse, and the
    # refusal was honest: the producer folded the subject to its value, the
    # destructive form needs an lvalue, and the graph named a Constant.
    #
    # The slot is DEMOTED now -- `_address_taken` marks a destructive s///'s
    # targ the same way `\$x` does -- so the subject is the pad slot, its
    # declaration survives, and the substitution is emitted ONCE with the count
    # bound to a temporary:
    #
    #     my $s = "aaa";
    #     my $subst7 = ($s =~ s{a}{b}g);
    #     print join('', ($subst7 . "\n"));
    #
    # Asserted as a ROUND TRIP rather than a rendering, because the two things
    # the old refusal protected -- that the ORIGINAL changes, and that the
    # count is the count -- are only visible by running it. See
    # docs/plans/2026-09-26-a-destructive-subst-on-a-lexical.md.
    round_trips('my $s = "aaa"; my $n = ($s =~ s/a/b/g); print "$n $s\n";',
        'a counted s/// on a lexical');
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

# A COMPUTED PATTERN MUST SURVIVE THE ROUND TRIP. The graph holds the pattern
# as a VALUE, and the emitted program has to turn it back into a pattern --
# interpolating it is what does that, since perl compiles the string.
#
# THE GROUP IS NOT DECORATION. A value like `a|z` binds past its own extent
# without one: `s/$P b$/` would let the alternation swallow ` b$`, matching
# something the source never wrote. Both cases below are checked because only
# the alternation one can tell a correct grouping from a missing one.
subtest 'a computed pattern round-trips' => sub {
    round_trips(<<'SRC', 'a computed pattern');
my $P = @ARGV ? $ARGV[0] : "a";
my $s = "a b";
$s =~ s/$P b$/X/;
print "$s\n";
SRC

    round_trips(<<'SRC', 'an alternation keeps its extent');
my $P = @ARGV ? $ARGV[0] : "a|z";
my $s = "a bz";
$s =~ s/$P b/X/;
print "$s\n";
SRC
};

done_testing;
