# ABOUTME: %ENV reads, the \ operator, and an assignment used as a value.
# ABOUTME: All three come from the corpus -- comp/require.t, comp/fold.t, base/lex.t.

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

# %ENV IS READ THROUGH A NODE WITH THE KEY ON IT, because the key is a
# compile-time literal and env writes are not modelled.
subtest 'an %ENV read' => sub {
    round_trips(<<'SRC', 'a key that is never set');
print defined($ENV{SON_DEFINITELY_UNSET_XYZZY}) ? "set\n" : "unset\n";
SRC
};

# `\` MAKES A REFERENCE, and the check is that it still points at the same
# storage: a reference to a COPY still prints a plausible value.
subtest 'the \ operator' => sub {
    round_trips(<<'SRC', 'a scalar ref reflects later writes');
my $x = 1;
my $r = \$x;
$x = 9;
print "$$r\n";
SRC

    round_trips(<<'SRC', 'and a write through it is visible');
my $x = 1;
my $r = \$x;
$$r = 7;
print "$x\n";
SRC
};

# AN ASSIGNMENT IS A VALUE, and in Perl it is the TARGET as an lvalue --
# measured on base/lex.t, `Match(27) in=[9, 26]` where 9 is an Assign, which is
# the `($x = "...") =~ /.../` shape.
#
# THE ASSIGNMENT MUST STILL HAPPEN. Rendering only the value would match the
# right string and leave $x unset, which prints plausibly and is wrong.
subtest 'an assignment used as a value' => sub {
    round_trips(<<'SRC', 'match against a fresh assignment');
my $x;
print(($x = "abc") =~ /b/ ? "y\n" : "n\n");
print "[$x]\n";
SRC
};

done_testing;
