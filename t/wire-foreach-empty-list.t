# ABOUTME: `for my $x (()) {}` iterates zero times -- the body never runs.
# ABOUTME: Lowering is the absence of a loop, not a loop over nothing.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub run_and_wire ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $said = qx{$PERL $file 2>/dev/null};
    my $out  = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/)
          ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* : ();
    return ($said, \@n, $err);
}

# AN EMPTY ITERATION LIST IS ZERO ITERATIONS, so the body never executes and
# there is no loop to build. Measured:
#
#     for my $pkg(()){ print "BODY" } print "after";
#       perl prints: after
#
# This is perl's own t/comp/parser.t line 497 (bug #114942). It refused on the
# grounds that there were no bounds to iterate -- true, and that IS the answer
# rather than an obstacle to it: emitting nothing is exactly right.
#
# NOT AN EMPTY LOOP, which would be a different claim. A Loop node with no
# iterations still asserts that a loop exists and that its body is reachable;
# a consumer walking for reachable blocks would find one that never runs.
subtest 'an empty iteration list builds no loop and no body' => sub {
    my ($said, $n, $err) = run_and_wire(
        'for my $pkg(()){ print "BODY" } print "after";', 'fe-empty');
    is $said, 'after', 'perl runs the body zero times' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;

    is scalar(grep { $_->{op} eq 'Loop' } $n->@*), 0,
        'no Loop node -- there is no iteration';

    # The body's Print must not appear: it is unreachable, and emitting it
    # would put a statement in the graph that perl never runs.
    my @prints = grep { $_->{op} eq 'Print' } $n->@*;
    is scalar(@prints), 1,
        'exactly one Print -- the trailing one, not the dead body';
};

# THE SURROUNDING PROGRAM MUST SURVIVE. Refusing took the whole enclosing CV
# with it, so the fix has to leave everything after the loop intact.
subtest 'code after the empty loop is unaffected' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my $x = 1; for my $i (()) { $x = 99 } print $x;', 'fe-after');
    is $said, '1', 'perl leaves $x alone' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    ok scalar(grep { $_->{op} eq 'Print' } $n->@*),
        'the trailing print is still in the graph';
};

# A NON-EMPTY LIST STILL BUILDS A LOOP. A fix that dropped every list-literal
# foreach would trade a refusal for a silent drop -- the worse outcome.
subtest 'a non-empty list still loops' => sub {
    my ($said, $n, $err) = run_and_wire(
        'my $t=0; for my $i (1,2,3) { $t += $i } print $t;', 'fe-full');
    is $said, '6', 'perl sums three values' or return;
    unlike $err, qr/GAP|INTERNAL/, 'it lowers' or return;
    ok scalar(grep { $_->{op} eq 'Loop' } $n->@*),
        'a Loop is built for a non-empty list';
};

done_testing;
