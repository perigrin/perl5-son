# ABOUTME: ref(), $1 and qx// render as themselves; each is a plain expression.
# ABOUTME: All three come from the corpus -- comp/term.t, comp/utf.t and base/term.t.

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

# `ref` READS A REFERENCE'S TYPE. A unary node whose op_str is already `ref`.
# The check is the ANSWER, not that something rendered: `ref` over the wrong
# operand still returns a plausible type name.
subtest 'ref() round-trips' => sub {
    # NO CODE REF HERE: `sub { 1 }` builds an AnonSub, a separate refusal,
    # and a case that fails for two reasons proves neither.
    round_trips(<<'SRC', 'each reference kind');
my $a = [1,2];
my $h = {k=>1};
my $s = \"x";
print ref($a), " ", ref($h), " ", ref($s), "\n";
SRC

    round_trips(<<'SRC', 'a non-reference is the empty string');
my $p = "plain";
print "[", ref($p), "]\n";
SRC
};

# A CAPTURE READS ONE GROUP OF ITS MATCH. inputs[0] is the match node and the
# `n` field is the group number -- so a rule that ignored `n` would return the
# same group for $1 and $2.
subtest 'a regex capture round-trips' => sub {
    round_trips(<<'SRC', 'two groups, read in order');
my $s = "ab-cd";
if ($s =~ /(\w+)-(\w+)/) { print "1=$1 2=$2\n" } else { print "no\n" }
SRC

    round_trips(<<'SRC', 'and out of order, so a shared rule shows');
my $s = "ab-cd";
if ($s =~ /(\w+)-(\w+)/) { print "2=$2 1=$1\n" } else { print "no\n" }
SRC
};

# BACKTICKS RUN A COMMAND AND CAPTURE ITS OUTPUT. `echo` is the portable
# choice here; the value is what matters, not the shell.
subtest 'a backtick expression round-trips' => sub {
    round_trips(<<'SRC', 'qx captures output');
my $out = `echo hello`;
print "[$out]";
SRC
};

done_testing;
