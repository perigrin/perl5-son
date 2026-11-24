# ABOUTME: A division or modulus whose divisor may be zero dies where it stands: it is
# ABOUTME: pinned to the control chain; one that cannot fault stays a floating value.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE DEFECT (audit 2026-11-19, W7, departure 23). `1 / $d` was a floating
# value: a consumer made it where it was first used, so
#
#     my $d = @ARGV; my $q = 1 / $d; print "before\n"; print "$q\n";
#
# printed `before` and then died, where perl dies first. Click: "Faulting
# instructions keep an explicit control input."

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub nodes ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $w = JSON::PP->new->utf8->decode($json);
    return ( $w, $w->{methods}{'main::__PROGRAM__'}{nodes}->@* );
}

for my $c ( [ 'Divide', '1 / $d' ], [ 'Modulo', '7 % $d' ], [ 'Divide', '$d / $d' ] ) {
    my ( $kind, $expr ) = @$c;
    subtest "$expr may fault" => sub {
        my ( $w, @n ) = nodes(qq{my \$d = \@ARGV; my \$q = $expr; print "before\\n"; print "\$q\\n";});
        my ($div) = grep { $_->{op} eq $kind } @n or return fail "no $kind";
        ok defined $div->{control_in}, 'it has a control_in';
        my ($before) = grep { $_->{op} eq 'Print' } @n;
        my %by = map { $_->{id} => $_ } @n;
        my ( $p, $seen ) = ( $before->{control_in}, 0 );
        while ( defined $p && $by{$p} ) { $seen = 1 if $p == $div->{id}; $p = $by{$p}{control_in} }
        ok $seen, 'the first print comes after it on the chain';
        is [ grep { $_->{rule} eq 'fault-floating' } SoN::Verify::verify($w)->{violations}->@* ], [],
            'the verifier sees no floating fault';
    };
}

for my $c ( [ 'Divide', '$d / 2' ], [ 'Modulo', '$d % 3' ], [ 'Divide', '$d / 0.5' ] ) {
    my ( $kind, $expr ) = @$c;
    subtest "$expr cannot fault" => sub {
        my ( $w, @n ) = nodes(qq{my \$d = \@ARGV; my \$q = $expr; print "\$q\\n";});
        my ($div) = grep { $_->{op} eq $kind } @n or return fail "no $kind";
        ok !defined $div->{control_in}, 'it floats: a value like any other';
    };
}

subtest 'a modulus by a constant that truncates to zero may fault' => sub {
    my ( $w, @n ) = nodes(q{my $d = @ARGV; my $q = eval { $d % 0.5 }; print defined $q ? "v\n" : "died\n";});
    my ($div) = grep { $_->{op} eq 'Modulo' } @n or return fail 'no Modulo';
    ok defined $div->{control_in}, 'it has a control_in';
};

# AN ARGUMENT OF sprintf is flagged OPf_MOD (it may be %n's target), and the
# pin skipped it: `sprintf("%d", 1/$_[0])` floated (final audit 2026-11-24,
# clause 2; verifier rule effect-floating). A division is never a store.
subtest 'a division that may fault among sprintf\'s arguments' => sub {
    my ( $w, @n ) = nodes(q{my $d = @ARGV; my $s = sprintf("%d", 1/$d); print "before\n"; print "$s\n";});
    my ($div) = grep { $_->{op} eq 'Divide' } @n or return fail 'no Divide';
    ok defined $div->{control_in}, 'it has a control_in';
    is [ map { $_->{rule} } SoN::Verify::verify($w)->{violations}->@* ], [], 'the verifier finds nothing';
};

done_testing;
