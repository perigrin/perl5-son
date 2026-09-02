# ABOUTME: exists and delete REFUSE rather than lowering to a wrong answer.
# ABOUTME: exists was mapped to Defined over the KEY, which is always true.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub translate ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    open my $eh, '<', "$dir/$name.err" or die;
    my $err = do { local $/; <$eh> };
    return ($out, $err // '');
}

# A SILENT WRONG ANSWER, and it was reachable from ordinary code. OpMap mapped
#
#     exists  => [1, 'Defined', 1, 0]
#
# so `exists $h{zz}` became Defined(Constant("zz")) -- asking whether the
# STRING "zz" is defined, which it always is. perl prints "no"; the graph meant
# "yes". Membership and definedness are DIFFERENT QUESTIONS, measured:
#
#     my %h = (a => undef);
#     exists $h{a}    true      the key is there
#     defined $h{a}   false     its value is not
#
# and the operand was wrong on top of that: the Defined took the KEY, never the
# slot, so no version of this mapping could have been right.
subtest 'exists refuses rather than testing the key string' => sub {
    my ($out, $err) = translate('my %h=(a=>1); print exists $h{zz} ? "y" : "n";', 'ex');
    like $err, qr/GAP/, 'exists is refused, loudly';
    unlike $out, qr/"op"\s*:\s*"Defined"/,
        'no Defined node is emitted over the key';
};

# DELETE MUTATES AND YIELDS. It removes the key AND returns the value:
#
#     my %h=(a=>1,b=>2); my $d = delete $h{a};   $d is 1, and a is gone
#
# It reached the wire as Call(delete, Constant("a")) :Unknown -- the KEY as its
# only operand, no hash, and no memory edge, so a later read could not observe
# the removal. Refuse until the mutation is memory-modelled, the same contract
# push/unshift/splice are held to.
subtest 'delete refuses rather than dropping the mutation' => sub {
    my ($out, $err) = translate('my %h=(a=>1,b=>2); my $d = delete $h{a}; print $d;', 'del');
    like $err, qr/GAP/, 'delete is refused, loudly';
};

# THE REFUSAL MUST NAME THE CONSTRUCT. A GAP whose message does not say what
# was refused sends the reader hunting, which is the failure mode the
# refuse-before-popping work in this file already fixed once.
subtest 'the refusals name themselves' => sub {
    my (undef, $eerr) = translate('my %h=(a=>1); print exists $h{a} ? 1 : 0;', 'exname');
    like $eerr, qr/exists/, 'the exists GAP says "exists"';
    my (undef, $derr) = translate('my %h=(a=>1); delete $h{a};', 'delname');
    like $derr, qr/delete/, 'the delete GAP says "delete"';
};

# NEIGHBOURING HASH OPERATIONS STILL WORK. The refusal must be for these two
# ops, not for hash access generally.
subtest 'ordinary hash reads and writes are untouched' => sub {
    my ($out, $err) = translate('my %h=(a=>1); $h{b}=2; print $h{a};', 'hashok');
    unlike $err, qr/GAP/, 'a plain hash read/write does not refuse';
    like $out, qr/"op"\s*:\s*"Subscript"/, 'and still builds its Subscript';
};

done_testing;
