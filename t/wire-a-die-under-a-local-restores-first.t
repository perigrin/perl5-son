# ABOUTME: A die in a sub (no eval there) under a live `local` puts it back first: its restore
# ABOUTME: is pinned on the chain immediately before the Unwind, so a caller's eval sees it put back.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# Probe lo2: `our $g = 1; sub t { local $g = 2; die "x\n" } eval { t() };
# print "$g\n";` -- perl 1. The die left t by no way on the wire, and the
# restore B::SoN wrote stood after the Unwind, where nothing runs.
my $dir = tempdir( CLEANUP => 1 );
my $f = "$dir/p.pl";
open my $o, '>', $f or die $!;
print $o q{our $g = 1; sub t { local $g = 2; die "x\n" } eval { t() }; print "$g\n";};
close $o;
my $w = JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err) );
my @n  = $w->{methods}{'main::t'}{nodes}->@*;
my %by = map { $_->{id} => $_ } @n;
my ($die) = grep { $_->{op} eq 'Unwind' } @n;
ok $die, 'the die' or return;
my $before = $by{ $die->{control_in} };
is $before->{op}, 'EntryWrite', 'what the die follows is a store';
is( ( $by{ $before->{inputs}[0] }{fields} // {} )->{symbol}, 'g', '... of $g' );
my $saved = $by{ $before->{inputs}[1] };
# (a restore binds the name back to the saved scalar since places-everywhere: `EntryWrite binds [EntryDef, Ref [EntryDef]]` -- the Ref's input is the read)
$saved = $by{ $saved->{inputs}[0] } if $saved->{op} eq 'Ref';
is $saved->{op}, 'EntryDef', '... of $g\'s value read before the local';
my $local = $by{ $before->{mem_in} };
is $local->{op}, 'EntryWrite', 'the restore follows the local\'s store';
# (the `local` makes a new scalar, then stores the value into it: the save is read before the new scalar)
my $fresh = $by{ $local->{mem_in} };
ok $fresh->{op} eq 'EntryWrite' && $fresh->{fields}{local}, '... which follows the new scalar';
is $saved->{mem_in}, $fresh->{mem_in}, '... and puts back what was there before it';
is $die->{mem_in}, $before->{id}, 'the die names the memory after the restore';
done_testing;
