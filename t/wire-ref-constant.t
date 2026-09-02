# ABOUTME: A folded reference literal (\2) keeps its referent and is stamped a Ref.
# ABOUTME: It fell off _extract_const's flag dispatch and became Constant(undef)/string.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub const_nodes ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    # const_type/value live under `fields`, not at the node's top level.
    # Flattened here so each subtest reads one shape.
    return [ map { { $_->{fields}->%*, stamp => $_->{stamp} } }
             grep { $_->{op} eq 'Constant' }
             ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* ];
}

# THE DEFECT WAS A FABRICATION, NOT AN IMPRECISION. `\2` compiles to a single
# folded const whose SV is ROK (a reference). _extract_const dispatches on
# IOK/NOK/POK, none of which are set on a reference SV, so it fell through to
# the bottom `return (undef, Unknown, 'string')` -- reporting a STRING constant
# whose value is undef, for a value perl prints as SCALAR(0x...).
#
# Measured flags on 5.42.0: class=B::IV ROK=1 IOK=0 NOK=0 POK=0.
# The referent is fully readable: $sv->RV is a B::IV holding 2.
subtest 'a folded scalar-ref constant is not an undef string' => sub {
    my $consts = const_nodes('print \2;', 'refint');
    my ($ref) = grep { ($_->{const_type} // '') ne 'undef' } $consts->@*;
    ok defined $ref, 'a non-undef constant exists for \2' or return;
    isnt $ref->{const_type}, 'string',
        'a reference is not reported as a string constant';
    isnt $ref->{stamp}, 'Unknown',
        'a reference is not a hole -- its type is known statically';
};

# THE REFERENT MUST SURVIVE. Dropping it is the data loss: `\2` and `\3` became
# the same node. Whatever shape it takes on the wire, 2 must still be in there.
subtest 'the referent value is preserved' => sub {
    my $consts = const_nodes('print \2;', 'refval');
    my $found = grep { defined $_->{value} && "$_->{value}" =~ /\b2\b/ } $consts->@*;
    ok $found, 'the referent 2 survives to the wire'
        or diag explain [ map { { ct => $_->{const_type}, v => $_->{value}, s => $_->{stamp} } } $consts->@* ];
};

# TWO DIFFERENT REFERENTS MUST NOT COLLAPSE. The strongest statement of the
# drop: with the value fabricated as undef, \2 and \3 hash-cons to ONE node.
subtest 'distinct referents stay distinct' => sub {
    my $consts = const_nodes('print \2; print \3;', 'reftwo');
    my @refs = grep { ($_->{const_type} // '') !~ /^(undef|string)$/
                      || defined $_->{value} } $consts->@*;
    my %seen = map { ($_->{value} // 'undef') . "/" . ($_->{const_type} // '') => 1 } @refs;
    ok scalar(keys %seen) >= 2, '\2 and \3 are two different constants'
        or diag explain [ map { { ct => $_->{const_type}, v => $_->{value} } } $consts->@* ];
};

# THE OTHER REFERENT TYPES take the same path. Measured: \"str" is a B::PV
# referent (POK), \3.5 a B::NV (NOK). A fix keyed only on the integer case
# would leave these fabricating undef strings.
subtest 'string and number referents decode too' => sub {
    for my $case (['print \"str";', 'refstr', 'str'], ['print \3.5;', 'refnum', '3.5']) {
        my ($src, $name, $want) = $case->@*;
        my $consts = const_nodes($src, $name);
        my $found = grep { defined $_->{value} && index("$_->{value}", $want) >= 0 } $consts->@*;
        ok $found, "$name: the referent $want survives"
            or diag explain [ map { { ct => $_->{const_type}, v => $_->{value} } } $consts->@* ];
    }
};

# A PLAIN INTEGER CONSTANT IS UNAFFECTED. Asserted so the ROK arm cannot be
# written in a way that captures ordinary constants -- the flag dispatch order
# matters and IOK is tested before this fix's arm would be reached.
subtest 'an ordinary integer constant still decodes as an integer' => sub {
    my $consts = const_nodes('print 2;', 'plainint');
    my ($int) = grep { ($_->{const_type} // '') eq 'integer' } $consts->@*;
    ok defined $int, 'a plain 2 is still an integer constant';
    is $int->{value}, 2, 'with its value intact';
};

done_testing;
