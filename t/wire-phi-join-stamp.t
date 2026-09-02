# ABOUTME: A merge Phi is stamped with the join of the values that reach it.
# ABOUTME: The join already existed at two construction sites; this makes it uniform.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;
use SoN::IR::Stamp;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire_for ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

# The merge Phi over the named variable. Sources here keep an EFFECT in each
# arm (a print), because a two-arm if/else whose arms are bare values folds to
# a TernaryExpr select instead of a Region+Phi -- no Phi would exist to assert
# about. These shapes are taken from chalk's corpus, where they were measured.
sub merge_phis ($src, $name) {
    my $wire = wire_for($src, $name);
    return grep { $_->{op} eq 'Phi' && scalar(($_->{inputs} // [])->@*) == 2 }
           ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
}

# THE DEFECT. A Phi's type is the join of the values reaching it, and
# SoN::IR::Stamp::join is exactly that. The join was already applied at TWO
# construction sites (_patch_loop_phi, and the guarded-loop merge path) but
# nowhere else, so an ordinary if/else merge reached the wire Unknown -- even
# with both arms Int constants. 19 of the 233 measured wire Unknowns were Phis
# whose inputs were ALL already stamped.
subtest 'a merge of two Int arms is Int' => sub {
    my @p = merge_phis('my $n = 5; my $x = 0;
if ($n > 0) { print "pos\n"; $x = 1 } else { print "neg\n"; $x = 2 }
print "$x\n";', 'int_merge');
    ok @p >= 1, 'a merge Phi exists' or return;
    is $p[0]{stamp}, 'Int', 'both-Int arms join to Int';
};

# BILATERAL. Two Str arms must give Str -- a hardcoded type would pass above.
subtest 'a merge of two Str arms is Str' => sub {
    my @p = merge_phis('my $x = 5; my $s = "no";
if ($x > 3) { print "call\n"; $s = "yes" }
print "s=$s\n";', 'str_merge');
    ok @p >= 1, 'a merge Phi exists' or return;
    is $p[0]{stamp}, 'Str', 'both-Str arms join to Str';
};

# MIXED ARMS. The join must be the SUPERTYPE, not either arm's own type. A fix
# that copied arm 0's stamp would pass both subtests above and fail here.
subtest 'mixed arms join to their supertype' => sub {
    my @p = merge_phis('my $x = 5; my $v = 0;
if ($x > 3) { print "call\n"; $v = "s" }
print "v=$v\n";', 'mixed_merge');
    ok @p >= 1, 'a merge Phi exists' or return;
    is $p[0]{stamp}, 'Str', 'join(Int,Str) is Str, not Int';
};

# THE SAME RULE, THREE MORE NODE KINDS. `&&`, `||` and `//` each yield ONE OF
# THEIR OPERANDS rather than computing a new value, so their type is the join of
# the two -- the same question a Phi asks. They were Unknown for the same reason.
sub logical_stamp ($src, $name, $op) {
    my $wire = wire_for($src, $name);
    my ($n) = grep { $_->{op} eq $op }
              ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    return $n && $n->{stamp};
}

subtest 'a logical op joins its operands' => sub {
    is logical_stamp('my $a = 3; my $b = 7; say($a // $b);', 'dor', 'DefinedOr'),
        'Int', '// over two Ints is Int';
    is logical_stamp('my $a = 3; my $b = 7; say($a && $b);', 'and', 'And'),
        'Int', '&& over two Ints is Int';
    is logical_stamp('my $a = 3; my $b = 7; say($a || $b);', 'or', 'Or'),
        'Int', '|| over two Ints is Int';
};

# BILATERAL, and this is the case that matters for `//`: an undef LHS. Undef is
# a real lattice member, so join(Undef,Int) is a genuine supertype, not Unknown.
subtest 'a logical op over mixed operands joins to their supertype' => sub {
    my $s = logical_stamp('my $a = undef; my $b = 7; say($a // $b);',
                          'dor_undef', 'DefinedOr');
    isnt $s, 'Unknown', 'an Undef operand does not poison the join';
    isnt $s, 'Undef', 'nor does the result claim to be only Undef';
};

# THE CASCADE. Once `//` is typed, a merge that reads it stops being poisoned.
# This was measured: the corpus case below had a correctly-poisoned Phi whose
# real root was an Unknown DefinedOr one level down.
subtest 'typing a logical op unpoisons the merge above it' => sub {
    my @p = merge_phis('my $a = 3; my $x = $a // 0;
if ($x > 0) { print "p\n"; $x = 1 }
print "x=$x\n";', 'undef_merge');
    ok @p >= 1, 'a merge Phi exists' or return;
    isnt $p[0]{stamp}, 'Unknown',
        'the merge is typed once its DefinedOr arm is';
};

# AN UNKNOWN ARM POISONS THE JOIN, and must. join(Int, Unknown) is Unknown --
# claiming Int would assert a type one path cannot support. `shift` off @_ is
# the Array[Scalar] wall, genuinely untyped at the producer.
# AN UNKNOWN ARM POISONS THE JOIN, and must. join(Int, Unknown) is Unknown --
# claiming Int would assert a type one path cannot support. The arm here carries
# a value from `shift`, which is a Call: its type belongs to its callee, so no
# use-site constraint may fill it in. See the note in wire-selftyped-stamp.t.
# THE PREMISE ABOVE WAS ALREADY FALSE and this subtest was passing for the
# wrong reason. `shift` is NOT untyped: measured, its arm is Call:Scalar, and
# has been since the floor passes started typing it. The merge read Unknown
# only because nothing re-asked it after the floor -- so the subtest was
# measuring a PASS-ORDERING gap while claiming to measure poisoning.
#
# With the merge re-asked, join(Int,Scalar) = Scalar is the lattice's answer
# and the right one. The poisoning RULE is unchanged and is asserted directly
# below, against Stamp itself, so it cannot again be tested by proxy through a
# fixture whose arms turn out to be typed.
subtest 'the poisoning rule: an Unknown arm yields Unknown' => sub {
    is SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Int' ),
        SoN::IR::Stamp->new( type => 'Unknown' ),
    )->type, 'Unknown',
        'join(Int,Unknown) is Unknown -- claiming Int would assert a type one
         path cannot support';

    # And the merge pass must DECLINE rather than narrow when it sees one.
    my $wire = wire_for('sub g { my $u = shift; my $x = 0;
if ($u > 1) { print "hi\n"; $x = $u }
return $x }
print g(7), "\n";', 'poisoned');
    my %by = map { $_->{id} => $_ } ($wire->{methods}{'main::g'}{nodes} // [])->@*;
    my @p = grep { $_->{op} eq 'Phi' && scalar(($_->{inputs} // [])->@*) == 2 }
            values %by;
    ok @p >= 1, 'a merge Phi exists' or return;

    # Whatever its arms turn out to be, the Phi must equal their join -- never
    # one arm picked over the other.
    my @arms = map { $by{$_}{stamp} // 'Unknown' } ($p[0]{inputs} // [])->@*;
    my $lub = SoN::IR::Stamp->new( type => $arms[0] );
    $lub = SoN::IR::Stamp::join( $lub, SoN::IR::Stamp->new( type => $_ ) )
        for @arms[ 1 .. $#arms ];
    is $p[0]{stamp}, $lub->type,
        "the merge is the join of [@arms], not either arm alone";
};

done_testing;
