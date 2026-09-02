# ABOUTME: Every user CV reaches the wire or is accounted for by a named refusal.
# ABOUTME: "The file emitted JSON" is not "the file translated" -- this checks the difference.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

# THE ACCOUNTING IDENTITY:
#
#     CVs in the source  ==  methods on the wire  +  CVs refused by a GAP
#
# A CV missing from BOTH sides is a SILENT DROP -- the failure mode this
# producer treats as worse than a refusal, and the one no other test can see.
#
# WHY THIS EXISTS. Every file-level metric used on this producer has overstated
# it, because a file emits JSON as long as ONE sub translates. Measured on
# perl's t/base/lex.t: 3 methods, 53 nodes, and the entire 709-line
# __PROGRAM__ refused -- reported as a clean translation for most of a session.
#
# AND THE DIAGNOSTIC IS NOT GREPPABLE. A survey classifying stderr by message
# text reported ZERO internal errors across perl's t/ while 20 files raised
# one, because it matched one of five phrasings. The structural signals are:
# a method's PRESENCE on the wire, and the `GAP:` prefix that B::SoN itself
# uses to separate a refusal from a bug.
sub account ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> } // '';

    my %wire;
    if (length $out && $out =~ /^\{/) {
        my $w = eval { JSON::PP->new->decode($out) };
        %wire = map { $_ => 1 } keys +($w->{methods} // {})->%* if $w;
    }
    # A refusal names its CV: "B::SoN: skipped NAME: GAP: ..."
    my %refused = map { $_ => 1 } $err =~ /^B::SoN: skipped (\S+?):\s+GAP:/mg;
    # An INTERNAL error is NOT an accounting entry -- it is a bug, and the CV
    # vanishes. Collected separately so it can never be mistaken for a refusal.
    my @internal = $err =~ /^(?:Dying on warning: )?B::SoN: INTERNAL ERROR ([^\n]*)/mg;

    return { wire => \%wire, refused => \%refused, internal => \@internal };
}

subtest 'a translated sub is on the wire' => sub {
    my $a = account('sub f { 1 } sub g { 2 } print f(), g();', 'plain');
    ok $a->{wire}{'main::f'}, 'f reached the wire';
    ok $a->{wire}{'main::g'}, 'g reached the wire';
    is scalar($a->{internal}->@*), 0, 'no internal errors';
};

# THE CASE THE IDENTITY EXISTS FOR. One sub refuses; the others must still
# arrive, and the refused one must be NAMED rather than silently absent.
subtest 'a refused sub is named, and its neighbours still translate' => sub {
    my $a = account(
        'sub a { 1 } sub b { my %h=(k=>1); exists $h{k} } sub c { 3 } print a(), c();',
        'mixed');
    ok $a->{wire}{'main::a'}, 'a translated';
    ok $a->{wire}{'main::c'}, 'c translated';
    ok !$a->{wire}{'main::b'}, 'b did not reach the wire';
    ok $a->{refused}{'main::b'}, 'and b is ACCOUNTED FOR by a named refusal';
    is scalar($a->{internal}->@*), 0, 'a refusal is not an internal error';
};

# EVERY CV IS ACCOUNTED FOR. The identity itself, over a program mixing
# translated and refused subs: nothing may be missing from both sides.
subtest 'no CV is missing from both the wire and the refusal list' => sub {
    my $src = join ' ',
        'sub t1 { 1 }',
        'sub t2 { my %h=(k=>1); exists $h{k} }',
        'sub t3 { my @a=(1,2); $a[0] }',
        'sub t4 { my %h; delete $h{x} }',
        'print t1(), t3();';
    my $a = account($src, 'identity');
    for my $cv (map { "main::$_" } qw(t1 t2 t3 t4)) {
        ok $a->{wire}{$cv} || $a->{refused}{$cv},
            "$cv is on the wire or named in a refusal";
    }
};

# AN INTERNAL ERROR IS NOT AN ACCOUNTING ENTRY. It is a bug: the CV vanishes
# and no GAP names it. Asserted on the whole check so a future crash cannot be
# absorbed as though it were a refusal -- which is exactly how 20 crashing
# files were reported as clean.
subtest 'internal errors are reported as bugs, not absorbed as refusals' => sub {
    my $a = account('sub f { 1 } print f();', 'noint');
    is scalar($a->{internal}->@*), 0, 'a clean program raises none'
        or diag explain $a->{internal};
    is scalar(keys $a->{refused}->%*), 0, 'and refuses nothing';
};

done_testing;
