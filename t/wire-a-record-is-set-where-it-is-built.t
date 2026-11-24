# ABOUTME: An Assign is a record because B::SoN says so where it builds it, not because the
# ABOUTME: serializer found it on neither chain (final audit, clause 3).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::IR::NodeFactory;
use SoN::Serialize::JSON;
use SoN::Verify;

# The serializer wrote `record` for any Assign off both chains, so a store
# the walk forgot to place was a record by construction and the verifier,
# reading the flag, checked the writer against itself.
subtest 'an Assign off both chains is no record unless it says so' => sub {
    my $f = SoN::IR::NodeFactory->new;
    my $t = $f->make('PadAccess', targ => 1, sigil => '$', symbol => 'x');
    my $v = $f->make('Constant', value => 1);
    my $a = $f->make('Assign', inputs => [ $t, $v ]);
    ok !$a->record, 'built with no flag';
    my $fields = SoN::Serialize::JSON::_extract_fields( $a, { map { $_->id => $_->id } $t, $v, $a } ) // {};
    ok !$fields->{record}, 'the serializer does not make one a record';
    my $r = $f->make('Assign', inputs => [ $t, $v ], record => 1);
    ok $r->record, 'a record says so';
    isnt $r, $a, '... and is not the store of the same value';
    ok( ( SoN::Serialize::JSON::_extract_fields( $r, { map { $_->id => $_->id } $t, $v, $r } ) // {} )->{record},
        'and is written so' );
};

my $dir = tempdir( CLEANUP => 1 );
sub wire ($src) {
    open my $o, '>', "$dir/c.pl" or die $!;
    print $o $src, "\n";
    close $o;
    return decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $dir/c.pl 2>/dev/null) );
}

subtest 'B::SoN flags the parameter bind and the SSA rebind' => sub {
    my $w = wire('sub f { my ($a, $b) = @_; my ($c, $d) = ($b, $a); $c . $d } print f(1, 2), "\n";');
    my @rec = grep { $_->{op} eq 'Assign' && ( $_->{fields} // {} )->{record} } $w->{methods}{'main::f'}{nodes}->@*;
    is scalar @rec, 2, 'two records';
    ok !( grep { defined $_->{control_in} || $_->{mem_out} } @rec ), '... each on neither chain';
    is [ map { $_->{rule} } SoN::Verify::verify($w)->{violations}->@* ], [], 'the wire verifies';
};

done_testing;
