# ABOUTME: a warn is placed on the control chain as print is, in any context,
# ABOUTME: and carries the file and line perl appends, as a die does.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub wire_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    return ( eval { JSON::PP->new->decode($j) }, $f );
}

sub warns_of ($w, $graph) {
    return grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'warn' }
        ( $w->{methods}{$graph}{nodes} // [] )->@*;
}

# 1. A WARN INSIDE AN EXPRESSION had no place on the chain: when it ran was
# not said (pvm argument-extent:3, `my @greedy = (warn "a", "b")`), and one
# whose value nothing read vanished with no refusal.
for my $case (
    [ 'a warn in a list',          q{my @g = (warn "a\n", "b"); print scalar(@g), "\n";} ],
    [ 'a warn in parens in a list', q{my @c = (warn("a\n"), "b"); print scalar(@c), "\n";} ],
    [ 'a warn whose value is unread', q{my $x = 1 + warn("q\n"); print "z\n";} ],
    [ 'a warn as a statement',     q{warn "s\n"; print "z\n";} ],
) {
    my ($name, $src) = @$case;
    my ($w) = wire_of($src);
    my @w = warns_of($w, 'main::__PROGRAM__');
    is scalar(@w), 1, "$name: one warn on the wire";
    ok defined $w[0]{control_in}, "$name: on the control chain";
    ok $w[0]{fields}{memory_input}, "$name: a memory version (its handler may store)";
}

# A sub's last statement runs in its caller's context, not void.
{
    my ($w) = wire_of(q{sub f { warn "x\n" } my $r = f(); print "$r\n";});
    my @w = warns_of($w, 'main::f');
    ok @w && defined $w[0]{control_in}, "a sub's last-statement warn: on the control chain";
}

# 2. ITS FILE AND LINE, as a die's: perl appends " at FILE line N.\n" to a
# message not ending in a newline.
{
    my ($w, $f) = wire_of(qq{my \$x = 1;\n\nmy \@g = (warn "no newline", "b");\nprint "ok\\n";\n});
    my ($c) = warns_of($w, 'main::__PROGRAM__');
    is $c->{fields}{file}, $f, 'a warn names the file perl compiled';
    is $c->{fields}{line}, 3, 'and the line of its statement';
    ok !exists $c->{fields}{package}, 'and no package (a die names none)';
    my ($u) = grep { $_->{op} eq 'Unwind' } ( ( wire_of(qq{\n\ndie "x";\n}) )[0]{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    is [ sort grep { /file|line/ } keys $u->{fields}->%* ], [ sort grep { /file|line/ } keys $c->{fields}->%* ],
        'the same fields as a die';
}

# The order holds in the round trip: each warn runs where perl runs it.
sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f; return $out;
}
for my $src (
    q{print "1\n"; my @g = (warn("2\n"), "b"); print "3 ", scalar(@g), "\n";},
    q{my $n = 0; local $SIG{__WARN__} = sub { $n++ }; my @g = (warn "a\n", "b"); my $x = 1 + warn("q\n"); print "$n\n";},
) {
    my ($data) = wire_of($src);
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    ok defined $out, "renders: $src" or do { diag $d->gap; next };
    my $want = run_perl($src) =~ s/ at \S+ line \d+\.//gr;
    my $got = run_perl($out) =~ s/ at \S+ line \d+\.//gr;
    is $got, $want, "round trip: $src" or diag $out;
}

done_testing;
