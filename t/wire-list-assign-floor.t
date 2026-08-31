# ABOUTME: A list assignment yields the LHS in list context, a count in scalar.
# ABOUTME: Floored to their join; a scalar assign keeps its stronger RHS type.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;
use SoN::IR::Stamp;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub assigns_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    return [ grep { ( $_->{op} // '' ) eq 'Assign' }
             map  { ( $wire->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $wire->{methods} // {} )->%* ) ];
}

# THE DEFECT. `my ($a,$b,$c) = @_` in perl's t/base/num.t reached the wire as
# Assign:Unknown with all three targets stamped Num. Nothing about it was
# unknowable -- a list assignment simply had no answer anywhere.
#
# perl gives it TWO, by context, measured:
#     scalar:  ( ($a,$b,$c) = @src )  is 3   -- the COUNT of RHS elements
#     list:    ( ($a,$b,$c) = @src )  is the assigned LHS
# so the sound answer is their join, and the LATTICE decides what that is.
#
# THIS IS A FLOOR, NOT A TABLE ROW. A two-input scalar assign is already
# stamped from its RHS by the walker (`$a[0] = "foo"` is Assign:Str), which is
# strictly more precise. A blanket row would overwrite that; a floor only ever
# fills an Unknown.
subtest 'a list assignment is floored to the join of its two contexts' => sub {
    my $lub = SoN::IR::Stamp::join(
        SoN::IR::Stamp->new( type => 'Int' ),     # scalar ctx: the count
        SoN::IR::Stamp->new( type => 'List' ),    # list ctx:   the LHS
    )->type;

    my $assigns = assigns_for( q{sub f { my ($a,$b,$c) = @_; $a } f(1,2,3);},
                               'list-assign' );
    ok scalar($assigns->@*), 'the graph has an Assign' or return;
    is scalar( grep { ( $_->{stamp} // '' ) eq 'Unknown' } $assigns->@* ), 0,
        'no Assign reaches the wire Unknown';
    ok scalar( grep { ( $_->{stamp} // '' ) eq $lub } $assigns->@* ),
        "the list assign carries the lattice's join ($lub)";
};

# THE STRONGER ANSWER SURVIVES. Without this the floor could flatten every
# scalar assignment to the same join.
subtest 'a scalar assignment keeps its RHS type' => sub {
    my $assigns = assigns_for( q{my @a; $a[0] = "foo"; print $a[0];},
                               'scalar-assign' );
    ok scalar( grep { ( $_->{stamp} // '' ) eq 'Str' } $assigns->@* ),
        'a scalar assign of a Str is still Str, not floored';
};

done_testing;
