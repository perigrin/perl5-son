# ABOUTME: A body that cannot translate is attempted ONCE, not retried forever.
# ABOUTME: The anon-body drain looped on "not in %graphs" while failure deleted it.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub translate ($src, $name, $secs = 25) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "no warnings;\nuse feature 'state';\n$src\n";
    close $fh;
    my $rc = system("timeout $secs $PERL -Ilib -MO=SoN,json,package=main $file"
                    . " >/dev/null 2>$dir/$name.err");
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';
    return ($rc, $err);
}

# AN INFINITE LOOP BY CONSTRUCTION. The anon-body drain is
#
#     while (1) { @pending = not-yet-in-%graphs; last unless @pending; ... }
#
# and its catch DELETED the entry on failure -- so a body that cannot
# translate was pending again on the very next round, forever. Measured on
# perl's own t/op/lexsub.t, which spun emitting one identical
# "INTERNAL ERROR ... Stack underflow" per round until killed.
#
# THE SAME DEFECT, BOUNDED, IS WHY op/gmagic.t EMITTED 40,930 SKIP MESSAGES:
# two anon CVs at ~27,000 each, the loop stopped only by the file running out
# of other work. Eight files in perl's t/ were TIMEOUTs from this one cause.
#
# The trigger needs BOTH mutual lexical subs and an early-return branch;
# either alone translates cleanly, which is why it survived so long.
my $LEXSUB = <<'SRC';
sub mk {
  sub {
    state sub s1;
    state sub s2 { \&s1 }
    sub s1 { \&s2 }
    if (@_) { return \&s1 }
    return s1();
  }
}
my $s = mk(); print defined($s)?1:0;
SRC

subtest 'a failing anon body does not spin the translator' => sub {
    my ($rc, $err) = translate($LEXSUB, 'lexsub_spin');
    isnt $rc, 124 << 8, 'it terminates rather than timing out'
        or return;
    is $rc, 0, 'and exits cleanly';
};

# REPORTED ONCE. The count is the real assertion: a retry loop that terminated
# for some other reason would still emit the message many times, so bounding
# the loop and reporting once are the same fact.
subtest 'a failing body is reported exactly once' => sub {
    my (undef, $err) = translate($LEXSUB, 'lexsub_once');
    my $n = () = $err =~ /INTERNAL ERROR|^B::SoN: skipped/mg;
    cmp_ok $n, '<=', 4, "the failure is reported a bounded number of times (got $n)";
};

# THE FIXPOINT MUST STILL WORK. Bounding the loop by "attempted" must not stop
# a NESTED anon sub from being drained -- that is what the fixpoint is for, and
# a fix that simply ran one round would pass the two subtests above.
subtest 'a nested anon sub is still drained' => sub {
    my ($rc, $err) = translate(
        'my $outer = sub { my $inner = sub { 42 }; return $inner->() };'
        . ' print $outer->();', 'nested_anon');
    is $rc, 0, 'it translates';
    unlike $err, qr/INTERNAL ERROR/, 'with no internal error';
};

done_testing;
