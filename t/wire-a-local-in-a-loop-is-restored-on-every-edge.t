# ABOUTME: `local $g` in a loop body is put back on every way out of the pass -- its end,
# ABOUTME: a `next`, a `last` -- and what it puts back is the value $g held at the local.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# THE DEFECT (audit 2026-11-19, W6, probe lo3 -- one of the three whose wire
# was byte-identical to a right program's, so only the producer could fix it).
#
#     our $g = 1;
#     for my $i (1..2) { local $g = $g + $i; last if $i == 2 }
#     print "$g\n";                                   perl 1, the wire 4
#
# The `local` was a plain store on the wire: no restore at the end of the
# pass (the next pass added to the last one's local) and none on the `last`.
# Two causes. The pass-end restore ran only where the loop walk itself
# reached the body's `unstack`; a body whose tail follows a guarded `next` or
# `last` is finished by an arm walk, which has none of the loop walk's saves.
# And a loop control's edge restored localized ELEMENTS only.
#
# AND WHAT IT RESTORES was the scope binding -- what this graph last stored --
# where a sub had since written the scalar: `b(); { local $g = 2 } print $g`
# printed what $g held before b().

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub nodes ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return () unless length $json;
    return JSON::PP->new->utf8->decode($json)->{methods}{'main::__PROGRAM__'}{nodes}->@*;
}

# The stores to $g on the control path back from $from to (not through) $stop.
sub stores_back ( $by, $from, $stop ) {
    my ( @s, %seen );
    my @q = ($from);
    while ( defined( my $id = shift @q ) ) {
        next if $seen{$id}++ || $id == $stop;
        my $x = $by->{$id} or next;
        push @s, $x if $x->{op} eq 'EntryWrite' && $by->{ $x->{inputs}[0] }{fields}{symbol} eq 'g';
        push @q, grep { defined } $x->{control_in},
            ( $x->{op} =~ /\A(?:Proj|Region|If)\z/ ? $x->{inputs}->@[ 0 .. ( $x->{op} eq 'Region' ? $#{ $x->{inputs} } : 0 ) ] : () );
    }
    return @s;
}

subtest 'a `last` after the local puts it back on its way out' => sub {
    my @n  = nodes('our $g = 1; for my $i (1..2) { local $g = $g + $i; last if $i == 2 } print "$g\n";');
    my %by = map { $_->{id} => $_ } @n;
    my ($loop) = grep { $_->{op} eq 'Loop' } @n or return fail 'no Loop';
    my ($exit) = grep { $_->{op} eq 'Region' && ( $_->{head} // -1 ) == $loop->{id} } @n or return fail 'no exit Region';
    my ($local) = grep { $_->{op} eq 'EntryWrite' && $by{ $_->{inputs}[1] }{op} eq 'Add' } @n;
    ok $local, 'the local\'s store' or return;
    # the exit's way in from the `last`: not the loop's own exit Proj
    my @break = grep { !( $by{$_}{op} eq 'Proj' && $by{$_}{inputs}[0] == $loop->{id} ) } $exit->{inputs}->@*;
    is scalar(@break), 1, 'one break edge' or return;
    my @restore = grep { $_->{id} != $local->{id} } stores_back( \%by, $break[0], $local->{id} );
    is scalar(@restore), 1, 'a store to $g stands between the local and the exit';
    my $saved = $by{ $restore[0]{inputs}[1] };
    is $saved->{op}, 'EntryDef', 'it stores a read of $g';
    is $saved->{inputs}[0], $local->{inputs}[2], '...made at the version the local\'s store follows';
};

subtest 'the pass that runs on puts it back too, past a guarded `last`' => sub {
    my @n  = nodes('our $g = 1; for my $i (1..2) { local $g = $g + $i; print "in $g\n"; last if $i == 2; print "more\n"; } print "$g\n";');
    my %by = map { $_->{id} => $_ } @n;
    my ($loop) = grep { $_->{op} eq 'Loop' } @n or return fail 'no Loop';
    my ($mem)  = grep { $_->{op} eq 'Phi' && $_->{fields}{memory} && $_->{fields}{region} == $loop->{id} } @n;
    ok $mem, 'the loop carries memory' or return;
    my $back = $by{ $mem->{inputs}[1] };
    is $back->{op}, 'EntryWrite', 'the version that goes round is a store';
    is $by{ $back->{inputs}[1] }{op}, 'EntryDef', '...of the value saved at the local, not the local\'s own';
};

subtest 'a `next` after the local puts it back on its edge' => sub {
    my @n = nodes('our $g = 1; for my $i (1..2) { local $g = $g + $i; next if $i == 1; print "more $g\n"; } print "$g\n";');
    my %by = map { $_->{id} => $_ } @n;
    my @restores = grep { $_->{op} eq 'EntryWrite' && $by{ $_->{inputs}[1] }{op} eq 'EntryDef' } @n;
    is scalar(@restores), 2, 'two restores: the `next` edge and the pass that runs on';
};

subtest 'what is put back is what the scalar held at the local' => sub {
    my @n  = nodes('our $g = 1; sub b { $g = 5 } b(); { local $g = 2; print "$g\n"; } print "$g\n";');
    my %by = map { $_->{id} => $_ } @n;
    my ($call) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'main::b' } @n or return fail 'no call';
    my @writes = grep { $_->{op} eq 'EntryWrite' && $by{ $_->{inputs}[0] }{fields}{symbol} eq 'g' } @n;
    my $restore = $writes[-1];
    my $saved   = $by{ $restore->{inputs}[1] };
    is $saved->{op}, 'EntryDef', 'the restore stores a read of $g' or return;
    is $saved->{inputs}[0], $call->{id}, '...at the version the call left, not the constant bound before it';
};

done_testing;
