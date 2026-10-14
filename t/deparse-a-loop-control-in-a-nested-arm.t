# ABOUTME: A `next` or `last` in a nested arm -- the final else of an elsif chain, an
# ABOUTME: if inside an arm -- leaves the enclosing loop, and the statements after it skip.

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


# The final else of an if/elsif/else is a cond_expr inside the outer one's
# false arm; its `next` / `last` must reach the loop (chalk's
# StructPromotion::analyze, _collect_positional_arg_reads, Actions::Subscript).
round_trips(q{my $s=""; for my $i (1..4) { my $v; if ($i==1) { $v="a" } elsif ($i==2) { $v="b" } else { next } $s.=$v } print "[$s]\n";},
    'else { next } at the end of an elsif chain');
round_trips(q{my $s=""; for my $i (1..4) { my $v; if ($i==1) { $v="a" } elsif ($i==2) { $v="b" } else { last } $s.=$v } print "[$s]\n";},
    'else { last } at the end of an elsif chain');
round_trips(q{my $s=""; for my $i (1..4) { my $v; if ($i!=3) { $v=$i } elsif ($i==3) { next } $s.="<".($v//"u").">" } print "[$s]\n";},
    'elsif { next } with no else skips the rest of the body');
round_trips(q{my $s=""; for my $i (1..4) { if ($i==1) { $s.="a" } elsif ($i==2) { next } $s.=$i } print "[$s]\n";},
    'elsif { next } before a statement: the statement is skipped');
round_trips(q{my $s=""; for my $i (1..5) { if ($i==1) { $s.="a" } elsif ($i==3) { last } $s.=$i } print "[$s]\n";},
    'elsif { last } before a statement');

# An if inside an arm whose body ends in `last` (chalk's
# _fixup_ternary_assignment: `elsif (C) { $d--; if ($d == 0) { $e = $p; last } }`).
round_trips(q{my ($d,$e,$p)=(0,-1,0); for my $c (split //, "((a)b)c") { if ($c eq "(") { $d++ } elsif ($c eq ")") { $d--; if ($d == 0) { $e = $p; last } } $p++ } print "$e $p\n";},
    'last inside an if inside an elsif arm');
round_trips(q{my $n=0; my $i=0; while ($i < 8) { $i++; if ($i % 2) { if ($i > 4) { last } } else { $n += $i } } print "$n $i\n";},
    'last inside an if inside an if arm, while loop');
round_trips(q{my $n=0; for my $i (1..8) { if ($i % 2) { if ($i > 4) { next } $n += 100 } else { $n += $i } } print "$n\n";},
    'next inside an if inside an if arm, then a statement in the arm');

done_testing;
