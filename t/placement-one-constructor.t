# ABOUTME: Every node the walk puts on the control chain is put there by _pin (and,
# ABOUTME: when it is a memory version, by _place): no handler sets the three by hand.
use v5.42.0;
use Test2::V0;

# WHY A SOURCE TEST. The audit of 2026-11-19 (departure 5) counted about 120
# hand-written placements in lib/SoN/FromOptree.pm: three lines each --
# control_in, the sim's control, the sim's memory -- and a store was on the
# memory chain only where all three were written. A handler that wrote two
# made a store the control and not the memory. The wire cannot say which
# handler made a node, so the rule "one constructor" is held on the source.

my $file = 'lib/SoN/FromOptree.pm';
open my $fh, '<', $file or die "$file: $!";
my @lines = <$fh>;
close $fh;

my ( $sub, @by_hand, %defined );
for my $i ( 0 .. $#lines ) {
    $sub = $1 if $lines[$i] =~ /^\s*sub (\w+)/;
    $defined{$1} = 1 if $lines[$i] =~ /^\s*sub (_pin|_place)\b/;
    # control_in taken from a sim's current control: the placement itself.
    push @by_hand, sprintf( '%s:%d (in %s)', $file, $i + 1, $sub // 'file' )
        if $lines[$i] =~ /->set_control_in\(\s*\$\w+->control\s*\)/ && ( $sub // '' ) ne '_pin';
}

ok $defined{_pin} && $defined{_place}, '_pin and _place are defined';

# AND THE ONE PLACE A NODE BECOMES A MEMORY VERSION (wire v2's mem_out): a
# node made the sim's memory by hand would be a version the wire does not
# call one (or _unplace, which takes back the last placement). What may be
# set as the memory besides: another sim's memory, a
# Phi (a merge, or a loop header's), or MemStart.
my ( $s2, @versions_by_hand );
for my $i ( 0 .. $#lines ) {
    $s2 = $1 if $lines[$i] =~ /^\s*sub (\w+)/;
    next if ( $s2 // "" ) =~ /\A(?:_pin|_place|_unplace|_call_memory_barrier)\z/;
    push @versions_by_hand, sprintf( '%s:%d (in %s)', $file, $i + 1, $s2 // 'file' )
        if $lines[$i] =~ /->set_mem_out\(/
        || $lines[$i] =~ /->set_memory\(\s*(?!\$\w+->memory\b|\$mem_phi\b|\$memory\[|\$factory->make(?:_unique)?\('Phi')/;
}
is \@versions_by_hand, [], 'no handler makes a memory version by hand';
is \@by_hand, [], 'no handler takes control_in from the sim by hand';

# _place is _pin plus the memory version, and nothing else.
my ($body) = join( '', @lines ) =~ /^\s*sub _place \(\$sim, \$node\) \{\n(.*?)^\s*\}\n/ms;
like $body // '', qr/_pin\(\$sim, \$node, 1\);.*\$node->set_mem_out\(1\);.*\$sim->set_memory\(\$node\)/s,
    '_place pins, then makes the node the memory version';

done_testing;
