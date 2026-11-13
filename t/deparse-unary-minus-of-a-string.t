# ABOUTME: Unary minus is not numeric on a string: -"abc" is "-abc", -"+x" is "-x",
# ABOUTME: so its operand is not coerced to a number, and its result is no Num.

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

round_trips(q{sub f { my $x = shift; return - $x } print f(3), ",", f(-4), ",", f(2.5), ",", f("7"), ",", f("-2"), ",", f("abc"), ",", f("+q"), ",", f("-"), "\n";},
    'a value known only at run time');
round_trips(q{my $s = "abc"; my $t = -$s; print "$t\n";}, 'a string variable');

# THE WIRE: Negate's operand reaches it uncoerced, and a run-time value's
# negation is no Num (a consumer would read "-abc" as a number).
{
    my $d = graph_of(q{sub f { my $x = shift; return - $x } print f("abc"), "\n";});
    my $n = $d->{methods}{'main::f'}{nodes};
    my %n = map { ( $_->{id} => $_ ) } ( ref $n eq 'HASH' ? values %$n : @$n );
    my ($neg) = grep { $_->{op} eq 'Negate' } values %n;
    ok $neg, 'a Negate on the wire';
    my $in = $n{ $neg->{inputs}[0] };
    isnt $in->{op}, 'Coerce', 'its operand is not coerced';
    isnt $neg->{stamp}, 'Num', 'it is not stamped Num';
}
round_trips(q{my $n = 5; my $m = -$n; print $m + 1, "\n";}, 'a number');

done_testing;
