# ABOUTME: A MakeCell is a memory version made where it stands: on wire v2 it is on the
# ABOUTME: control chain (control_in, mem_in, mem_out), and the deparser reads it back.
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

sub wire () {
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $dir/c.pl 2>/dev/null);
    return decode_json($j);
}
sub cell ($w) {
    my ($c) = grep { $_->{op} eq 'MakeCell' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    return $c;
}

my $w2 = wire();
my $c2 = cell($w2);
ok $c2, 'wire 2 makes the cell';
ok defined $c2->{control_in}, '... on the control chain';
ok defined $c2->{mem_in} && $c2->{mem_out}, '... as a memory version';
is [ grep { $_->{rule} =~ /version-off-chain|memory-order-disagrees/ } SoN::Verify::verify($w2)->{violations}->@* ], [],
    'no version off the chain, no memory out of order';

# It reads back as the program: perl's answer (wire v1, which left the pin
# out, is gone: stage 6).
for my $w ($w2) {
    my $d   = SoN::Deparse->new;
    my $out = $d->render($w);
    ok defined $out, "wire $w->{version} renders" or diag $d->gap;
    open my $p, '>', "$dir/r.pl" or die $!;
    print $p $out;
    close $p;
    is scalar qx($^X $dir/r.pl 2>&1), "3\n", "wire $w->{version}: perl's answer";
}

done_testing;
