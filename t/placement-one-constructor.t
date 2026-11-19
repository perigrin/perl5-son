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
is \@by_hand, [], 'no handler takes control_in from the sim by hand';

# _place is _pin plus the memory version, and nothing else.
my ($body) = join( '', @lines ) =~ /^\s*sub _place \(\$sim, \$node\) \{\n(.*?)^\s*\}\n/ms;
like $body // '', qr/_pin\(\$sim, \$node\);.*\$sim->set_memory\(\$node\)/s,
    '_place pins, then makes the node the memory version';

done_testing;
