# ABOUTME: A `return` inside a block eval leaves the EVAL, with its value: the eval's
# ABOUTME: join takes one way in per return, and execution goes on after the eval.

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
    is producer_stderr(), '', "$name: the producer says nothing";
    return fail "$name: translates" unless $data;
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
}

round_trips(q{sub f { my $x = shift; my $w = eval { return "none" unless $x; "got $x" }; "<$w>" } print f(1), f(0), "\n";},
    'a guarded return');
round_trips(q{sub f { my $x = shift; my $w = eval { my $y = $x or return ""; "y=$y" } || "no"; $w } print f(2), " ", f(0), "\n";},
    'an `or return` (Carp::caller_info)');
round_trips(q{sub f { my $c = shift; if ($c) { my $w = eval { return "r" unless $c > 1; "big" }; return $w } 0 } print f(1), f(2), f(0), "\n";},
    'in an if arm');
round_trips(q{sub f { my $n = 0; my $w = eval { for my $i (1 .. 5) { $n++; return "at $i" if $i == 3 } "end" }; "$w $n" } print f(), "\n";},
    'from a loop in the eval');
round_trips(q{sub f { my $w = eval { return "early" if $_[0]; die "x\n" }; defined $w ? $w : "died: $@" } print f(1), " ", f(0);},
    'a return and a die');

round_trips(q{sub f { my $w = eval { return 5 }; $w + 1 } print f(), "\n";}, 'every path returns');
round_trips(q{sub f { my $w = eval { if ($_[0]) { return "a" } else { return "b" } }; $w } print f(1), f(0), "\n";}, 'both arms return');


round_trips(q{sub f { my ($c, $p) = @_; my $w = eval { return unless defined $p; return if $p eq "x"; "<$p>" } || "none"; $w } print f(1, "a"), f(1, undef), f(1, "x"), "\n";}, 'a bare return in a scalar eval (Carp::caller_info)');

# A RETURN LEAVES ONLY THE EVAL'S SCOPE: a `local` outside it is still in
# force after (restored at its own scope's end, not at the return).
round_trips(q{our $g = "outer"; sub f { my $c = shift; if ($c) { local $g = "inner"; my $w = eval { return "r" if $c > 1; "v" }; return "$w $g" } "none" } print f(1), " ", f(2), " ", f(0), " $g\n";}, 'under a local outside the eval');

done_testing;
