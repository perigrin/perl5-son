# ABOUTME: A match, a pos() and a chain of s/// on one variable each happen at
# ABOUTME: the point written, against the variable as it is there.

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
    my $j = qx($^X -Ilib -MO=-q,SoN,json,package=main $f 2>$dir/err);
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

# A MATCH FLOATED TO ITS USE. `$hit` was spelled `($s =~ m{abc})` at the
# print, after the s/// had rewritten $s. Corpus 010.
round_trips(<<'SRC', 'a match before a rewrite of its subject');
my $s = $ENV{X} // "abcd";
my $hit = $s =~ /abc/;
$s =~ s{a}{z};
print "[$hit] $s\n";
SRC

# A CHAIN OF s/// ON ONE VARIABLE. Each rebound the slot to its own result,
# so the next took that as its subject, unpinned, and was dropped: only the
# first survived. Corpus 010.
round_trips(<<'SRC', 'three substitutions in a row');
my $s = $ENV{X} // "abcd";
$s =~ s{a}{z};
$s =~ s/c/y/;
$s =~ s#d#w#;
print "$s\n";
SRC

# pos() IS STATE ON THE VARIABLE, set by a /g match and read or written by
# pos(). The subject folded to a constant, which has no pos. Positions 2
# and 5 differ on purpose: equal ones let a mis-ordered read pass. Corpus 189.
round_trips(<<'SRC', 'pos after successive /g matches, and a reset');
my $s = $ENV{X} // "abcabc";
$s =~ m/b/g;
my $first = pos($s);
$s =~ m/b/g;
my $second = pos($s);
pos($s) = 0;
$s =~ m/b/g;
print "$first $second ", pos($s), "\n";
SRC

# A PATTERN WITH UNBALANCED BRACES CANNOT GO BETWEEN `m{` AND `}`. Once the
# match above was pinned rather than dropped, corpus 098 emitted
# `m{b(?{ $k = length("}}}") })}`, which perl reads as code after the first
# `}`. The emission must at least compile.
subtest 'an unbalanced-brace pattern compiles' => sub {
    my $data = graph_of(<<'SRC');
my $s = $ENV{X} // "abc";
my $r = \$s;
my $hit = $s =~ /b}}/;
print $hit ? "y" : "n", "\n";
SRC
    my $out = SoN::Deparse->new->render($data);
    ok defined $out, 'renders' or return;
    is run_perl($out), run_perl(qq{print "n\\n";\n}), 'compiles and runs';
};

done_testing;
