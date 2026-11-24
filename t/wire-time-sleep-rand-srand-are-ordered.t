# ABOUTME: time, sleep, rand and srand stand on the control chain in order: a time read
# ABOUTME: after a sleep, and a rand after an srand, are made after it (final audit 4.10).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Verify;
use SoN::Deparse;
use B::SoN::EffectTable;

# Floating, the two `time` reads named MemStart and nothing put them on
# either side of the sleep (nor the rands of the srands): a consumer could
# make both before it, and `$t1 > $t0` read 0.
my $dir = tempdir( CLEANUP => 1 );

sub wire ($src) {
    open my $o, '>', "$dir/c.pl" or die $!;
    print $o $src, "\n";
    close $o;
    return decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $dir/c.pl 2>/dev/null) );
}

# the builtin Calls on the program's control chain, in its order
sub chain ($w) {
    my $g = $w->{methods}{'main::__PROGRAM__'};
    my %succ;
    push $succ{ $_->{control_in} }->@*, $_ for grep { defined $_->{control_in} } $g->{nodes}->@*;
    my @c;
    for ( my $at = $g->{start}; my @s = ( $succ{$at} // [] )->@*; $at = $s[0]{id} ) {
        push @c, $s[0]{fields}{name} if $s[0]{op} eq 'Call';
    }
    return [ grep { /\A(?:time|sleep|rand|srand)\z/ } @c ];
}

ok B::SoN::EffectTable::on_chain($_), "$_ is on the chain in every context" for qw(time sleep rand srand);

for my $case (
    [ 'my $t0 = time; sleep 1; my $t1 = time; print $t1 > $t0 ? "ok\n" : "no\n";', [qw(time sleep time)] ],
    [ 'srand(42); my $a = rand; srand(42); my $b = rand; print $a == $b ? "same\n" : "diff\n";', [qw(srand rand srand rand)] ],
    [ 'my @r = (rand, rand); print $r[0] == $r[1] ? "same\n" : "diff\n";', [qw(rand rand)] ],
) {
    my ( $src, $want ) = @$case;
    my $w = wire($src);
    is chain($w), $want, "in order on the chain: $src";
    is [ map { "$_->{rule}" } SoN::Verify::verify($w)->{violations}->@* ], [], '... and the wire verifies';
    my $d   = SoN::Deparse->new;
    my $out = $d->render($w);
    ok defined $out, '... and renders' or diag $d->gap;
    open my $p, '>', "$dir/r.pl" or die $!;
    print $p $out;
    close $p;
    is scalar qx($^X $dir/r.pl 2>&1), scalar qx($^X $dir/c.pl 2>&1), "... perl's answer";
}

done_testing;
