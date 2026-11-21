# ABOUTME: Wire v2 (B::SoN's one wire): the five examples of the plan's section 3.4, node by node --
# ABOUTME: inputs are values, `mem_in` names the version read or followed, `mem_out` a version.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# docs/plans/2026-11-20-wire-v2.md, 3.2 to 3.4. Asserted as facts about the
# nodes (which op, which inputs, which edges), not as ids.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub wire ( $src, $opt = q() ) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json$opt,not_package=SoN $f 2>$dir/err);
    return JSON::PP->new->utf8->decode($json);
}
sub graph ( $w, $name = 'main::__PROGRAM__' ) {
    my @n = $w->{methods}{$name}{nodes}->@*;
    return ( \@n, { map { $_->{id} => $_ } @n } );
}
sub op_of ( $by, $id ) { defined $id && $by->{$id} ? $by->{$id}{op} : 'none' }

subtest 'the top level says version 2 and its profile; wire v1 is gone' => sub {
    my $w = wire('print 1;');
    is $w->{version}, 2, 'version 2 (the default, and the only one)';
    is $w->{profile}, ['mem'], 'profile: mem';
    is wire( 'print 1;', ',wire=2' )->{version}, 2, 'wire=2 names it';
    like scalar( `$^X -Ilib -MO=-q,SoN,json,wire=1 -e 1 2>&1` ), qr/wire=1: the wire is version 2 \(wire v1 is gone\)/,
        'another version is refused by name';
};

subtest 'an Assign to a memory place, and the read after it' => sub {
    my ( $n, $by ) = graph( wire('my @a = (1,2); $a[0] = 10; my $x = $a[0]; print "$x\n";') );
    my ($st) = grep { $_->{op} eq 'Assign' } @$n;
    my @sub = grep { $_->{op} eq 'Subscript' } @$n;
    my ($place) = grep { !exists $_->{mem_in} } @sub;
    my ($read)  = grep { exists $_->{mem_in} } @sub;
    ok $place && $read, 'one Subscript place, one read' or return;
    is $st->{inputs}[0], $place->{id}, 'the place is the Assign target';
    is scalar $place->{inputs}->@*, 2, '... [container, index]';
    is op_of( $by, $st->{mem_in} ), 'MemStart', 'the Assign follows MemStart';
    ok $st->{mem_out}, '... and is a version';
    ok defined $st->{control_in}, '... on the control chain';
    is scalar $read->{inputs}->@*, 2, 'the read: values only';
    is $read->{mem_in}, $st->{id}, '... read at the Assign';
    is [ $read->{inputs}->@* ], [ $place->{inputs}->@* ], '... of the same element';
};

subtest 'a sub call is a version, and the read after it names it' => sub {
    my ( $n, $by ) = graph( wire('our $g = 0; sub bump { $g++ } bump(); print "$g\n";') );
    my ($call) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'main::bump' } @$n;
    ok $call, 'the call' or return;
    ok defined $call->{control_in} && defined $call->{mem_in} && $call->{mem_out}, 'control_in, mem_in, mem_out';
    my @reads = grep { $_->{op} eq 'EntryDef' && $_->{fields}{symbol} eq 'g' && ( $_->{mem_in} // -1 ) == $call->{id} } @$n;
    ok scalar @reads, 'a read of $g names the call as its version';
    ok !grep( { exists $_->{fields}{memory_input} } @$n ), 'no memory_input on v2';
};

subtest 'a memory read through a builtin' => sub {
    my ( $n, $by ) = graph( wire('my @k; my %h; push @k, "z"; my $c = @k; my $r = ref(\%h); print "$c $r\n";') );
    my ($push)  = grep { $_->{op} eq 'Call' && $_->{fields}{name} eq 'push' } @$n;
    my ($count) = grep { $_->{op} eq 'Count' } @$n;
    my ($rt)    = grep { $_->{op} eq 'RefType' } @$n;
    ok $push && $count && $rt, 'push, Count, RefType' or return;
    is scalar $push->{inputs}->@*, 2, 'push: [array, value]';
    ok $push->{mem_out} && defined $push->{mem_in}, 'push follows memory and is a version';
    is scalar $count->{inputs}->@*, 1, 'Count: [array]';
    is $count->{mem_in}, $push->{id}, '... read at the push';
    is scalar $rt->{inputs}->@*, 1, 'RefType: [reference]';
    ok defined $rt->{mem_in}, '... read at a version';
};

subtest 'Return names the memory at the end of its sub' => sub {
    my ( $n, $by ) = graph( wire('our $g = 1; sub bump { $g += 10 } bump(); print "$g\n";'), 'main::bump' );
    my ($ret) = grep { $_->{op} eq 'Return' } @$n;
    my ($w)   = grep { $_->{op} eq 'EntryWrite' } @$n;
    ok $ret && $w, 'a Return and the store' or return;
    is scalar $w->{inputs}->@*, 2, 'the EntryWrite: [place, value]';
    ok $w->{mem_out} && op_of( $by, $w->{mem_in} ) eq 'MemStart', '... follows MemStart and is a version';
    is $ret->{mem_in}, $w->{id}, 'the Return names it';
    my @defs = grep { $_->{op} eq 'EntryDef' && $_->{fields}{symbol} eq 'g' } @$n;
    is scalar(@defs), 2, 'the read and the place of $g are two nodes';
    is [ sort map { exists $_->{mem_in} ? 'read' : 'place' } @defs ], [ 'place', 'read' ], '... one read, one place';
};

subtest 'a record assign is on neither chain' => sub {
    my ( $n, $by ) = graph( wire('my ($x, $y) = (1, 2); print "$x $y\n";') );
    my ($as) = grep { $_->{op} eq 'Assign' } @$n;
    ok $as, 'the Assign' or return;
    ok $as->{fields}{record}, 'record';
    ok !exists $as->{control_in} && !exists $as->{mem_in} && !exists $as->{mem_out}, 'no control_in, mem_in, mem_out';
};

done_testing;
