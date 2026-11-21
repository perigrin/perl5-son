# ABOUTME: `($lo, $used) = g()` into `my` scalars declared earlier is a store on both chains
# ABOUTME: (control_in, mem_in, mem_out): what the memory after it is, not a pin that stores nothing.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Deparse;

# WHY (docs/plans/2026-11-20-wire-v2.md, stage 6, L5 hard). The Assign binds
# the scalars from a list whose positions are not known (a call), and the
# slots are read by name after it: it was pinned where it stands, following
# memory, but no version -- on the control chain only. Wire v2's L5 asks a
# non-record Assign for all three edges; this one fills the variables' slots
# (chalk keeps them in cells), so it is a store: placed, the memory version
# the reads after it follow. Corpus 167, 168.

my $dir = tempdir( CLEANUP => 1 );
my $src = q{sub g { (5, 2) } sub f { my ($lo, $used); ($lo, $used) = g(); $used += 1; "$lo $used" } print f(), "\n";};
open my $o, '>', "$dir/c.pl" or die $!;
print $o $src, "\n";
close $o;
my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $dir/c.pl 2>/dev/null) );
my @n  = $w->{methods}{'main::f'}{nodes}->@*;
my %by = map { $_->{id} => $_ } @n;

my ($as) = grep { $_->{op} eq 'Assign' && ( $_->{fields}{targets} // 0 ) == 2 } @n;
ok $as, 'the list assignment' or bail_out('no Assign');
ok defined $as->{control_in}, '... on the control chain';
is $by{ $as->{mem_in} // -1 }{op}, 'Call', '... following the call it binds from';
ok $as->{mem_out}, '... and a memory version';
my ($ret) = grep { $_->{op} eq 'Return' } @n;
is $ret->{mem_in}, $as->{id}, 'the sub ends at its memory';

my $d    = SoN::Deparse->new;
my $text = $d->render($w);
ok defined $text, 'it renders' or diag $d->gap;
open my $r, '>', "$dir/r.pl" or die $!;
print $r $text // '';
close $r;
is scalar qx($^X $dir/r.pl 2>&1), "5 3\n", "and prints perl's answer";

done_testing;
