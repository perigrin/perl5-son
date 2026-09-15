# ABOUTME: A call through a code ref carries the callee as an INPUT, not a name.
# ABOUTME: `dispatch_kind='direct'` with name 'unknown' names a sub nothing defines.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# A CALLEE THAT IS A VALUE CANNOT BE A NAME. The entersub handler resolves a
# callee to its stash name, or through a pad binding to an AnonSub, and falls
# back to the literal string 'unknown' when neither applies. Its own comment
# says what that costs: "the AnonSub was popped and dropped -- the exact
# silent wrong answer the old refusal was written to prevent".
#
# A CODE REF ARRIVING AS A PARAMETER hits that fallback, because there is no
# pad binding to look through -- measured on
# `sub take { my $f = shift; return $f->() }`:
#
#     3 Call  builtin shift    in=[ArgsSource, MemStart]
#     4 Call  direct  unknown  in=[]          <- NO INPUTS AT ALL
#
# The callee is gone. A consumer emitting that calls a sub named `unknown`
# which nothing defines.
#
# THE CALLEE IS AN INPUT, and `dispatch_kind` says so. Three kinds existed --
# builtin, direct, method -- all of which name their callee; a call through a
# VALUE is a fourth.
subtest 'a call through a parameter' => sub {
    my $src = 'sub take { my $f = shift; return $f->() } print take(sub { 9 }), "\n";';
    is run_perl($src), "9\n", 'perl calls the passed sub' or return;

    my $g = graph_of($src);
    ok $g && $g->{methods}{'main::take'}, 'it translates' or return;

    my @ns = ($g->{methods}{'main::take'}{nodes} // [])->@*;
    my %by = map { $_->{id} => $_ } @ns;

    my ($call) = grep {
        ($_->{op} // '') eq 'Call'
            && (($_->{fields} // {})->{dispatch_kind} // '') ne 'builtin'
    } @ns;
    ok $call, 'there is a non-builtin Call' or return;

    isnt +(($call->{fields} // {})->{name} // ''), 'unknown',
        'it does not name a phantom sub';

    is +(($call->{fields} // {})->{dispatch_kind} // ''), 'indirect',
        'its dispatch_kind says the callee is a value';

    # AND THAT VALUE IS THE SHIFTED CODE REF, not something else on the stack.
    my @in = ($call->{inputs} // [])->@*;
    ok scalar(@in), 'it has an input' or return;
    my $callee = $by{ $in[0] };
    is +(($callee->{fields} // {})->{name} // ''), 'shift',
        'and input 0 is the shift that produced the code ref';
};

# NO OTHER Call NAMES `unknown`, anywhere in the graph. A refusal that still
# emitted the bad node would be the worst of both.
subtest 'nothing names unknown' => sub {
    my $g = graph_of('sub take { my $f = shift; return $f->() } print take(sub { 9 }), "\n";');
    ok $g, 'it translates' or return;

    my @bad;
    for my $m (sort keys $g->{methods}->%*) {
        push @bad, "$m:$_->{id}"
            for grep { ($_->{op} // '') eq 'Call'
                    && (($_->{fields} // {})->{name} // '') eq 'unknown' }
                ($g->{methods}{$m}{nodes} // [])->@*;
    }
    is \@bad, [], 'no Call names `unknown`';
};

# THE RESOLVABLE FORMS MUST NOT REGRESS -- a named sub and an anon sub held in
# a pad are the common cases, and both resolve to a name today.
subtest 'resolvable callees still name their callee' => sub {
    my $g = graph_of('sub f { 7 } print f(), "\n";');
    ok $g, 'a named sub translates' or return;
    my ($c) = grep { ($_->{op} // '') eq 'Call'
                  && (($_->{fields} // {})->{dispatch_kind} // '') eq 'direct' }
              ($g->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    is +(($c->{fields} // {})->{name} // ''), 'main::f', 'and names it';

    my $g2 = graph_of('my $c = sub { 8 }; print $c->(), "\n";');
    ok $g2, 'an anon sub through a pad translates' or return;
    my ($c2) = grep { ($_->{op} // '') eq 'Call'
                   && (($_->{fields} // {})->{dispatch_kind} // '') eq 'direct' }
               ($g2->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*;
    like +(($c2->{fields} // {})->{name} // ''), qr/__ANON__/,
        'and names the anon body';
};

done_testing;
