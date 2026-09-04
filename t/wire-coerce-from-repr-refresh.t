# ABOUTME: A Coerce's from_repr must match its input's FINAL stamp, not a snapshot.
# ABOUTME: The backend dispatches on from_repr; Unknown matches no arm and GAPs.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;
our $TODO;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub coerces_of ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
    my $w = ($out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return [] unless $w;
    my @out;
    for my $g ( values $w->{methods}->%* ) {
        my %by = map { $_->{id} => $_ } $g->{nodes}->@*;
        for my $n ( $g->{nodes}->@* ) {
            next unless $n->{op} eq 'Coerce';
            my $src_node = $by{ ($n->{inputs} // [])->[0] // '' };
            push @out, {
                from  => ($n->{fields} // {})->{from_repr} // '',
                to    => ($n->{fields} // {})->{to_repr}   // '',
                input => ($src_node // {})->{stamp} // 'NONE',
            };
        }
    }
    return \@out;
}

# from_repr IS A SNAPSHOT TAKEN TOO EARLY. _coerce_to_str reads the operand's
# stamp at CONSTRUCTION time and writes 'Unknown' when there is none -- which
# its own comment defends as honest, and which "obliges a later pass to NARROW
# it before anything is lowered".
#
# That pass was never written. Stamps ARE narrowed afterwards (backward
# inference, _stamp_derived, _stamp_merges all run later), so a Coerce ends up
# claiming Unknown over an input that is now Str, Int or Num. Measured across
# perl's t/base and t/comp: 210 such nodes.
#
# IT IS NOT COSMETIC. chalk's LLVM backend dispatches on from_repr directly --
# `Int->Num` emits sitofp, `Num->Int` emits fptosi -- and an Unknown source
# matches no arm. The FromOptree comment records this exact failure already
# happening once, when the field said 'Scalar': t/cmd/elsif.t failed as
# "Coerce[Scalar->Str] is not lowered" for calls that ARE typed Int by the
# time the loader sees them.
#
# THE FIELD CANNOT BE MUTATED IN PLACE: from_repr is part of content_hash, and
# a node's id IS that hash, so rewriting it would leave the node cached under a
# key that no longer matches. The refresh has to REBUILD and re-point the
# consumer, which is the pattern _insert_str_coercions already uses.

# KNOWN AND UNFIXED, with the reason recorded so the next attempt starts from
# the right place. Measured over perl's t/base and t/comp, 210 of 376 Coerce
# nodes claim from_repr=Unknown over an input that inference later typed.
#
# A REBUILD PASS WAS WRITTEN AND REVERTED. Rebuilding the node and re-pointing
# its consumers' inputs got 210 stale down to 57 -- but left the ORIGINAL node
# in the graph as well, because membership is by reachability and the old node
# is still reached another way. The result was TWO Coerce nodes over one value,
# one correct and one stale, which is worse than the stale field alone.
#
# That rebuild was the WRONG ORDER OF WORK, and so was the Graph-level node
# replacement operation designed to make it possible. Both were infrastructure
# to keep a field fresh that T1 does not need: from_repr is a CACHE of
# inputs[0]'s stamp, spelled like a declaration. Measured, 375 of 376
# non-Unknown values are exactly that stamp; the 1 exception is hardcoded and
# false (qr// over a deref, FromOptree.pm:3771, claims Str over a Scalar).
#
# The justification for the rebuild -- that chalk's backend dispatches on
# from_repr and Unknown matches no arm -- is a T2 symptom. This repo stops at
# T1. Removing the field is the T1-clean fix and needs no pass at all, but it
# is a wire change and belongs to the boundary conversation.
#
# See docs/plans/2026-09-04-from_repr-is-a-cache-t1-does-not-need.md
{
    local $TODO = 'from_repr is a redundant cache of the input stamp; the fix '
                . 'is to drop the field, which is a wire decision';
    my $cs = coerces_of('sub f { my ($x)=@_; print $x } f("a");', 'cf-param');
    my @typed = grep { $_->{input} ne 'NONE' && $_->{input} ne 'Unknown' } $cs->@*;
    is scalar(grep { $_->{from} ne $_->{input} } @typed), 0,
        'from_repr should match the input stamp';
}

subtest 'a Coerce over a genuinely untyped input still says Unknown' => sub {
    # An external callee's result cannot be typed here, and Unknown is the
    # honest answer -- the pessimistic top type, not a placeholder.
    my $cs = coerces_of('my $s = "x"; utf8::encode($s); print "$s!";', 'cf-ext');
  SKIP: {
        skip 'no Coerce in this shape', 1 unless scalar($cs->@*);
        my @unk = grep { $_->{input} eq 'Unknown' || $_->{input} eq 'NONE' }
                  $cs->@*;
        is scalar(grep { $_->{from} ne 'Unknown' } @unk), 0,
            'an untyped input keeps from_repr Unknown';
    }
};

subtest 'no Coerce claims a conversion from a type it already is' => sub {
    my $cs = coerces_of('sub g { my ($x)=@_; return $x . "!" } print g("a");',
                        'cf-noop');
    is scalar(grep { $_->{from} eq $_->{to} } $cs->@*), 0,
        'no from == to identity coercion is emitted';
};


# The hardcoded half of the same defect. qr// over a dereffed scalar ref emits
# Coerce(from_repr=Str -> Regex) whose input is stamped Scalar, and unlike the
# snapshot above this one cannot go stale -- it is wrong on construction and
# stays wrong whatever flows in. Everything else in that subgraph is correct:
# Ref/PostfixDeref models the deref, Scalar is honest for a deref result, and
# to_repr=Regex correctly says "compile this as a pattern".
{
    my $cs = coerces_of('my $p = "a"; my $r = \$p; my $re = qr/$$r/;', 'cf-qr');
    my ($qr) = grep { $_->{to} eq 'Regex' } $cs->@*;
    ok defined $qr, 'the qr// Coerce is in the graph' or return;

    local $TODO = 'from_repr is hardcoded Str at the qr// site regardless of '
                . 'what the input is stamped';
    is $qr->{from}, $qr->{input},
        'from_repr should match the input stamp at qr//';
}


done_testing;
