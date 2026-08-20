# ABOUTME: Tests that B::SoN under package=main emits the MOP of classes only
# ABOUTME: referenced (via method Call class_name) from the emitted subs.

use v5.42.0;
use Test2::V0;
use JSON::PP ();

my $perl = $^X;
my $lib  = 'lib';

# Run B::SoN,json,package=main on a source file and return the decoded JSON.
sub son_json ($source) {
    require File::Temp;
    my ( $fh, $tmp ) = File::Temp::tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $source;
    close $fh;
    my $out = `$perl -I$lib -MO=SoN,json,package=main $tmp 2>/dev/null`;
    return JSON::PP->new->decode($out);
}

# The teaching case: a whole-program object idiom. Counter is referenced only
# from main::corpus_case via Counter->new and $c->get; under package=main the
# producer must still emit Counter's MOP so the Chalk side can infer the
# method Call's return repr.
my $SRC = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method get { $n }
}
sub corpus_case {
    my $c = Counter->new(n => 5);
    my $x = $c->get;
    $x;
}
corpus_case();
PERL

my $data = son_json($SRC);

subtest 'referenced class is emitted under package=main' => sub {
    ok( exists $data->{classes}, 'JSON has a top-level classes section' );
    ok( exists $data->{classes}{Counter}, 'Counter class is present' );
};

subtest 'emitted class carries its method + a return repr' => sub {
    my $c = $data->{classes}{Counter};
    my $methods = $c->{methods} // {};
    ok( exists $methods->{get}, 'method get present' );

    my $gk = $methods->{get};
    my $g  = $data->{methods}{$gk};
    ok( $g, 'get method-ref points at a real graph' );

    # The get graph returns the field $n (a FieldAccess). The producer does not
    # stamp the field read directly -- Chalk's _replay_classes seeds the field
    # read repr from the class field type. So the producer contract is: the
    # field carries a declared type. $n defaults to 0 (Int).
    my ($field) = ( $c->{fields} // [] )->@*;
    is( $field->{type}, 'Int', 'field $n carries its declared type Int' );

    my %by_id = map { $_->{id} => $_ } $g->{nodes}->@*;
    my ($ret_id) = ( $g->{returns} // [] )->@*;
    ok( defined $ret_id, 'get graph has a return' );
    my $ret = $by_id{$ret_id};
    # Return inputs are [control, value]; the returned value is the last input.
    my $val = $ret->{inputs}[-1];
    my $vn  = $by_id{$val};
    is( $vn->{op}, 'FieldAccess',
        'get returns a FieldAccess (Chalk stamps its repr from the field type)' );
};

subtest 'the main sub still carries the get Call with the class_name' => sub {
    my $g = $data->{methods}{'main::corpus_case'};
    ok( $g, 'main::corpus_case emitted' );
    my ($get_call) =
      grep { ( $_->{op} // '' ) eq 'Call'
          && ( $_->{fields}{name} // '' ) eq 'get' } $g->{nodes}->@*;
    ok( $get_call, 'get Call node present' );
    is( $get_call->{fields}{class_name}, 'Counter',
        'get Call carries class_name Counter for MRO resolution' );
};

subtest 'does not over-emit internal SoN classes' => sub {
    my @names = sort keys $data->{classes}->%*;
    # `main` now appears because every sub is recorded under its owning class,
    # and a file-level sub belongs to class main ("all code belongs to a
    # class" -- Chalk::MOP seeds an implicit main for exactly this reason).
    # That is the sub-metadata channel, not the stash leak this subtest exists
    # to catch, so assert the GUARD rather than the old exact set.
    is( \@names, ['Counter', 'main'],
        'only the referenced class (plus main) is emitted, not the whole stash' );
    # The guard stated directly: no internal producer class leaks.
    ok( !grep( { /^(?:SoN|B|JSON|Test)\b/ } @names ),
        'no internal producer classes leak into the wire' )
        or diag "leaked: @names";
    # main owns the file-level sub; Counter's `get` is a METHOD and must not
    # be recorded as one of its subs.
    is( [ sort keys( ( $data->{classes}{main}{subs} // {} )->%* ) ],
        ['corpus_case'], 'main carries exactly the file-level sub' );
    is( [ sort keys( ( $data->{classes}{Counter}{subs} // {} )->%* ) ],
        [], 'a class method is not recorded as a sub' );
};

done_testing();
