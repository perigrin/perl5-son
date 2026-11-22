# ABOUTME: Every builtin the walk makes a Call for has a row in B::SoN::EffectTable (pure, a
# ABOUTME: fact, or its own handler's); a may-die builtin stands on the chain; none is pure by default.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use B::SoN::EffectTable;

# THE DEFECT (audit 2026-11-22, section 1 and risk 6): the table was an
# allow-list, so a builtin with no row was pure. `log(0)` and `sqrt(-1)` die
# in perl; floating and unused, they were dropped and the program ran on.

subtest 'every Call in the op map has a row' => sub {
    open my $fh, '<', 'lib/SoN/FromOptree/OpMap.pm' or die $!;
    my @calls = map { /^\s+(\w+)\s+=>\s+\[[^\]]*'Call'/ ? $1 : () } <$fh>;
    ok scalar(@calls) > 50, 'the op map names its Call builtins';
    is [ grep { !B::SoN::EffectTable::known($_) } @calls ], [], 'none is left to a default';
    ok !B::SoN::EffectTable::known('no_such_builtin'), 'a name with no row is not known';
    ok B::SoN::EffectTable::writes('no_such_builtin'), 'and is taken to write';
};

subtest 'a builtin that may die is on the chain' => sub {
    ok B::SoN::EffectTable::faults($_), "$_ may die" for qw(log sqrt);
    ok B::SoN::EffectTable::on_chain($_), "$_ is pinned" for qw(log sqrt);
    ok !B::SoN::EffectTable::on_chain($_), "$_ is not" for qw(abs int sin exp uc join);
};

my $dir = tempdir( CLEANUP => 1 );
sub wire ($src) {
    open my $o, '>', "$dir/p.pl" or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $dir/p.pl 2>$dir/err);
    return length $json ? JSON::PP->new->utf8->decode($json) : undef;
}
for my $src ( 'my $z = @ARGV; my $x = log($z); print "after\n";', 'my $z = -@ARGV; my $x = sqrt($z); print "after\n";' ) {
    my $w = wire($src) or do { fail "$src: a wire"; next };
    my @c = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) =~ /\A(?:log|sqrt)\z/ } map { $_->{nodes}->@* } values $w->{methods}->%*;
    is scalar(@c), 1, "$src: the unused call is in the graph";
    ok defined $c[0]{control_in}, "$src: on the control chain";
}

done_testing;
