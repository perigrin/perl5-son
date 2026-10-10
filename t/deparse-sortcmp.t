# ABOUTME: A sort's comparator -- folded flags, an inline block, or a named sub -- is
# ABOUTME: rendered from the Call's fields, so a non-default order round-trips as written.
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

# THE WIRE CARRIED THE ORDER AND THE RENDERER DROPPED IT: every sort came out
# `sort(LIST)`, string ascending -- `sort { $b <=> $a } (3,1,2)` printed 1 2 3.
my @cases = (
    [ q{my @a = sort { $b <=> $a } (3,1,2); print "@a\n";},
      'a folded numeric descending sort' ],
    [ q{my @a = sort { $a <=> $b } (10,9,100); print "@a\n";},
      'a folded numeric ascending sort is not a string sort' ],
    [ q{print join(",", sort { $b cmp $a } qw(b c a)), "\n";},
      'a folded string descending sort' ],
    [ q{my @a = reverse sort { $a <=> $b } (10,9,100); print "@a\n";},
      'reverse of a numeric sort' ],
    [ q{print join(",", sort { lc($b) cmp lc($a) } qw(a C b)), "\n";},
      'an inline block comparator' ],
    [ q{my $r = [{i => "b"}, {i => "a"}, {i => "c"}]; print join(",", map { $_->{i} } sort { $b->{i} cmp $a->{i} } @$r), "\n";},
      'a block comparing elements through a reference' ],
    [ q{sub byd { $b <=> $a } my @a = sort byd (3,1,10,2); print "@a\n";},
      'a named comparator sub' ],
    [ q{sub f { my @s = sort { $b <=> $a } @_; return "@s" } for my $n (1, 2) { print f($n, 10, 3), "\n" }},
      'a sort in a sub, called from a loop' ],
    [ q{our @g = (3,1,2); my %h = (k => [5,9,7]); print join(",", sort { $b <=> $a } @g), "|", join(",", sort { $b <=> $a } @{$h{k}}), "\n";},
      'a package array and a hash element reference' ],
    [ q{package P; sub byd { $b <=> $a } sub f { join ",", sort byd @_ } package main; print P::f(3, 1, 10), "\n";},
      'a named comparator in another package' ],
    [ q{package P; sub f { join ",", sort { lc($b) cmp lc($a) } @_ } package main; print P::f(qw(a C b)), "\n";},
      'an inline block inside a sub of another package' ],
    [ q{package P; print join(",", sort { lc($b) cmp lc($a) } qw(a C b)), "\n";},
      'an inline block in the program under a package statement' ],
);

round_trips(@$_) for @cases;

# A COMPARATOR THE GRAPH DOES NOT CONTAIN CANNOT BE CALLED, and falling back
# to `sort(LIST)` would order by something the program never asked for.
subtest 'a comparator body missing from the graph refuses' => sub {
    my $data = graph_of(q{print join(",", sort { lc($b) cmp lc($a) } qw(a C b)), "\n";});
    ok $data, 'it translates' or return;
    my ($call) = grep { ($_->{fields}{sort_cmp_body} // '') ne '' }
        $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    ok $call, 'the sort names its comparator' or return;
    delete $data->{methods}{ $call->{fields}{sort_cmp_body} };
    my $d = SoN::Deparse->new;
    is $d->render($data), undef, 'it does not render';
    like $d->gap, qr/GAP: a sort comparator `[^`]+`, which is not in the graph/, 'and names why';
};

# A COMPARATOR BLOCK SHARES ITS ENCLOSING SUB'S PAD but is drained as a graph
# of its own, so a variable from outside the block has no edge into it --
# measured, `sort { ($a % $i) <=> ($b % $i) }` in a loop died "Illegal modulus
# zero" once the body was called. The body refuses, and so does the sort.
sub body_refuses ($src, $gap, $name) {
    my $data = graph_of($src);
    like producer_stderr(), qr/^B::SoN: skipped \S+__SORTCMP__:\d+: \Q$gap\E$/m,
        "$name: the comparator body refuses";
    ok $data, "$name: the enclosing graph still translates" or return;
    my $d = SoN::Deparse->new;
    is $d->render($data), undef, "$name: it does not render";
    like $d->gap // '', qr/\AGAP: a sort comparator `[^`]+`, which is not in the graph/,
        "$name: the sort names its missing comparator";
}

my $CAPTURE = 'is not yet lowered -- the body graph has no edge to that variable';

body_refuses(q{for my $i (1..2) { print join(",", sort { ($a % $i) <=> ($b % $i) or $a <=> $b } 4,3,2,1), "\n" }},
    "GAP: a sort comparator block that reads a lexical of its enclosing scope (\$i) $CAPTURE",
    'a loop variable');
body_refuses(q{my @k = (3, 1, 2); print join(",", sort { $k[$a] <=> $k[$b] } 0 .. 2), "\n";},
    "GAP: a sort comparator block that reads a lexical of its enclosing scope (\@k) $CAPTURE",
    'an outer array');
body_refuses(q{for (1, -1) { print join(",", sort { $_ * ($a <=> $b) } 1, 3, 2), "\n" }},
    'GAP: a sort comparator block that reads $_ is not yet lowered -- it is the enclosing topic, and the body graph has no edge to it',
    'the enclosing topic');

done_testing;
