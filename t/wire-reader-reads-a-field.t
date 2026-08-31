# ABOUTME: A :reader accessor reads a FIELD, so its body is a FieldAccess.
# ABOUTME: perl's generated reader uses a real pad slot, which misreported it.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub wire_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use feature 'class'; no warnings 'experimental::class';\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

my $SRC = q{
class P { field $x :param :reader = 1; }
class Q { field $y :param = 1; method get { $y } }
my $p = P->new(x => 5); my $q = Q->new(y => 6);
print $p->x, $q->get;
};

# THE DEFECT, reported by chalk and reproduced here. Two methods that do the
# same thing -- return a field -- reach the wire as different node kinds:
#
#     P::x    (generated :reader)  Start, PadAccess:Scalar,   Return
#     Q::get  (explicit method)    Start, FieldAccess:Scalar, Return
#
# A PadAccess is a LEXICAL read and the field lives in the object, so the
# reader graph describes reading somewhere the value is not.
#
# THE PRODUCER WAS NOT INVENTING THIS. perl's own metadata disagrees between
# the two: measured on 5.42.0, the pad entry for `$y` in Q::get answers
# PadnameFIELDINFO (is_field YES), while `$x` in P::x has FLAGS 0x0 and answers
# no. _make_pad_or_field asks that question and correctly gets "not a field",
# so the fix cannot come from the pad -- it comes from the CLASS RECORD, which
# knows the reader's fieldix and that is_reader is true.
subtest 'a reader body is a FieldAccess, like the method it mirrors' => sub {
    my $wire = wire_for( $SRC, 'reader' );
    my $ops  = sub ( $g ) {
        [ map { $_->{op} } ( $wire->{methods}{$g}{nodes} // [] )->@* ]
    };

    ok scalar( grep { $_ eq 'FieldAccess' } $ops->('Q::get')->@* ),
        'the explicit method reads a FieldAccess (unchanged)';
    ok scalar( grep { $_ eq 'FieldAccess' } $ops->('P::x')->@* ),
        'and the generated reader now does too';
    is scalar( grep { $_ eq 'PadAccess' } $ops->('P::x')->@* ), 0,
        'the reader no longer reads a pad it does not own';
};

# The node must carry the field it actually reads, not merely be the right kind.
subtest 'the reader FieldAccess names its field' => sub {
    my $wire = wire_for( $SRC, 'reader-idx' );
    my ($fa) = grep { ( $_->{op} // '' ) eq 'FieldAccess' }
               ( $wire->{methods}{'P::x'}{nodes} // [] )->@*;
    ok $fa, 'the reader has a FieldAccess' or return;

    my ($field) = grep { ( $_->{name} // '' ) eq '$x' }
                  ( $wire->{classes}{P}{fields} // [] )->@*;
    ok $field, 'the class record has the field' or return;

    is $fa->{fields}{field_index}, $field->{fieldix},
        'it carries the fieldix the class record declares';
    is $fa->{fields}{field_stash}, 'P', 'and the declaring class';
};

# THE SECOND HALF. A :reader is a callable method, so consumers must be able to
# find it in the class record -- chalk added a MOP::Field->is_reader accessor
# purely to recover a return type the `methods` record should have carried.
subtest 'a reader is recorded as a method of its class' => sub {
    my $wire = wire_for( $SRC, 'reader-methods' );
    my $m    = $wire->{classes}{P}{methods} // {};
    ok exists $m->{x}, 'P::x appears in classes.P.methods';
    is $wire->{classes}{Q}{methods}{get} ? 1 : 0, 1,
        'and an explicit method still does';
};

done_testing;
