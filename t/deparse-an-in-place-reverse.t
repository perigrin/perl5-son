# ABOUTME: `@a = reverse @a` is an assign perl folds into an in-place reverse; the array
# ABOUTME: is rebound to the reversed list where the assign stands, or refused by name.

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


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


sub refuses ($src, $why, $name) {
    my $data = graph_of($src);
    my $err  = producer_stderr();
    my $d    = SoN::Deparse->new;
    my $out  = $data ? $d->render($data) : undef;
    ok !defined $out, "$name: refuses" or diag $out;
    like $err . ($d->gap // ''), $why, "$name: names its cause";
}

# perl nulls the aassign and flags the reverse INPLACE, so the reversed list
# reached nothing and @a kept its order -- a silent wrong answer at top level,
# in a sub, in a loop body and in an arm. It is rebound as the in-place sort
# is.
my @cases = (
    [ q{my @k = (1, 2, 3); @k = reverse @k; print "@k\n";}, 'at top level' ],
    [ q{sub g { my @k = @_; @k = reverse @k; print "@k\n" } g(1, 2);}, 'in a sub' ],
    [ q{my @k = (1, 2, 3); @k = reverse @k; push @k, 4; print "@k ", scalar(@k), "\n";},
      'then mutated and counted' ],
    [ q{sub g { my ($r, @k) = @_; @k = reverse @k; print "$r @k\n" } g(0, 1, 2);},
      'of an array a list assign bound, straight line' ],
    # IN A LOOP BODY the floating literal was placed above the loop, reading
    # the index before it was declared; it is pinned where the assign stands.
    [ q{sub g { my @o; for my $n (@_) { my @k = @$n; @k = reverse @k; push @o, @k } print "@o\n" } g([1, 2], [3, 4]);},
      'in a loop body' ],
    [ q{sub g { my ($r, $x) = @_; my @k = @$x; if (!$r) { @k = reverse @k } print "@k\n" } g(0, [1, 2]); g(1, [1, 2]);},
      'in an if arm' ],
    [ q{sub g { my ($r, $x) = @_; my @k = @$x; @k = reverse @k unless $r; print "@k\n" } g(0, [1, 2]); g(1, [1, 2]);},
      'under a modifier' ],
    # chalk's Context::walk_all and walk_acc: under a modifier in a loop
    # body, behind an arm that leaves by `next`. Floating, the reversed list
    # was placed above that arm's guard and read `->@*` of a leaf.
    [ q{sub wa { my ($root, %opts) = @_; my $reverse = $opts{reverse}; my @r; my @stack = ($root); while (@stack) { my $node = pop @stack; my $f = $node->{v}; if (defined $f) { push @r, $f; next; } my @kids = @{ $node->{kids} }; @kids = reverse @kids unless $reverse; push @stack, @kids; } return @r; } my $t = { kids => [ { v => 1 }, { kids => [ { v => 5 }, { v => 9 } ] } ] }; print join(",", wa($t)), "|", join(",", wa($t, reverse => 1)), "\n";},
      'Context::walk_all' ],
    [ q{sub wc { my ($root, $acc, %opts) = @_; my $reverse = $opts{reverse}; my @stack = ($root); while (@stack) { my $node = pop @stack; my $f = $node->{v}; if (defined $f) { $acc = $acc . $f; next; } my @kids = @{ $node->{kids} }; @kids = reverse @kids unless $reverse; push @stack, @kids; } return $acc; } my $t = { kids => [ { v => 1 }, { kids => [ { v => 5 }, { v => 9 } ] } ] }; print wc($t, ""), "|", wc($t, "", reverse => 1), "\n";},
      'Context::walk_acc' ],
    # A REVERSE INTO ANOTHER ARRAY IS NOT IN PLACE, and was never dropped.
    [ q{my @k = (1, 2, 3); my @j = reverse @k; print "@j|@k\n";}, 'into another array' ],
);
for my $c (@cases) {
    round_trips(@$c);
    emits_quietly(@$c);
}

# AN ARRAY A LIST ASSIGN LEFT UNBOUND -- `my ($r, @k) = @_` -- in a loop
# body or an arm: the arm's literal declared a second `my @k` there and left
# the outer one undeclared, which is not a program.
my $unbound = qr/GAP: an in-place reverse \(`\@a = reverse \@a`\) in a loop body or an arm, of an array a list assign left unbound/;
refuses(q{sub g { my ($r, @k) = @_; @k = reverse @k unless $r; print "@k\n" } g(0, 1, 2); g(1, 1, 2);},
    $unbound, 'an unbound array under a modifier');
refuses(q{sub g { my ($r, @k) = @_; if (!$r) { @k = reverse @k } print "@k\n" } g(0, 1, 2); g(1, 1, 2);},
    $unbound, 'an unbound array in an if arm');

# STORAGE OTHERS CAN SEE keeps the in-place sort's refusal.
refuses(q{our @k = (1, 2); @k = reverse @k; print "@k\n";},
    qr/GAP: an in-place reverse of an array other than a plain lexical/,
    'a package array');

done_testing;
