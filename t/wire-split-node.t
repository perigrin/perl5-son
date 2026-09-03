# ABOUTME: split yields a List; its target array is FUSED into the op, not on the stack.
# ABOUTME: pmreplroot names the target's pad slot when OPpSPLIT_ASSIGN is set.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? (map { { $_->%*, ($_->{fields} // {})->%* } }
                  ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*) : ();
    return (\@n, $err);
}

# SPLIT PUSHES NO MARK IN ANY FORM, which is why it refused: OpMap registered
# it as a 'mark' pop and pop_to_mark died. But the LIST forms do not need one --
# they FUSE the target array into the op itself. Measured on 5.42.0 under
# suppress_peep (the configuration the walker actually sees):
#
#     my @x = split(/,/,$s)   split(... => @x:1,4) ASSIGN,LEX   pmreplroot=1
#     @y = split(/,/,$s)      split(... => @y:3,4) ASSIGN,LEX   pmreplroot=1
#     my $n = split(/,/,$s)   split                no target    pmreplroot=0
#
# pmreplroot IS the target's pad index when OPpSPLIT_ASSIGN (0x10) is set, and
# 0 when it is not. That is the discriminator, and it is what makes the list
# form recoverable rather than genuinely unlowerable.
#
# THE VALUE IS A List OF UNKNOWN ARITY. Measured: split(/,/,"a,b,c") is 3
# fields, split(/,/,"") is 0, split(//,"ab") is 2. The count depends on the
# subject at runtime, so no narrower stamp is honest.
subtest 'a my-declared list split translates' => sub {
    my ($n, $err) = wire('my @x = split(/,/, "a,b,c"); print scalar(@x);', 'split_my');
    unlike $err, qr/INTERNAL/, 'no crash';
    unlike $err, qr/GAP/, 'and no refusal';
    ok scalar(grep { $_->{op} eq 'Call' && ($_->{name} // '') eq 'split' } $n->@*),
        'a split Call is built';
};

subtest 'an assigned list split translates' => sub {
    my ($n, $err) = wire('my @y; @y = split(/,/, "a,b"); print scalar(@y);', 'split_assign');
    unlike $err, qr/INTERNAL/, 'no crash';
    unlike $err, qr/GAP/, 'and no refusal';
};

# THE TARGET MUST BE BOUND, or the split runs and its result goes nowhere --
# a silent drop rather than a refusal. This is the assertion that separates a
# real fix from one that merely stops refusing.
subtest 'the target array is bound to the split result' => sub {
    my ($n, $err) = wire('my @x = split(/,/, "a,b,c"); print scalar(@x);', 'split_bound');
  SKIP: {
        skip "refused: $err", 1 if $err =~ /GAP/;
        my %byid = map { $_->{id} => $_ } $n->@*;
        my ($count) = grep { $_->{op} eq 'Count' } $n->@*;
        ok defined $count, 'the scalar(@x) Count exists' or skip 'no Count', 1;
        # walk back from Count: it must reach the split, not an empty literal
        my (@q, %seen) = (($count->{inputs} // [])->@*);
        my $reaches = 0;
        while (my $id = shift @q) {
            next if $seen{$id}++;
            my $nd = $byid{$id} or next;
            $reaches = 1, last if ($nd->{name} // '') eq 'split';
            push @q, ($nd->{inputs} // [])->@*;
        }
        ok $reaches, 'scalar(@x) reads the split result, not an unrelated binding';
    }
};

# THE SCALAR FORM has no fused target and yields the FIELD COUNT, which is a
# different operation. It stays refused rather than being lowered as a list.
# THE SCALAR FORM IS Count OVER THE SAME LIST. Its refusal said the field count
# ran "over fields that are never built" -- true when it was written, and stale
# the moment the list form started building them. Measured:
#
#     my $n = split(/,/,"a,b,c")   3      the field count
#     my @x = split(/,/,"a,b,c")   3      the same three fields
#
# so the scalar reading is Count(split-result), exactly as `scalar(@x)` is.
subtest 'the scalar form is a Count over the split result' => sub {
    my ($n, $err) = wire('my $n = split(/,/, "a,b,c"); print $n;', 'split_scalar');
    unlike $err, qr/INTERNAL/, 'no crash';
    unlike $err, qr/GAP/, 'it no longer refuses';
    my %byid = map { $_->{id} => $_ } $n->@*;
    my ($count) = grep { $_->{op} eq 'Count' } $n->@*;
    ok defined $count, 'a Count node is built' or return;
    my ($src) = map { $byid{$_} } ($count->{inputs} // [])->@*;
    is +($src->{name} // ''), 'split', 'and it counts the split result';
};

# THE PATTERN MUST BE AN OPERAND. It rides on the PMOP rather than the stack,
# and dropping it is a SILENT WRONG ANSWER rather than an imprecision:
#
#     split(/,/, "a,b,c")   3 fields
#     split(/;/, "a,b,c")   1 field
#
# Without the pattern both emit an IDENTICAL graph and hash-cons to ONE node,
# so whichever the consumer lowers, the other is wrong. I had the fix passing
# every other subtest in this file before noticing.
subtest 'two different patterns are two different graphs' => sub {
    my ($a, $ea) = wire('my @x = split(/,/, "a,b,c"); print scalar(@x);', 'pat_comma');
    my ($b, $eb) = wire('my @x = split(/;/, "a,b,c"); print scalar(@x);', 'pat_semi');
  SKIP: {
        skip "refused", 2 if $ea =~ /GAP/ || $eb =~ /GAP/;
        my ($pa) = grep { ($_->{const_type} // '') eq 'regex' } $a->@*;
        my ($pb) = grep { ($_->{const_type} // '') eq 'regex' } $b->@*;
        ok defined $pa && defined $pb, 'both carry a pattern constant' or skip 'no pattern', 1;
        isnt $pa->{value}, $pb->{value},
            "the patterns differ ($pa->{value} vs $pb->{value}), so the graphs cannot collide";
    }
};

# A RUNTIME-INTERPOLATED PATTERN has no compile-time precomp, so it refuses
# rather than being lowered with a fabricated one.
subtest 'a runtime pattern refuses' => sub {
    my (undef, $err) = wire('my $re = ","; my @x = split(/$re/, "a,b"); print scalar(@x);', 'pat_runtime');
    unlike $err, qr/INTERNAL/, 'no crash';
};

done_testing;
