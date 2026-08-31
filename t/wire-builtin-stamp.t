# ABOUTME: A builtin Call is typed by its NAME, not by the node ~180 ops share.
# ABOUTME: Pins what the builtin index answers, and what it honestly refuses.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

use B::SoN::TypeLibrary;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub wire_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

# The stamp on the first builtin Call of the given name, anywhere in the wire.
sub builtin_stamp ( $src, $name, $builtin ) {
    my $wire = wire_for( $src, $name );
    for my $g ( sort keys( ( $wire->{methods} // {} )->%* ) ) {
        for my $n ( ( $wire->{methods}{$g}{nodes} // [] )->@* ) {
            next unless $n->{op} eq 'Call';
            next unless ( $n->{fields}{dispatch_kind} // '' ) eq 'builtin';
            next unless ( $n->{fields}{name}          // '' ) eq $builtin;
            return $n->{stamp};
        }
    }
    return undef;
}

# THE DEFECT. ~180 optree ops collapse to ONE generic `Call` node, and
# TypeLibrary was keyed by IR NODE NAME alone -- so it could give exactly one
# answer for all 180, and that answer was Unknown. Every builtin reached the
# wire untyped, and poisoned its consumers on the way.
#
# The key was already on the node: a builtin Call carries dispatch_kind
# 'builtin' and its name. These pin that the index now reads it.

subtest 'a builtin with a fixed result is typed by name' => sub {
    is builtin_stamp( 'my @a = (1,2,3); my $s = join(",", @a); print "$s\n";',
        'bjoin', 'join' ), 'Str',
        'join is Str however its list is typed';

    is builtin_stamp( 'my $i = index("abc", "b"); print "$i\n";',
        'bindex', 'index' ), 'Int',
        'index is Int -- a position, and -1 on a miss is still Int';

    is builtin_stamp( 'my $s = "hello"; my $n = ($s =~ tr/l/L/); print "$n\n";',
        'btrans', 'trans' ), 'Int',
        'tr/// COUNTS what it changed';

    is builtin_stamp( 'my $s = "hello"; my $r = ($s =~ tr/l/L/r); print "$r\n";',
        'btransr', 'transr' ), 'Str',
        'and tr///r RETURNS the new string -- perl gives them separate op names';
};

# `abs` IS A JOIN, NOT A FIXED ROW. This is the one that a careless table gets
# wrong: abs(-5) is 5 (IOK) and abs(-5.5) is 5.5 (NOK), so the result is a
# function of the OPERAND, capped at Num -- exactly Negate's shape. A fixed Num
# row would WIDEN abs of an Int, which is the regression the whole exercise
# forbids.
subtest 'abs preserves its operand type, capped at Num' => sub {
    is B::SoN::TypeLibrary::result_for( [ 'Call', 'abs' ], 'Int' ), 'Int',
        'abs of an Int is an Int, not a Num';
    is B::SoN::TypeLibrary::result_for( [ 'Call', 'abs' ], 'Num' ), 'Num',
        'abs of a Num is a Num';
    is B::SoN::TypeLibrary::result_for( [ 'Call', 'abs' ], 'Scalar' ), 'Num',
        'and a join that escaped the cap comes back down to it';
    is B::SoN::TypeLibrary::result_for( [ 'Call', 'abs' ] ), undef,
        'a join op cannot answer without operands -- an honest GAP';
};

# PERL SETTLES EVERY ROW. Asserted directly so a future edit that "simplifies"
# the table has to argue with perl rather than with a comment.
subtest 'perl agrees with the rows we chose' => sub {
    is join( ',', 1, 2, 3 ), '1,2,3', 'join yields a string';
    is join( ',' ), '', 'and an empty list is "" -- still a string, not undef';
    is index( 'abc', 'z' ), -1, 'a missed index is -1, an Int like any hit';
    is abs(-5),   5,   'abs of an integer is an integer';
    is abs(-5.5), 5.5, 'abs of a fraction is a fraction -- so abs is a join';
    my $s = 'hello';
    is( ( $s =~ tr/l/L/ ),  2,       'tr/// yields a count' );
    is( ( $s =~ tr/l/L/r ), 'heLLo', 'tr///r yields the string' );
};

# WHAT THE TABLE REFUSES, AND WHY. An honest Unknown beats a guess -- 89b0008
# reverted a guessed Scalar for exactly this reason. Each of these appears as a
# reachable untyped builtin Call over perl's t/base, t/cmd, t/comp and
# t/opbasic, so each is a row someone will be tempted to add. Pinned so that
# adding one has to come with the argument for it.
subtest 'the table declines what it cannot say soundly' => sub {
    my %why = (
        # One op name, two types, decided by context the table cannot see.
        readline => 'scalar context is one line, list context is all of them',
        keys     => 'scalar context is a count, list context is the keys',
        caller   => 'scalar context is the package, list context is 3+ values',

        # One op name, two results, separated only by a flag on the op.
        subst => 's///g returns a count; s///gr returns the string',

        # undef on failure -- and Boolean descends from Str in this lattice,
        # not from Undef, so Boolean would be WRONG, not merely wide.
        open  => 'returns undef on failure, which no Boolean row admits',
        close => 'likewise',
        eof   => 'likewise',
        ftchr => 'a file test on a missing file is undef, and -s is a count',

        # The value belongs to the program, not to the operator.
        require   => 'a do-FILE returns the file last expression',
        dofile    => 'likewise',
        tie       => 'returns the tied object',
        mapstart  => 'a list whose size depends on the block',
        grepstart => 'likewise',
        prototype => 'a Str, or undef when there is no prototype',
    );

    for my $builtin ( sort keys %why ) {
        my $fixed = B::SoN::TypeLibrary::result_for( [ 'Call', $builtin ] );
        my $join =
            B::SoN::TypeLibrary::result_for( [ 'Call', $builtin ], 'Int' );
        ok !defined $fixed && !defined $join,
            "$builtin is left Unknown: $why{$builtin}";
    }
};

# THE BOOLEAN QUESTION, SETTLED. Several refusals above rest on it, so it is
# asserted rather than asserted-about.
subtest 'Boolean does not admit undef in this lattice' => sub {
    require SoN::IR::Stamp;
    my $bool  = SoN::IR::Stamp->new( type => 'Boolean' );
    my $undef = SoN::IR::Stamp->new( type => 'Undef' );
    ok !$undef->is_subtype_of($bool),
        'Undef is not a Boolean -- so a builtin returning undef on failure '
      . 'cannot be typed Boolean';
};

# ONE PUBLIC QUESTION. perigrin's ruling: the builtin index is internal and
# encapsulated by TypeLibrary. A caller asks result_for and gets an answer; it
# never learns which of the two indices held it.
subtest 'the builtin index is not reachable except through result_for' => sub {
    for my $leak (qw(result_for_builtin builtin_result_type builtin_signature)) {
        ok !B::SoN::TypeLibrary->can($leak),
            "no public $leak -- the index stays internal";
    }

    # The node index still answers for node names, unchanged.
    is B::SoN::TypeLibrary::result_for('Concat'), 'Str',
        'a node name still routes to the node index';
    is B::SoN::TypeLibrary::result_for( [ 'Call', 'no_such_builtin' ] ), undef,
        'and an unknown builtin says nothing rather than guessing';
};

done_testing;
