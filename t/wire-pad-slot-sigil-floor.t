# ABOUTME: A pad slot's declared type is supplied by _declared_slot_type, NOT stamped.
# ABOUTME: Stamping it pre-empts the backward-inference meet and widens parameters.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub pads_of ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
    my $w = ($out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return [] unless $w;
    return [ grep { $_->{op} eq 'PadAccess' }
             map  { $_->{nodes}->@* } values $w->{methods}->%* ];
}

# WHY A PAD SLOT IS LEFT Unknown, and why that is right.
#
# The sigil IS a floor -- measured on 5.42.0:
#
#     my $p = shift    receives Int Str Num Undef ArrayRef HashRef CodeRef
#                      Regex; every one joins to Scalar, because perl flattens
#                      arguments and a $ slot holds exactly ONE scalar
#     my @a = @_       reftype(\@a) is ARRAY, including for f()
#     my %h = @_       reftype(\%h) is HASH,  including for f()
#
# So "a parameter should be at least Scalar" is a correct observation. But
# B::SoN::_declared_slot_type ALREADY returns Scalar for every PadAccess, and
# deliberately does NOT write it onto the node -- because the backward
# inference pass skips any node whose stamp is not Unknown, and MEETS the
# declared type with the use-site requirement instead:
#
#     sub add1 { my ($x) = @_; $x + 1 }    meet(Scalar, Num) = Num
#
# Unknown on the node is therefore a HANDSHAKE, not an absence: it is how the
# producer says "the declaration alone does not decide this; go and meet it
# with the use". Stamping the floor makes the parameter come out Scalar --
# strictly WIDER than what the body proves.
#
# This test exists because I made that change and it broke
# t/wire-backward-inference.t in exactly that way. Pinned so the next reader
# who notices the same "missing" floor finds the reason rather than the hole.

subtest 'a parameter is narrowed by its use, not floored at its sigil' => sub {
    my $p = pads_of('sub add1 { my ($x) = @_; return $x + 1 } print add1(5);',
                    'sf-param');
    my ($pad) = grep { my $f = $_->{fields} // {};
        ($f->{sigil} // '') eq '$' && ($f->{symbol} // '') eq 'x' } $p->@*;
    ok $pad, 'the $x read exists' or return;
    is $pad->{stamp}, 'Num',
        'Num from `$x + 1` -- meet(Scalar, Num), not the bare Scalar floor';
};

# A SLOT WITH NO USE-SITE CONSTRAINT STAYS Unknown, and that is the handshake
# doing its job rather than a gap: nothing in the body decides it.
subtest 'an unconstrained slot stays Unknown for the meet to fill' => sub {
    my $p = pads_of(
        'my %t; $t{a}=1; sub u { my %c = %t; scalar keys %c } print u();',
        'sf-hash');
    my @hp = grep { (($_->{fields} // {})->{sigil} // '') eq '%' } $p->@*;
    ok scalar(@hp), 'a % pad node is built' or return;
    ok +(grep { ($_->{stamp} // 'NONE') eq 'Unknown' } @hp),
        'left Unknown -- _declared_slot_type supplies Hash to the meet instead';
};

# A DECLARED VALUE STILL NARROWS THE TARGET. The declaration-target stamp
# (t/wire-vardecl-target-stamp.t) is a different mechanism and unaffected: it
# fires where the VALUE is known, which is not the parameter case.
subtest 'a declared value still types its target' => sub {
    my $p = pads_of('my $f = "abc$$"; print $f;', 'sf-decl');
    my ($pad) = grep { my $f = $_->{fields} // {};
        ($f->{sigil} // '') eq '$' && ($f->{symbol} // '') eq 'f' } $p->@*;
    ok $pad, 'the declaration target exists' or return;
    is $pad->{stamp}, 'Str', 'still Str';
};

done_testing;
