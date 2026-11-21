# ABOUTME: ref(), blessed() and reftype() read the referent's class at a memory version, and a
# ABOUTME: bless is the version after it: a read before a bless and one after differ on the wire.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;
use SoN::Verify;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g.pl";    # one name: the wire carries it, and two wires are compared
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub program ($data) { return $data->{methods}{'main::__PROGRAM__'}{nodes}->@* }
sub canon ($data)   { return JSON::PP->new->canonical->encode( $data->{methods}{'main::__PROGRAM__'} ) }

# The class reads of a wire: RefType nodes and the builtin Calls named.
sub class_reads (@nodes) {
    return grep {
        $_->{op} eq 'RefType'
            || $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) =~ /\A(?:blessed|reftype)\z/
    } @nodes;
}
# The memory a class read is at (wire v2: its mem_in).
sub memory_of ($n) { return $n->{mem_in} }

sub renders_the_same ( $src, $data, $what ) {
    my $d   = SoN::Deparse->new;
    my $out = $d->render($data);
    ok defined $out, "$what: the deparser renders it" or diag $d->gap;
    is run_perl( $out // '' ), run_perl($src), "$what: and it prints what perl prints";
}

sub no_unversioned_class_read ( $data, $what ) {
    my @bad = grep { $_->{rule} eq 'read-unversioned:object-class' } SoN::Verify::verify($data)->{violations}->@*;
    is \@bad, [], "$what: the verifier finds no class read without a version";
}

# THE TWO PROGRAMS THAT WERE ONE WIRE (docs/memory/ref-of-a-blessed-reference-
# names-no-version.md): K and HASH, and nothing on the wire to say which.
subtest 'ref() after a bless and ref() before it are two wires' => sub {
    my $after  = q{my $h = {}; bless $h, "K"; print ref($h), "\n";};
    my $before = q{my $h = {}; my $r = ref($h); bless $h, "K"; print $r, "\n";};
    my ( $da, $db ) = ( graph_of($after), graph_of($before) );
    isnt canon($da), canon($db), 'the wires differ';

    for my $case ( [ after => $da, 'Call' ], [ before => $db, 'MemStart' ] ) {
        my ( $what, $data, $want ) = $case->@*;
        my %by      = map { $_->{id} => $_ } program($data);
        my ($bless) = grep { $_->{op} eq 'Call' && $_->{fields}{name} eq 'bless' } program($data);
        my ($read)  = grep { $_->{op} eq 'RefType' } program($data);
        ok defined $bless->{mem_in} && $bless->{mem_out}, "$what: the bless follows memory and is a version";
        ok defined $bless->{control_in}, "$what: the bless is on the control chain";
        is scalar( $read->{inputs}->@* ), 1, "$what: the RefType's input is its reference";
        is $by{ $read->{mem_in} }{op}, $want, "$what: it reads the memory $want";
        is $read->{mem_in}, $bless->{id}, 'after: that memory is the bless' if $what eq 'after';
        no_unversioned_class_read( $data, $what );
    }
    renders_the_same( $after,  $da, 'after' );
    renders_the_same( $before, $db, 'before' );
};

# Each class read of a program names a version, and one each side of a bless
# names two.
for my $case (
    [ 'ref() on both sides (probe ef9)',
        q{my $o = {}; my $c = ref($o); bless $o, "K"; my $d = ref($o); print "$c $d\n";}, 2 ],
    [ 'blessed() on both sides (probe st2)',
        q{use Scalar::Util qw(blessed); my $o = {}; my $a = blessed($o) // "u"; bless $o, "K"; my $b = blessed($o) // "u"; print "$a $b\n";}, 2 ],
    [ 'blessed() of a reference a sub made',
        q{use Scalar::Util qw(blessed); sub mk { return [] } my $o = mk(); my $a = blessed($o) // "u"; bless $o, "K"; my $b = blessed($o) // "u"; print "$a $b\n";}, 2 ],
    [ 'reftype() and ref() across a bless',
        q{use Scalar::Util qw(reftype); my $o = []; my $a = ref($o); my $t = reftype($o); bless $o, "K"; print "$a $t ", ref($o), " ", reftype($o), "\n";}, 2 ],
    [ 'a bless in a called sub (probe st7)',
        q{sub mk { return bless {}, "A" } sub re { bless $_[0], "B"; return } my $o = mk(); my $a = ref($o); re($o); print "$a ", ref($o), "\n";}, 2 ],
    [ 'a bless used for its value (probe vp19)',
        q{my $o = {}; my @r = (ref($o), ref(bless $o, "K"), ref($o)); print "@r\n";}, 2 ],
    [ 'ref() in a loop that blesses',
        q{my $o = {}; for my $c ("A", "B") { print ref($o), " "; bless $o, $c } print ref($o), "\n";}, 2 ],
) {
    my ( $what, $src, $versions ) = $case->@*;
    subtest $what => sub {
        my $data  = graph_of($src) or return fail 'a wire';
        my @reads = class_reads( program($data) );
        ok scalar(@reads), 'the wire has class reads';
        is [ grep { !defined memory_of($_) } @reads ], [], 'every class read has a memory input';
        my %seen = map { memory_of($_) // 'none' => 1 } @reads;
        is scalar( keys %seen ), $versions, "they read $versions memory versions";
        no_unversioned_class_read( $data, $what );
        renders_the_same( $src, $data, $what );
    };
}

done_testing;
