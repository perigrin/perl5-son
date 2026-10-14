# ABOUTME: An if/else whose every arm returns ends the path it is on: nothing runs after
# ABOUTME: it, and each arm's return is its own edge to the function exit (chalk's Context).

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


round_trips(q{sub f { my $x = shift; if ($x eq "a") { print "a"; return "A" } else { print "c"; return "C" } } print f($_) for qw(a c); print "\n";},
    'both arms print and return');
round_trips(q{sub f { my $x = shift; if ($x eq "a") { print "a"; return "A" } elsif ($x eq "b") { return "B" } else { print "c"; return "C" } } print f($_) for qw(a b c); print "\n";},
    'every arm of an elsif chain returns');
round_trips(q{my @r; sub f { my $x = shift; push @r, "in"; if ($x > 1) { push @r, $x; return $x * 2 } else { push @r, "low"; return 0 } } print f(1), f(3), " @r\n";},
    'both arms push and return, after an effect');
round_trips(q{sub f { my $x = shift; if ($x eq "a") { if ($x ne "b") { print "x"; return 1 } else { print "y"; return 2 } } return 3 } print f("a"), f("q"), "\n";},
    'a nested if/else whose arms both return, in an arm');

# No effect in either arm: the If is built for the returns alone (it was
# not, and three edges hung off one control).
round_trips(q{sub f { my $x = shift; if ($x eq "a") { return "A" } else { return "C" } } print f($_) for qw(a c); print "\n";},
    'both arms only return');
round_trips(q{sub f { my $x = shift; if ($x eq "a") { return "A" } elsif ($x eq "b") { return "B" } else { return "C" } } print f($_) for qw(a b c); print "\n";},
    'every arm of an elsif chain only returns');
round_trips(q{sub f { $_[0] ? (return 1) : (return 2) } print f(1), f(0), "\n";},
    'a ternary whose arms both return');
round_trips(q{sub f { my $x = shift; my $r = $x ? do { print "a"; return 1 } : do { print "b"; return 2 }; $r } print f(1), f(0), "\n";},
    'a consumed ternary whose arms both print and return');

# In a loop body there is no fall-through left to carry to the latch, and
# the body walk has no dead state to stop on: refused by name.
{
    my $data = graph_of(q{sub f { for my $i (1..3) { if ($i==2) { print "a"; return 1 } else { print "b"; return 2 } } } print f(), "\n";});
    like producer_stderr(), qr/GAP: an if\/else in a loop body whose arms all leave, none by `next`, is not yet lowered/,
        'an if/else in a loop body whose arms both return refuses by name';
}

done_testing;
