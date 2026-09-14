# ABOUTME: A call whose callee cannot be resolved refuses; it never names 'unknown'.
# ABOUTME: A code ref arriving as a parameter has no pad binding to look through.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub translate ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $f 2>&1 >/dev/null);
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    return ($err, eval { JSON::PP->new->decode($out) });
}

# 'unknown' IS NOT A SUB NAME. The entersub handler resolves a callee to its
# stash name, or through a pad binding to an AnonSub -- and falls back to the
# literal string 'unknown' when neither applies. Its own comment says what
# that costs: "the AnonSub was popped and dropped -- the exact silent wrong
# answer the old refusal was written to prevent".
#
# A CODE REF ARRIVING AS A PARAMETER hits that fallback, because there is no
# pad binding to look through -- measured on
# `sub take { my $f = shift; return $f->() }`:
#
#     3 Call  builtin shift   in=[ArgsSource, MemStart]
#     4 Call  direct  unknown in=[]          <- NO INPUTS AT ALL
#
# The callee is gone, and the emitted program would call a sub named
# `unknown` that nothing defines. A GAP is acceptable; this is not.
# TODO UNTIL THE PRODUCER REFUSES. The defect is measured and real; the fix
# is producer-side and not yet written. Marked TODO rather than deleted so the
# suite stays pristine while the finding stays pinned -- a defect nobody is
# reminded of is a defect that ships.
subtest 'a call through a parameter refuses' => sub {
    todo 'the entersub fallback still names a phantom sub' => sub {
    my ($err, $g) = translate(<<'SRC');
sub take { my $f = shift; return $f->() }
print take(sub { 9 }), "\n";
SRC

    like $err, qr/GAP:/, 'it refuses' or diag $err;

    # AND NAMES NOTHING. Even when refusing, no method in the wire may hold a
    # Call named 'unknown' -- a refusal that still emits the bad node is the
    # worst of both.
    if ($g) {
        my @bad;
        for my $m (sort keys $g->{methods}->%*) {
            push @bad, "$m:$_->{id}"
                for grep { ($_->{op} // '') eq 'Call'
                        && (($_->{fields} // {})->{name} // '') eq 'unknown' }
                    ($g->{methods}{$m}{nodes} // [])->@*;
        }
        is \@bad, [], 'no Call names `unknown`';
    }
    };
};

# A RESOLVABLE CALLEE MUST NOT REGRESS. Both forms the handler already
# resolves -- a named sub, and an anon sub held in a pad -- are the common
# cases and must keep working.
subtest 'resolvable callees still lower' => sub {
    my ($err) = translate('sub f { 7 } print f(), "\n";');
    unlike $err, qr/GAP:|INTERNAL/, 'a named sub' or diag $err;

    my ($err2, $g2) = translate('my $c = sub { 8 }; print $c->(), "\n";');
    unlike $err2, qr/GAP:|INTERNAL/, 'an anon sub through a pad' or diag $err2;

    if ($g2) {
        my ($call) = grep { ($_->{op} // '') eq 'Call'
                         && (($_->{fields} // {})->{dispatch_kind} // '') eq 'direct' }
                     ($g2->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
        ok $call, 'and it is a direct call' or return;
        isnt +(($call->{fields} // {})->{name} // ''), 'unknown',
            '... naming the body, not `unknown`';
    }
};

done_testing;
