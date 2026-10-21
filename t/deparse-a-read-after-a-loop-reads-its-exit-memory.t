# ABOUTME: A foreach whose body moves memory with no header Phi for it: a read after
# ABOUTME: the loop is placed after the loop, not inside the last pass.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
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

# A DEMOTED SCALAR READ AFTER THE LOOP took the memory of the body's last
# branch join -- the loop had no header Phi for it -- and the `my @walk =
# ($ctx)` that read it was spelled inside the body, out of scope for the
# loop after it (chalk's Perl::Actions::Block, `Global symbol "@walk"`).
round_trips(<<'SRC', 'a list built from a demoted scalar after a loop whose branch pushes');
package N { sub new { my ($c, $n, @k) = @_; bless { n => $n, k => [@k] }, $c } sub kids { $_[0]{k} } sub n { $_[0]{n} } }
sub vals { ({ a => 1 }, [2], { b => 1 }) }
sub f {
    my ($ctx) = @_;
    my @stmts;
    for my $val (vals($ctx)) {
        if (ref($val) eq 'ARRAY') {
        } elsif (ref($val) eq 'HASH' && exists $val->{a}) {
            push @stmts, $val;
        }
    }
    my @walk = ($ctx);
    my $s = "";
    while (my $node = pop @walk) {
        $s .= $node->n;
        push @walk, $node->kids->@*;
    }
    return $s . scalar(@stmts);
}
print f(N->new("a", N->new("b"))), "\n";
SRC
round_trips(q{sub g { 1 } sub f { my ($x) = @_; my @s; g($x); for my $v (1, 2) { push @s, $v if $v > 1 } my @w = ($x); return "@w|@s" } print f(7), "\n";},
    'a list over a demoted scalar after a loop with a guarded push');

done_testing;
