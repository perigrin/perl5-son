# ABOUTME: tools/gates.sh's chalk-suite gate fails when chalk's t/bootstrap/ir/wire-verify.t
# ABOUTME: skipped: a verifier that never ran is not a pass.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

# WHY (audit 2026-11-22, risk 10). chalk's wire-verify.t is `plan skip_all`
# when it cannot find B::SoN, as every producer-dependent chalk test is; prove
# calls a skipped file a success, so the suite gate counted it as passing.
# The gate must see the file run its tests. A stand-in chalk with only that
# file, once skipping and once running, holds it.
sub gate ($body) {
    my $chalk = tempdir( CLEANUP => 1 );
    my $out   = tempdir( CLEANUP => 1 );
    make_path( "$chalk/lib/Chalk", "$chalk/t/bootstrap/ir" );
    open my $o, '>', "$chalk/t/bootstrap/ir/wire-verify.t" or die $!;
    print $o "use Test::More;\n$body\n";
    close $o;
    system("git -C '$chalk' init -q") == 0 or die 'git init';
    my $summary = qx(tools/gates.sh --chalk '$chalk' --out '$out/g' --only chalk-suite --jobs 1 2>&1);
    return ( $? >> 8, $summary );
}

my ( $rc, $s ) = gate(q{plan skip_all => 'perl5-son not found';});
isnt $rc, 0, 'wire-verify.t skipped: the gates fail' or diag $s;
like $s, qr/^chalk-suite\s+MISS\b.*\n.*wire-verify\.t.*(?:skipped|no tests)/m, 'and the chalk-suite line says it did not run' or diag $s;

( $rc, $s ) = gate(q{ok 1, 'ran'; done_testing;});
is $rc, 0, 'wire-verify.t ran its tests: the gates pass' or diag $s;
like $s, qr/^chalk-suite\s+PASS\b/m, 'chalk-suite PASS' or diag $s;

done_testing;
