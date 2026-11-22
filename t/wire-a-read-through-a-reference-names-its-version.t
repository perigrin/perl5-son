# ABOUTME: A read through a reference, of @_, of a glob slot names its memory version: a slice
# ABOUTME: of a deref, a returned count of one, `*$g{HASH}`, an element read again after its store.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;
use SoN::Verify;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# reads_at_versions($rule_re, [what, src], ...): each wire has no violation of
# the rules matched, and the deparser's rendering prints what perl prints.
sub reads_at_versions ( $rule, @cases ) {
    for my $case (@cases) {
        my ( $what, $src ) = $case->@*;
        subtest $what => sub {
            my $data = graph_of($src) or return fail 'a wire';
            my @bad  = grep { $_->{rule} =~ $rule } SoN::Verify::verify($data)->{violations}->@*;
            is [ map { "$_->{graph} $_->{op}#$_->{node} $_->{rule} $_->{detail}" } @bad ], [], 'every read names a version';
            my $d   = SoN::Deparse->new;
            my $out = $d->render($data);
            ok defined $out, 'the deparser renders it' or diag $d->gap;
            is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
        };
    }
}

# Wire v2 stage 7, the `through-ref` and `args` rows of the read rule (V6).
reads_at_versions( qr/\Aread-unversioned:(?:through-ref|args)\z/,
    [ 'a slice of an array through a reference (corpus 160)', q{sub f { my $r = shift; my @x = @$r[0, 1]; push @$r, 9; return "@x" } print f([4, 5, 6]), "\n";} ],
    [ 'a slice of @_ (ar16)', q{sub sw { my @x = @_[1, 0]; return "@x" } print sw(1, 2), "\n";} ],
    [ 'a returned array through a reference, read as a count (corpus 283)',
        q{sub items { my $r = shift; return $r->@* } my @got = items([1, 2, 3]); my $count = items([4, 5]); print scalar(@got), " ", $count, "\n";} ],
    [ 'a glob slot through an alias (Carp::_univ_mod_loaded)',
        q{sub u { return 0 unless exists($::{"UNIVERSAL::"}); for ($::{"UNIVERSAL::"}) { return 0 unless ref \$_ eq "GLOB" && *$_{HASH} && exists $$_{"$_[0]::"}; return 1 } } print u("isa"), "\n";} ],
    [ 'an element a ternary arm stores, read again after the store (corpus 083)',
        q{sub f { my @a = (0); return $_[0] ? ($a[0] = 7) : 8 } print f(1), f(0), "\n";} ],
);

done_testing;
