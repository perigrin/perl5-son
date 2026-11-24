# ABOUTME: the rest of a loop body after `next unless C` / `last unless C` is walked on its own
# ABOUTME: Proj, so a division there that may fault is pinned after the guard, not left floating.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;
use SoN::Verify;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx(/usr/bin/timeout 10 $^X $f 2>&1);
}

sub wire_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    return eval { JSON::PP->new->decode($j) };
}

# The Ifs on the control chain from $n back to the Loop: the loop's test, and
# the guard's when $n stands after it.
sub ifs_before ( $n, $by ) {
    my $ifs = 0;
    my %seen;
    while ( $n && !$seen{ $n->{id} }++ && $n->{op} ne 'Loop' ) {
        $ifs++ if $n->{op} eq 'If';
        my $up = $n->{control_in} // ( $n->{op} eq 'Proj' ? $n->{inputs}[0] : undef );
        $n = defined $up ? $by->{$up} : undef;
    }
    return $ifs;
}

# (probe aun5d is the first: its Divide floated, and perl never runs it with 0)
for my $src (
    q{my $d=@ARGV; for my $x (2, $d) { next unless $x; print 4 / $x, "\n" } print "end\n";},
    q{my $d=@ARGV; for my $x (2, $d) { next if !$x; my $q = 4 / $x; print "z\n"; print $q, "\n" } print "end\n";},
    q{my $d=@ARGV; for my $x (2, $d) { last unless $x; print 4 / $x, "\n" } print "end\n";},
    q{my $d=@ARGV; for my $x (2, $d) { print "a\n"; next unless $x; print 4 % $x, "\n" } print "end\n";},
) {
    subtest $src => sub {
        my $w = wire_of($src) or return fail 'a wire';
        my @n  = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        my %by = map { $_->{id} => $_ } @n;
        my ($div) = grep { $_->{op} =~ /\A(?:Divide|Modulo)\z/ } @n;
        ok $div, 'the division' or return;
        ok defined $div->{control_in}, 'it is on the control chain';
        is ifs_before( $div, \%by ), 2, 'after the guard (the guard\'s If and the loop\'s test)';
        is [ grep { $_->{rule} eq 'effect-floating' } SoN::Verify::verify($w)->{violations}->@* ], [],
            'the verifier finds no floating effect';
        my $d   = SoN::Deparse->new;
        my $out = $d->render($w);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

done_testing;
