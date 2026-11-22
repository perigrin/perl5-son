# ABOUTME: Every read of a class field names its memory version: a :reader accessor's, a field
# ABOUTME: array or hash read whole, a slice of one. A FieldAccess with no mem_in is only a place.

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

my $H = q{use v5.42; use experimental 'class'; };
# Wire v2 stage 7, the `field` row of the read rule (V6).
for my $case (
    [ 'a :reader accessor (corpus 118, 241)', $H . q{class K { field $b :param :reader = 3; } my $k = K->new; print $k->b, K->new(b => 4)->b, "\n";} ],
    [ 'a slice of a field array (corpus 161)', $H . q{class K { field @f = (4, 5, 6); method s { my @x = @f[0, 2]; "@x" } } print K->new->s, "\n";} ],
    [ 'a field array joined, a field hash counted (corpus 247)',
        $H . q{class H { field %r; field @o; method reg ($g) { %r = $g->%*; @o = sort keys %r; return $self } method clear { @o = (); return $self }
               method summary { return scalar(keys %r) . ":" . join(",", @o) } }
               my $h = H->new->reg({ b => 2, a => 1 }); print $h->summary, " ", $h->clear->summary, "\n";} ],
    [ 'a field the subject of a match (chalk XS::AST::VarDecl::emit)',
        $H . q{class K { field $t :param = "a*"; method m { return $t =~ /\*$/ ? "p" : "n" } } print K->new->m, K->new(t => "b")->m, "\n";} ],
    [ 'a field matched in ADJUST', $H . q{class K { field $n :param; ADJUST { die "bad\n" unless $n =~ /^\w+$/ } method n { $n } } print K->new(n => "ok")->n, "\n";} ],
    [ 'a field array read whole either side of a push',
        $H . q{class K { field @f = (1); method m { my @a = @f; push @f, 2; my @b = @f; return "@a|@b" } } print K->new->m, "\n";} ],
) {
    my ( $what, $src ) = $case->@*;
    subtest $what => sub {
        my $data = graph_of($src) or return fail 'a wire';
        my @bad  = grep { $_->{rule} eq 'read-unversioned:field' } SoN::Verify::verify($data)->{violations}->@*;
        is [ map { "$_->{graph} $_->{op}#$_->{node} $_->{detail}" } @bad ], [], 'every read of a field names a version';
        my $d   = SoN::Deparse->new;
        my $out = $d->render($data);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

done_testing;
