# ABOUTME: A Subscript through a Ref-stamped expression must parenthesize the
# ABOUTME: reference, or perl parses `\@a->[0]` as a reference to `@a->[0]`.
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
    my $j = qx($^X -Ilib -MO=SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ( $data && $data->{methods}{'main::__PROGRAM__'} ) {
        fail "$name: translates";
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

# THE GRAPH IS CORRECT AND THE RENDERING IS NOT. Measured on
# `my @a=(10,20); my $s=\@a; print "$$s[0]"`:
#
#      4 ArrayLiteral Array
#      5 Ref          ArrayRef  in=[4]
#      8 Subscript    Scalar    in=[5,6,7]
#
# `Ref` over `ArrayLiteral` with a `Subscript` into it says exactly what perl
# did. The emission spelled it `\@a->[0]`, which perl reads as a reference TO
# `@a->[0]` and rejects: "Can't use an array as a reference". `(\@a)->[0]`
# is the same node rendered correctly.
#
# The `List` branch at Deparse.pm:358 already parenthesizes for this reason,
# with a comment about a deparse that spun for 28 hours. The Ref branch did
# not, so this is one trigger shared by three corpus cases (008, 094, 193 in
# pvm's conformance corpus).
round_trips( <<'SRC', 'an array-ref subscript through a taken reference' );
my @a = (10, 20);
my $s = \@a;
print "$$s[0] $$s[1]\n";
SRC

round_trips( <<'SRC', 'a hash-ref subscript through a taken reference' );
my %h = (k => 'v', j => 'w');
my $r = \%h;
print "$$r{k} $$r{j}\n";
SRC

# THE ARROW FORM must keep working -- it is the same node reached by a
# spelling that already parenthesized correctly.
round_trips( <<'SRC', 'the arrow spelling is undisturbed' );
my @a = (10, 20);
my $s = \@a;
print $s->[0], " ", $s->[1], "\n";
SRC

# AND A PLAIN ARRAY SUBSCRIPT must not gain parens it does not need.
round_trips( <<'SRC', 'a plain array element is unchanged' );
my @a = (10, 20);
print "$a[0] $a[1]\n";
SRC

done_testing;
