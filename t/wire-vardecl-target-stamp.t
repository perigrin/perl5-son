# ABOUTME: A `my $x = EXPR` declaration target carries the declared value's type.
# ABOUTME: An lvalue Subscript already does; the pad slot was left Unknown.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub nodes_of ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
    my $w = ($out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return [] unless $w;
    return [ map { $_->{nodes}->@* } values $w->{methods}->%* ];
}

# A DECLARATION TARGET IS A LOCATION, and locations in this IR ARE stamped
# with the type of what lives there -- measured, an lvalue Subscript for
# `$z[0] = 9` carries Int. The pad slot a VarDecl wraps was the exception,
# reaching the wire Unknown while the value bound to it was fully typed:
#
#     my $f = "abc$$";
#       Concat    stamp=Str      <- the value, correctly typed
#       PadAccess stamp=Unknown  <- the slot it is bound to
#       VarDecl [PadAccess, Concat]
#
# Found by root-causing every remaining Unknown in base+comp: 314 of 426 are
# string eval (deliberate -- Code sits outside Scalar so the join IS Unknown,
# and it marks a refusal), and this was in the remainder.
#
# ONLY WHERE THE VALUE HAS A TYPE. A declaration whose value is itself Unknown
# leaves the slot Unknown too -- inventing one would be the change that
# improves a coverage number and makes the producer worse.

subtest 'a declared string slot is Str' => sub {
    my $n = nodes_of('my $f = "abc$$"; print $f;', 'vd-str');
    my ($pad) = grep { $_->{op} eq 'PadAccess'
                       && (($_->{fields} // {})->{varname} // '') eq '$f' } $n->@*;
    ok $pad, 'the declaration target is built' or return;
    is $pad->{stamp}, 'Str', 'and carries the declared value type';
};

# NOT EVERY DECLARATION BECOMES A NODE. `my $c = @a; print $c` emits no
# PadAccess for $c at all -- the binding is resolved at translation time and
# the Count flows straight to the Print. So the assertion has to be "IF a
# declaration target exists, it carries the type", not "a target exists".
# Asserting the node would test the walker's folding, not the stamp.
subtest 'a declared Int slot, where one is built, is Int' => sub {
    # A read in another statement forces the slot to survive as a node.
    my $n = nodes_of('my @a=(1,2,3); my $c = @a; my $d = $c + 0; print $d;',
                     'vd-int');
    my @pads = grep { $_->{op} eq 'PadAccess' } $n->@*;
  SKIP: {
        skip 'this shape folds its declarations away', 1 unless @pads;
        is scalar(grep { ($_->{stamp} // 'NONE') eq 'Unknown' } @pads), 0,
            'no declaration target is left Unknown';
    }
};

# THE VALUE ITSELF MUST BE UNDISTURBED. The slot takes the value's type; it
# does not replace or widen it.
subtest 'the bound value keeps its own stamp' => sub {
    my $n = nodes_of('my $f = "abc$$"; print $f;', 'vd-value');
    my ($cat) = grep { $_->{op} eq 'Concat' } $n->@*;
    ok $cat, 'the Concat is built' or return;
    is $cat->{stamp}, 'Str', 'and is still Str';
};

# AN UNTYPED VALUE LEAVES THE SLOT UNTYPED. Silence propagates; it is not
# replaced with a guess.
subtest 'an unknown value leaves the slot unknown' => sub {
    my $n = nodes_of('my $v = utf8::is_utf8("x"); my $d = $v; print $d ? 1 : 0;',
                     'vd-unknown');
    my ($pad) = grep { $_->{op} eq 'PadAccess'
                       && (($_->{fields} // {})->{varname} // '') eq '$d' } $n->@*;
  SKIP: {
        skip 'no such declaration in this shape', 1 unless $pad;
        ok +(($pad->{stamp} // 'NONE') =~ /^(Unknown|NONE|Scalar)$/),
            'an untyped value does not invent a slot type';
    }
};

done_testing;
