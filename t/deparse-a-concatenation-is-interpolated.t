# ABOUTME: A concatenation of string constants and plain scalars is emitted as the
# ABOUTME: interpolated string the source wrote -- "    $code\n" -- not as a `.` chain.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

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

sub round_trips ($src, $name, $spelled = undef) {
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
    like $out, $spelled, "$name: spelled as the source" if $spelled;
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# perl COMPILES "    $code\n" TO ONE multiconcat, and the emission spelled it
# `(("    " . $code) . "\n")`: the same string to perl. chalk reads lib/ as
# source and generates Perl from it, and its generator mangles the `.` chain
# with the "\n" constant -- XS::AST::Statement's emit() came back with a
# trailing indent (perl-target-perl-tier-b.t). The source's form round-trips.
round_trips(<<'SRC', 'a string around a scalar', qr/return "    \$code\\n";/);
use v5.42; sub emit ($code) { return "    $code\n" } print emit("RETVAL = sv;");
SRC

round_trips(<<'SRC', 'two scalars and text', qr/"MODULE = \$m  PACKAGE = \$p\\n"/);
use v5.42; sub hdr ($m, $p) { return "MODULE = $m  PACKAGE = $p\n" } print hdr("Foo", "Bar");
SRC

round_trips(<<'SRC', 'sigils and quotes in the text are escaped');
use v5.42; sub q1 ($x) { return "cost: \$" . $x . " \@ \"$x\" \\ end" } print q1(5), "\n";
SRC

# TEXT THAT WOULD EXTEND THE VARIABLE keeps the `.` chain: `$x[0]` would be an
# element, `$x::y` a package variable, `$x->[0]` a dereference, `$x's` the
# old package separator.
round_trips(<<'SRC', 'text that would extend a variable');
use v5.42; sub f ($x) { return $x . "[0]" . $x . "::y" . $x . "->[1]" . $x . "'s" } print f("a"), "\n";
SRC

done_testing;
