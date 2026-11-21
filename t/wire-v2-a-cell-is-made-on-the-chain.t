# ABOUTME: A MakeCell is a memory version made where it stands: on wire v2 it is on the
# ABOUTME: control chain (control_in, mem_in, mem_out); wire v1 writes it as it always did.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Verify;
use SoN::Deparse;

# Known issue 1 of the wire v2 baseline (section 9): a cell was made the
# memory version by _call_memory_barrier and never put on the control chain,
# so every MakeCell was a V2 version-off-chain and most of V5's
# memory-order-disagrees. v1 has no place for the pin: its writer leaves it
# out, so the deparser and chalk's v1 reader see the wire they saw.
my $dir = tempdir( CLEANUP => 1 );
my $src = 'my $n = 1; my $f = sub { $n += 2; 1 }; $f->(); print "$n\n";';
open my $o, '>', "$dir/c.pl" or die $!;
print $o $src, "\n";
close $o;

sub wire ($v) {
    my $j = qx($^X -Ilib -MO=-q,SoN,json,wire=$v,not_package=SoN $dir/c.pl 2>/dev/null);
    return decode_json($j);
}
sub cell ($w) {
    my ($c) = grep { $_->{op} eq 'MakeCell' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    return $c;
}

my $w2 = wire(2);
my $c2 = cell($w2);
ok $c2, 'wire 2 makes the cell';
ok defined $c2->{control_in}, '... on the control chain';
ok defined $c2->{mem_in} && $c2->{mem_out}, '... as a memory version';
is [ grep { $_->{rule} =~ /version-off-chain|memory-order-disagrees/ } SoN::Verify::verify($w2)->{violations}->@* ], [],
    'no version off the chain, no memory out of order';

my $w1 = wire(1);
ok !defined cell($w1)->{control_in}, 'wire 1 writes the cell as it was: off the chain';
ok !( grep { defined $_->{control_in} && ( $w1->{methods}{'main::__PROGRAM__'}{nodes}[ $_->{control_in} ]{op} eq 'MakeCell' ) }
        $w1->{methods}{'main::__PROGRAM__'}{nodes}->@* ), '... and nothing follows it on the chain';

# Both read back as the program: perl's answer.
for my $w ( $w1, $w2 ) {
    my $d   = SoN::Deparse->new;
    my $out = $d->render($w);
    ok defined $out, "wire $w->{version} renders" or diag $d->gap;
    open my $p, '>', "$dir/r.pl" or die $!;
    print $p $out;
    close $p;
    is scalar qx($^X $dir/r.pl 2>&1), "3\n", "wire $w->{version}: perl's answer";
}

done_testing;
