# ABOUTME: A foreach over a lexical array whose binding carries no stamp -- declared bare
# ABOUTME: and pushed to, or captured from file scope -- or over a $_-iterated deref, round trips.

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


sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

round_trips(q{sub f { my @a; push @a, 1, 2; my $s = 0; for my $x (@a) { $s += $x } $s } print f(), "\n";},
    'a bare-declared array filled by push');
round_trips(q{my @F = qw(a b c); sub f { my $s = ""; for my $x (@F) { $s .= $x } return $s } print f(), "\n";},
    'a file-scoped array captured by a sub');
round_trips(q{sub f { my @a; push @a, 1, 2; for my $x (@a) { $x *= 10 } "@a" } print f(), "\n";},
    'an iterator write reaches a bare-declared array');
round_trips(q{sub f { my @a; push @a, 3, 4; my $s = ""; for (@a) { $s .= $_ } $s } print f(), "\n";},
    'an implicit $_ over a bare-declared array');
round_trips(q{use v5.42; sub c($k) { my %s; $s{$_} = 1 for $k->@*; join ",", sort keys %s } print c([2,1]), "\n";},
    'an implicit $_ over a dereferenced parameter');
round_trips(q{sub f { my $r = $_[0]; my $t = ""; for (@$r) { $t .= $_ } $t } print f([7,8]), "\n";},
    'an implicit $_ over @$r');

# A MERGED BINDING OF UNSTAMPED ARRAYS -- `@l = @n` in one arm -- is a Phi with
# no stamp. Taking the array path for it renders wrong (measured: `02` for
# `aabbab`, and "Can't use an array as a reference"), so it refuses by name.
refuses(q{sub f { my @l; push @l, "a", "b"; if ($_[0]) { my @n; for my $x (@l) { push @n, $x, $x } @l = @n; } my $s=""; for my $y (@l) { $s .= $y } $s } print f(1), f(0), "\n";},
    qr/GAP: a foreach over a merged binding of unstamped arrays/, 'a foreach over an array reassigned in one arm');

done_testing;
