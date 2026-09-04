# ABOUTME: A constant folded to perl's shared PL_sv_undef is a B::SPECIAL with no FLAGS method.
# ABOUTME: Index 1 is undef; only 2 (yes) and 3 (no) were handled, so index 1 crashed the walker.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub translate ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) };
    return ($data ? $data->{methods}{'main::__PROGRAM__'} : undef, $err);
}

# perl's shared SVs reach a const op as a B::SPECIAL whose index names which
# one -- and a B::SPECIAL has no FLAGS method, so anything reaching the
# flag dispatch dies with "Can't locate object method FLAGS".
#
#     0 Nullsv   1 &PL_sv_undef   2 &PL_sv_yes   3 &PL_sv_no
#
# 2 and 3 were handled (a folded comparison keeps its boolean-ness) and 0 is
# caught by the falsy-$$sv guard, but 1 is TRUTHY and had no arm -- so it fell
# through to ->FLAGS and crashed. An INTERNAL ERROR, which is worse than a GAP:
# it fires before any honest refusal could and names a site that is not the
# cause.
#
# perl's own t/comp/fold.t installs one deliberately: `$::{u} = \undef` puts a
# reference to undef in the stash, and `1 + u` folds against it.
subtest 'a constant folded to PL_sv_undef does not crash the walker' => sub {
    my ($g, $err) = translate(<<'SRC');
BEGIN { $main::{u} = \undef }
my $x = 1 + u;
print "$x\n";
SRC
    unlike $err, qr/INTERNAL ERROR/, 'it does not crash' or diag $err;
    unlike $err, qr/FLAGS/, '... and not on the FLAGS dispatch';
    ok defined $g, 'it translates' or return;

    # THE CONSTANT MUST BE UNDEF, not a fabricated string or zero. perl adds
    # undef as 0 here, so a wrong decode would still print 1 and hide itself.
    my @consts = grep { $_->{op} eq 'Constant' } $g->{nodes}->@*;
    ok scalar(grep { ($_->{fields}{const_type} // '') eq 'undef' } @consts),
        'the shared undef decodes as an undef Constant'
        or diag join ' ', map { $_->{fields}{const_type} // '?' } @consts;
};

done_testing;
