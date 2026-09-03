# ABOUTME: A qr// whose interpolation was FOLDED must not consume the caller's mark.
# ABOUTME: Guards an internal error that a stack-depth test cannot distinguish.
use 5.42.0;
use utf8;
use Test::More;
use File::Spec;

# RUN FROM perl5/t, NOT FROM HERE. comp/use.t does `chdir 't'` and sets @INC
# to ../lib and lib, then loads test_use.pm from t/lib -- so from any other
# directory it dies in BEGIN and never reaches the qr at all, reporting a
# phantom failure that has nothing to do with this fix.
my $T   = '/home/perigrin/dev/perl5/t';
my $USE = "$T/comp/use.t";
plan skip_all => "perl source tree not present at $USE" unless -r $USE;

# WHOSE MARK IS IT? A qr with runtime parts owns the mark those parts sit
# behind; a qr that is only a CALL ARGUMENT does not, and claiming the caller's
# leaves its entersub with none. That surfaces as "No mark on mark stack" -- an
# INTERNAL error, which the refuse-or-lower contract forbids: a construct we
# cannot handle must produce a named GAP, never a crash.
#
# A DEPTH TEST CANNOT DECIDE IT. `\Q...\E` compiles to
# regcomp -> quotemeta -> multiconcat, and multiconcat FOLDS every part into
# one value before qr runs. So the stack holds the call's first argument and
# the folded pattern -- two values above the mark, byte-identical in shape to a
# genuine two-part interpolation. The optree still knows: a pattern assembled
# at RUNTIME pushes its own pushmark inside the regcomp subtree, a folded one
# does not.
#
# ASSERTED AGAINST PERL'S OWN FILE rather than a reduction. Every reduction
# attempted -- the same call with the same prototype, the same qr, the same
# preceding void eval -- compiles to a shape that does NOT reproduce, so a
# hand-written case would pass with the fix reverted and guard nothing. The
# corpus file is the smallest thing known to exercise it.
my $lib = File::Spec->rel2abs('lib');
my $out = qx{cd $T && $^X -I$lib -MO=SoN,json,package=main comp/use.t 2>&1 1>/dev/null};

unlike $out, qr/No mark on mark stack/,
    'a folded-interpolation qr does not steal the enclosing call mark';
unlike $out, qr/INTERNAL ERROR/,
    '... and comp/use.t reports no internal error at all';

# THE REFUSAL THAT REPLACED IT IS THE POINT. The file still does not translate
# fully, but it now says WHICH construct stopped it instead of dying inside the
# stack simulator. A GAP is a to-do with a diagnostic; an internal error is a
# bug that hides one.
like $out, qr/GAP:/,
    '... it refuses with a named GAP instead';

done_testing;
