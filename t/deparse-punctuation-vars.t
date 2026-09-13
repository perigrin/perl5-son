# ABOUTME: A punctuation variable is stored as its control character and must be spelled with a caret.
# ABOUTME: Emitting the raw byte gives perl "Unrecognized character \x0F" -- found by base/num.t.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# PERL STORES `$^O` AS ${"\x0f"} -- the caret form is source syntax, and the
# symbol-table name is the control character itself. The producer passes that
# through faithfully, so the emitter receives "\x0f" and must spell it back as
# `$^O`. Writing the raw byte gives:
#
#     Unrecognized character \x0F; marked by <-- HERE after (($main:: <-- HERE
#
# Found by base/num.t, which reads $^O to skip OS-specific cases. That file is
# 56 tests of number stringification and now round-trips byte-identically.
subtest 'a caret variable renders as its caret form' => sub {
    my $data = graph_of('print "os\n" if $^O; print "done\n";');
    ok $data, 'it translates' or return;

    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    ok defined $out, 'it renders' or do { diag $d->gap; return };

    unlike $out, qr/\x0f/, 'no raw control character reaches the source';
    like $out, qr/\$\^O/, 'and the caret form is what is emitted';
};

# `$main::_` IS THE SAME VARIABLE AS `$_` -- verified:
#
#     perl -e '$main::_ = "x"; print "[$_]"'    prints [x]
#
# so qualifying it is verbose rather than wrong, and the emitter is allowed to
# be ugly. What WOULD be wrong is qualifying a name that cannot take a
# qualifier: `$main::1` is a syntax error. This asserts the program still runs,
# which is the criterion, rather than a spelling preference.
subtest 'a qualified punctuation variable still names the same slot' => sub {
    my $data = graph_of('$_ = "x"; print "$_\n";');
    ok $data, 'it translates' or return;

    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    ok defined $out, 'it renders' or do { diag $d->gap; return };

    my $f = "$dir/p." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $got = qx($^X $f 2>&1);
    unlink $f;
    is $got, "x\n", 'and the emitted program reads the same variable'
        or diag "--- emitted ---\n$out--- got ---\n$got";
};

done_testing;
