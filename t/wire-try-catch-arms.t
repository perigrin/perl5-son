# ABOUTME: A try/catch keeps BOTH arms, or refuses -- it must never drop one silently.
# ABOUTME: The catch body was never walked: `catch` is a BRANCH op with no handler.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub wire ($body, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nuse feature 'try';\nno warnings 'experimental::try';\n$body\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    my $w = (length $out && $out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    my @n = $w ? (map { { $_->%*, ($_->{fields} // {})->%* } }
                  ($w->{methods}{'main::__PROGRAM__'}{nodes} // [])->@*) : ();
    return (\@n, $err);
}

sub has_const ($nodes, $want) {
    return scalar grep { $_->{op} eq 'Constant'
                         && defined $_->{value}
                         && index("$_->{value}", $want) >= 0 } $nodes->@*;
}

# THE CATCH ARM WAS DROPPED SILENTLY, with no warning and no GAP. Reported by
# chalk against producer 07fcdca and reproduced here:
#
#     try { die "boom\n"; $x = 1 } catch ($e) { print "caught\n"; $x = 2 }
#
#     perl:  caught / 2
#     graph: no Unwind, no "boom", no "caught" -- and NOTHING on stderr
#
# The try body IS walked; the catch body is not. entertrycatch's handler calls
# _walk_branch on `$op->other`, which IS the `catch` op -- and `catch` is
# registered BRANCH with no handler, so the generic branch-skip steps straight
# over it and the arm behind it is never entered.
#
# A DROPPED ARM IS WORSE THAN A REFUSAL. This producer's contract ranks a
# silent drop below a GAP precisely because nothing downstream can see it:
# there is no graph in which a consumer could take the catch arm, and no
# diagnostic saying so.
subtest 'the catch arm is not silently dropped' => sub {
    my ($n, $err) = wire(
        'my $x = 0; try { print "in\n"; $x = 1 } catch ($e) { print "caught\n"; $x = 2 } print $x;',
        'both_arms');
    if ($err =~ /GAP/) {
        pass('refused loudly, which is acceptable');
        return;
    }
    ok has_const($n, 'in'), 'the try arm is present';
    ok has_const($n, 'caught'),
        'the catch arm is present -- it was dropped with no diagnostic';
};

# THE die CASE, which is chalk's original report. `die` inside a try is the
# whole point of the construct: without it the catch arm is unreachable and
# the try/catch means nothing.
subtest 'a die inside try reaches the graph' => sub {
    my ($n, $err) = wire(
        'my $x = 0; try { die "boom\n"; $x = 1 } catch ($e) { $x = 2 } print $x;',
        'try_die');
    if ($err =~ /GAP/) {
        pass('refused loudly, which is acceptable');
        return;
    }
    ok has_const($n, 'boom') || scalar(grep { $_->{op} eq 'Unwind' } $n->@*),
        'the die is represented -- as a value or an Unwind';
};

# NOTHING MAY BE DROPPED WITHOUT A DIAGNOSTIC. The weakest possible statement
# of the contract, and the one that holds whichever way the construct is
# eventually lowered: if an arm is missing, stderr must say so.
subtest 'a missing arm is always accompanied by a diagnostic' => sub {
    my ($n, $err) = wire(
        'my $x = 0; try { $x = 1 } catch ($e) { $x = 2 } print $x;', 'quiet_drop');
    my $arms_present = scalar(grep { $_->{op} =~ /^(Region|Phi)$/ } $n->@*);
    ok $arms_present || $err =~ /GAP|INTERNAL/,
        'either the construct is in the graph or the producer said why';
};

done_testing;
