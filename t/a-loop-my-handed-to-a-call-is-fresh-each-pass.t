# ABOUTME: A `my` made anew each pass of a loop, handed to a call, is passed as a place that says so
# ABOUTME: (PadAccess fresh_each_pass): a consumer gives each pass its own scalar, as perl does.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub produce ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    my $err = do { local ( @ARGV, $/ ) = "$dir/err"; <> } // '';
    return ( ( $json =~ /\S/ ? JSON::PP->new->decode($json) : undef ), $err =~ s/^\S+ syntax OK\n//mr );
}

# (perl prints 1,2,3 for each: the callee's `\$_[0]` is to that pass's $x.
# The wire held one slot for every pass -- 3,3,3 -- and then refused the named
# sub's form, leaving a method's and a code ref's wrong: probes x/xm24-xm31)
for my $src (
    'sub k { \$_[0] } my @r; for my $i (1..3) { my $x = $i; push @r, k($x) } print join(",", map { $$_ } @r), "\n";',
    'our @K; sub keep { push @K, \$_[0] } for my $i (1..3) { my $x = $i; keep($x) } print join(",", map { $$_ } @K), "\n";',
    'package K; sub new { bless {}, shift } sub k { \$_[1] } package main; my $o = K->new; my @r; for my $i (1..3) { my $x = $i; push @r, $o->k($x) } print join(",", map { $$_ } @r), "\n";',
    'my $k = sub { \$_[0] }; my @r; for my $i (1..3) { my $x = $i; push @r, $k->($x) } print join(",", map { $$_ } @r), "\n";',
    'sub k { \$_[0] } my @r; my $i = 0; while ($i < 3) { my $x = ++$i; push @r, k($x) } print join(",", map { $$_ } @r), "\n";',
) {
    my ( $w, $err ) = produce($src);
    is $err, '', "translates: $src";
    my @fresh = grep { $_->{op} eq 'PadAccess' && ( $_->{fields}{symbol} // '' ) eq 'x' && $_->{fields}{place} && $_->{fields}{fresh_each_pass} }
        map { $_->{nodes}->@* } values( ( $w // {} )->{methods}->%* );
    ok scalar(@fresh), "the argument is a place made anew each pass: $src";
}
# (a `my` outside the loop is one scalar: no mark)
{
    my ( $w ) = produce('sub k { \$_[0] } my @r; my $x; for my $i (1..3) { $x = $i; push @r, k($x) } print join(",", map { $$_ } @r), "\n";');
    ok !( grep { $_->{op} eq 'PadAccess' && $_->{fields}{fresh_each_pass} } map { $_->{nodes}->@* } values $w->{methods}->%* ),
        'a `my` declared before the loop is not made anew';
}
done_testing;
