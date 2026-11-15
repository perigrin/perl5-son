# ABOUTME: `$$r .= "x"` -- perl's multiconcat appending into a scalar deref -- is a store through
# ABOUTME: the reference of its value read there and the strings, as `$$r .= $x`'s concat is.
use 5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub write_src ($src) {
    my $f = "$dir/p." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return $f;
}
sub run_perl ($src) {
    my $f = write_src($src);
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>&1); unlink $f; return $out;
}
sub wire ($src) {
    my $f = write_src($src);
    my $j = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    unlink $f;
    my $e = do { open my $fh, '<', "$dir/err"; local $/; <$fh> } // '';
    return ( scalar eval { JSON::PP->new->decode($j) }, $e );
}

# Before, B::SoN refused every one: "multiconcat storing into a stacked
# destination that is not a package scalar".
for my $case (
    [ q{my $s = "a"; my $r = \$s; $$r .= "x"; print "$s\n";}, 'a reference to a scalar' ],
    [ q{my $s; my $r = \$s; $$r .= "x"; print "$s\n";}, 'an undefined one: "" without a warning' ],
    [ q{my $s = "a"; my $r = \$s; my $y = 3; $$r .= "x${y}z"; print "$s\n";}, 'strings and a value' ],
    [ q{my @a = (1, 2); my $r = \$a[1]; $$r .= "x"; print "@a\n";}, 'a reference to an array element' ],
    [ q{my %h = (k => "v"); my $r = \$h{k}; $$r .= "x"; print "$h{k}\n";}, 'a reference to a hash element' ],
    [ q{my $s = "a"; my $r = \$s; print(($$r .= "x"), "\n"); print "$s\n";}, 'its value used' ],
    [ q{my $s = "a"; my $r = \$s; $$r .= "x" for 1 .. 3; print "$s\n";}, 'in a loop' ],
    [ q{my %h = (k => \my $t); ${ $h{k} } .= "x"; print "$t\n";}, 'through a reference read from a hash' ],
) {
    my ($src, $name) = @$case;
    my $want = run_perl($src);
    my ($data, $err) = wire($src);
    unlike $err, qr/GAP: /, "$name: not refused" or diag $err;
    if (!$data) { fail "$name: translates"; next }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; next;
    }
    is run_perl($out), $want, "$name: perl's answer"
        or diag "--- emitted ---\n$out--- want ---\n$want";
}

# THE STORE IS THROUGH THE REFERENCE: an Assign to the scalar deref, of a
# Concat of what it held (read at the memory before it) and "x".
{
    my ($w) = wire(q{my $s = "a"; my $r = \$s; $$r .= "x"; print "$s\n";});
    my %n = map { $_->{id} => $_ } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my ($st) = grep { $_->{op} eq 'Assign' && ( $n{ $_->{inputs}[0] }{op} // '' ) eq 'PostfixDeref' } values %n;
    ok $st, 'an Assign through the scalar deref';
    my $v = $st && $n{ $st->{inputs}[1] };
    is $v && $v->{op}, 'Concat', 'of a Concat';
    ok $v && ( $n{ $v->{inputs}[1] }{fields}{value} // '' ) eq 'x', 'ending in "x"';
}

done_testing;
