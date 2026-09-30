# ABOUTME: A builtin:: function the producer records by its op name -- blessed,
# ABOUTME: refaddr, reftype -- is spelled builtin::NAME, which is the sub perl defines.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
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

# "the builtin op `refaddr` has no Perl spelling" refused 3 of chalk's lib/
# modules, and `blessed` 1: each is an op named for its builtin:: function.
round_trips(<<'SRC', 'blessed');
use v5.42; my $o = bless {}, 'K'; my $r = {};
print builtin::blessed($o), "|", (builtin::blessed($r) // "undef"), "\n";
SRC

round_trips(<<'SRC', 'reftype');
use v5.42; my $o = bless [], 'K';
print builtin::reftype($o), "\n";
SRC

round_trips(<<'SRC', 'floor and ceil');
use v5.42; my $x = 2.5; print builtin::floor($x), " ", builtin::ceil($x), "\n";
SRC

round_trips(<<'SRC', 'refaddr of a reference is a number');
use v5.42; my $o = bless {}, 'K';
print builtin::refaddr($o) > 0 ? "addr" : "none", "\n";
SRC

# ONE `{}` READ TWICE IS EMITTED TWICE -- `builtin::refaddr({}) ==
# builtin::refaddr({})` -- two hashes where the source has one. Not about
# builtins: `my $r = []; my $s = $r; push @$s, 1; scalar(@$r)` prints 0
# where perl prints 1. An anonymous constructor is an allocation with no
# place on the chain; see the round-trip plan's defect list.
{
    my $todo = todo 'an anonymous aggregate read twice is constructed twice';
    round_trips(<<'SRC', 'refaddr names the same referent twice');
use v5.42; my $r = {}; my $s = $r;
print builtin::refaddr($r) == builtin::refaddr($s) ? "same" : "diff", "\n";
SRC
}

done_testing;
