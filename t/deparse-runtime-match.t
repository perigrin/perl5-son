# ABOUTME: A Match is `=~` with a RUNTIME pattern -- the pattern is an input, not a field.
# ABOUTME: Interpolating it back is what makes it a pattern again; the group keeps its extent.

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

# A RUNTIME PATTERN IS AN INPUT. `RegexMatch` carries its pattern as a string
# field; `Match` is the binop that takes a computed one -- measured on
# `$s =~ /${p}c/` where $p is not foldable:
#
#     11 Concat  in=[9, 10]  stamp=Str
#     12 Match   in=[2, 11]  stamp=Boolean
#
# so input 1 is the pattern VALUE, and interpolating it back is what turns it
# into a pattern again: perl compiles the string.
#
# THE VARIABLE MUST NOT BE FOLDABLE, or the producer resolves it at
# translation time and builds a RegexMatch with a string field instead -- a
# correct graph, and no test of this path. @ARGV is what forces it.
subtest 'a runtime pattern round-trips' => sub {
    round_trips(<<'SRC', 'a computed pattern that matches');
my $p = @ARGV ? $ARGV[0] : "b";
my $s = "abc";
print(($s =~ /${p}c/) ? "y\n" : "n\n");
SRC

    round_trips(<<'SRC', 'a computed pattern that does not');
my $p = @ARGV ? $ARGV[0] : "z";
my $s = "abc";
print(($s =~ /${p}c/) ? "y\n" : "n\n");
SRC
};

# THE GROUP IS NOT DECORATION. A value like `a|z` binds past its own extent
# without one: `/${p}c/` would let the alternation swallow the `c`, matching
# something the source never wrote. Only this case can tell a correct grouping
# from a missing one.
subtest 'an alternation keeps its extent' => sub {
    round_trips(<<'SRC', 'alternation in a runtime pattern');
my $p = @ARGV ? $ARGV[0] : "a|z";
my $s = "zq";
print(($s =~ /${p}c/) ? "y\n" : "n\n");
SRC
};

# A LITERAL PATTERN IS A DIFFERENT NODE and must not regress -- it is the
# common case, and it carries its pattern as a field.
subtest 'a literal pattern still matches' => sub {
    round_trips(<<'SRC', 'literal pattern');
my $s = "abc";
print(($s =~ /bc/) ? "y\n" : "n\n");
SRC
};

done_testing;
