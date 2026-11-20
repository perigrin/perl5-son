# ABOUTME: An `if` arm whose only statement is a pinned builtin (a bless) keeps its If:
# ABOUTME: the bless follows the arm's Proj, and a ref() after the join reads a memory Phi.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE DEFECT (probe cr8, docs/memory/a-bless-only-arm-loses-its-if.md).
#
#     my $o = {}; if (@ARGV) { bless $o, "X" } print ref($o), "\n";
#
# had NO If: the bless and the print both followed the HashLiteral (one
# control, two successors), and ref() read MemStart, the memory before the
# bless. "Does this arm need control flow" was answered from a list of op
# names; bless became a pinned memory version (B::SoN::EffectTable) and the
# list was not told. The arm scan asks the table now.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return JSON::PP->new->utf8->decode($json);
}
sub nodes ($w) { $w->{methods}{'main::__PROGRAM__'}{nodes}->@* }
sub forks ($w) { [ grep { $_->{rule} eq 'control-fork' } SoN::Verify::verify($w)->{violations}->@* ] }

subtest 'one arm that only blesses' => sub {
    my $w  = wire(q{my $o = {}; if (@ARGV) { bless $o, "X" } print ref($o), "\n";});
    my @n  = nodes($w);
    my %by = map { $_->{id} => $_ } @n;
    my ($if) = grep { $_->{op} eq 'If' } @n;
    ok $if, 'there is an If' or return;
    my ($bless) = grep { $_->{op} eq 'Call' && $_->{fields}{name} eq 'bless' } @n;
    my $arm = $by{ $bless->{control_in} // '' };
    is $arm && $arm->{op}, 'Proj', q{the bless follows a Proj};
    is $arm && $arm->{inputs}[0], $if->{id}, '... of that If';
    my ($ref) = grep { $_->{op} eq 'RefType' } @n;
    my $mem = $by{ $ref->{inputs}[1] // '' };
    is $mem && $mem->{op}, 'Phi', 'the ref() after the join reads a Phi';
    ok $mem && $mem->{fields}{memory}, '... a memory Phi';
    ok scalar( grep { $_ == $bless->{id} } $mem->{inputs}->@* ), '... one of whose inputs is the bless';
    is forks($w), [], 'no control node has two successors';
};

subtest 'both arms only bless (cr8)' => sub {
    my $w = wire(
        q{my $o = {}; my $c = ref($o); if (@ARGV) { bless $o, "X" } else { bless $o, "Y" } print "$c ", ref($o), "\n";});
    my @n  = nodes($w);
    my %by = map { $_->{id} => $_ } @n;
    my ($if) = grep { $_->{op} eq 'If' } @n;
    ok $if, 'there is an If' or return;
    my @bless = grep { $_->{op} eq 'Call' && $_->{fields}{name} eq 'bless' } @n;
    is scalar @bless, 2, 'two blesses';
    is [ sort map { $by{ $_->{control_in} }{fields}{index} } @bless ], [ 0, 1 ], 'one on each Proj';
    my ($after) = grep { $_->{op} eq 'RefType' && $by{ $_->{inputs}[1] }{op} eq 'Phi' } @n;
    ok $after, 'the ref() after the join reads the memory Phi';
    is forks($w), [], 'no control node has two successors';
};

subtest 'a bless beside a value the arms give' => sub {
    my $w = wire(
        q{my $h = {}; my $r; if (@ARGV) { $r = "n" } else { $r = ref($h); bless $h, "K" } print "$r ", ref($h), "\n";});
    my @n = nodes($w);
    ok scalar( grep { $_->{op} eq 'If' } @n ), 'there is an If';
    is forks($w), [], 'no control node has two successors';
};

subtest 'a statement-modifier bless, and one behind &&' => sub {
    for my $src ( q{my $o = {}; bless $o, "X" if @ARGV; print ref($o), "\n";},
        q{my $o = {}; @ARGV && bless $o, "X"; print ref($o), "\n";} )
    {
        my $w = wire($src);
        ok scalar( grep { $_->{op} eq 'If' } nodes($w) ), "an If: $src";
        is forks($w), [], '... and no fork';
    }
};

# THE SAME HOLE, FOUND BY THE VERIFIER'S control-fork RULE once it existed:
# five more statements the walk pins and the arm scan did not know. Each ran
# whether or not its condition held (perl's Carp::caller_info has the first:
# `if ($MaxArgNums and @args > $MaxArgNums) { $#args = $MaxArgNums - 1; ... }`).
for my $c (
    [ q{a store to an array's last index},   q{my @a = (1, 2, 3); if (@ARGV) { $#a = 0 } print scalar(@a), "\n";} ],
    [ q{... behind a statement modifier},    q{my @a = (1, 2, 3); $#a = 0 if @ARGV; print scalar(@a), "\n";} ],
    [ q{... behind and},                     q{my @a = (1, 2, 3); @ARGV and $#a = 0; print scalar(@a), "\n";} ],
    [ q{... in a ternary arm},               q{my @a = (1, 2, 3); my $n = @ARGV ? ($#a = 0) : 5; print scalar(@a), " $n\n";} ],
    [ q{... beside a value the arm gives},   q{my @a = (1, 2, 3); my $o; if (@ARGV) { $#a = 0; $o = 1 } print scalar(@a), " ", $o // "u", "\n";} ],
    [ q{a package array assigned whole},     q{our @g = (1, 2); if (@ARGV) { @g = () } print scalar(@g), "\n";} ],
    [ q{a package hash assigned whole},      q{our %g = (a => 1); if (@ARGV) { %g = () } print scalar(keys %g), "\n";} ],
    [ q{a tr/// into its operand},           q{my $s = "ab"; if (@ARGV) { $s =~ tr/a/b/ } print "[$s]\n";} ],
    [ q{an array slice assigned},            q{my @a = (1, 2); if (@ARGV) { @a[0, 1] = (3, 4) } print "@a\n";} ],
    [ q{a list assignment with an array among its targets}, q{my ($x, @r); if (@ARGV) { ($x, @r) = (1, 2, 3) } print scalar(@r), "\n";} ],
    [ q{a hash slice assigned},              q{my %h; if (@ARGV) { @h{qw(a b)} = (1, 2) } print scalar(keys %h), "\n";} ],
) {
    my ( $what, $src ) = @$c;
    subtest $what => sub {
        my $w = wire($src);
        ok $w->{methods}{'main::__PROGRAM__'}, 'the program has a graph' or return diag `cat $dir/err`;
        ok scalar( grep { $_->{op} eq 'If' } nodes($w) ), 'there is an If';
        is forks($w), [], 'no control node has two successors';
    };
}

done_testing;

