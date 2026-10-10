# ABOUTME: A compound assignment through a scalar reference (`$$r += 2`) stores its
# ABOUTME: result back through the reference rather than computing it and dropping it.

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


round_trips('my $v=1; my $r = \$v; $$r += 2; print "$v\n";',
    'top level: += through a ref to a lexical');
round_trips('sub f { my $r = shift; $$r *= 3; return } my $v=2; f(\$v); print "$v\n";',
    'in a sub: *= through a ref argument');
round_trips('our $g=4; my $r = \$g; $$r -= 1; print "$g\n";',
    'a ref to a package scalar');
round_trips('my $v=1; my @rs = (\$v); ${$rs[0]} += 4; print "$v\n";',
    'a ref fetched from an array element');
round_trips('my $v=0; my $r = \$v; $$r += $_ for 1..4; print "$v\n";',
    'in a loop body');
round_trips('my $v=1; my $r = \$v; my $w = ($$r += 5); print "$v $w\n";',
    'the compound in scalar value context');
round_trips('my $v=1; my $r = \$v; $$r += 2; $$r **= 2; print "$v ", $$r, "\n";',
    'two compounds in sequence, then a read through the ref');
round_trips('my $v=1; my $r = \$v; $$r++; print "$v\n";',
    'a postfix increment through a ref');
round_trips('my $v=1; my $r = \$v; my $w = ++$$r; my $u = $$r--; print "$v $w $u\n";',
    'pre and post forms in value context');
round_trips('sub f { my $r = shift; $$r++ for 1..3; return } my $v=2; f(\$v); print "$v\n";',
    'an increment through a ref argument in a loop');

# `.=` and `||=` through a ref are separate shapes (multiconcat, a
# short-circuit over sassign); they refuse rather than drop the store.
sub refuses ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, $name;
}
refuses('my $v="a"; my $r = \$v; $$r .= "x"; print "$v\n";',
    qr/GAP: multiconcat storing into a stacked destination that is not a package scalar/,
    '.= through a ref refuses');
refuses('my $v=0; my $r = \$v; $$r ||= 4; print "$v\n";',
    qr/GAP: `\|\|=` into something other than a lexical scalar/,
    '||= through a ref refuses');

done_testing;
