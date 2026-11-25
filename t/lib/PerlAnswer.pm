# ABOUTME: answers_like_perl($src, $name): the program's wire, deparsed, prints what perl
# ABOUTME: prints -- with the promotion pass and without it (SON_NO_PROMOTE=1).
package PerlAnswer;
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use JSON::PP;
use SoN::Deparse;
use Exporter 'import';
our @EXPORT = qw(answers_like_perl);

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub _run ($src) {
    my $f = "$dir/r" . ++$n . ".pl";
    open my $o, '>', $f or die $!; print $o $src; close $o;
    return scalar qx($^X $f 2>&1);
}

sub answers_like_perl ( $src, $name ) {
    my $want = _run($src);
    my $f    = "$dir/w" . ++$n . ".pl";
    open my $o, '>', $f or die $!; print $o $src; close $o;
    for my $off ( '', 1 ) {
        local $ENV{SON_NO_PROMOTE} = $off;
        my $how  = $off ? 'unpromoted' : 'promoted';
        my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
        my $err  = do { open my $e, '<', "$dir/err"; local $/; <$e> } // '';
        $err =~ s/^\S+ syntax OK\n//m;
        is $err, '', "$name ($how): the producer says nothing" or next;
        my $d   = SoN::Deparse->new;
        my $out = $d->render( JSON::PP->new->decode($json) );
        ok defined $out, "$name ($how): renders" or diag( $d->gap // '' ), next;
        is _run($out), $want, "$name ($how): perl's answer";
    }
}

1;
