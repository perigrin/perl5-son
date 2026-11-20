# ABOUTME: B::SoN::EffectTable is the one statement of what a builtin does to memory and
# ABOUTME: the world; the walk pins by it in every context, and the verifier reads it.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use B::SoN::EffectTable;
use SoN::Verify;

# THE DEFECT (audit 2026-11-19, finding 4, departure 9). An effectful builtin
# was on the control chain in void context, and in any other only if one of
# seven hand-kept sets in SoN::FromOptree named it. `my $ok = open(...)`,
# `return bless {}, $class`, `mkdir($d) or die` were values: they ran at
# first use, or never. The census found open, chdir, mkdir, exec, read,
# sysopen, chmod, chown and readdir riding value edges in chalk's own lib.

subtest 'the table: facts and what follows from them' => sub {
    my $t = 'B::SoN::EffectTable';
    ok $t->can('on_chain')->($_), "$_ is pinned in every context"
        for qw(open close bless mkdir chdir exec system prtf readdir require tie warn select caller tell pos readline);
    ok !$t->can('on_chain')->( 'pos', lvalue => 1 ), 'pos as a store target is not a read';
    # (bless is one since ref/blessed/reftype read the class at a version)
    ok $t->can('is_version')->($_),  "$_ is a memory version" for qw(require dofile tie untie open close readline eof warn bless);
    ok !$t->can('is_version')->($_), "$_ is not"              for qw(mkdir caller tell pos select);
    ok $t->can('reads_at_version')->($_),  "$_ reads at a memory version" for qw(ref blessed reftype reftype_of_ref);
    ok !$t->can('reads_at_version')->($_), "$_ does not"                  for qw(time rand caller tell bless keys);
    ok !$t->can('on_chain')->($_),   "$_ is not pinned by the table" for qw(push time ref length uc join);
    ok $t->can('writes')->($_),      "$_ writes"              for qw(push chomp print bless open prtf);
    is $t->can('reads_state')->('ref'),  'object-class', 'ref reads an object\'s class';
    is $t->can('reads_state')->('time'), 'external',     'time reads the clock';
};

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return length $json ? JSON::PP->new->utf8->decode($json) : undef;
}

my %value_context = (
    open   => 'my $ok = open(my $fh, "<", $0); print "x\n"; close($fh) if $ok;',
    close  => 'open(my $fh, "<", $0); my $ok = close($fh); print "$ok\n";',
    bless  => 'sub mk { return bless {}, "K" } my $o = mk(); print ref($o), "\n";',
    mkdir  => 'my $d = "/nonexistent/x"; my $ok = mkdir($d, 0755); print $ok ? "y" : "n", "\n";',
    chdir  => 'my $ok = chdir("/"); print "$ok\n";',
    unlink => 'my $n = unlink("/nonexistent/x"); print "$n\n";',
    prtf   => 'my $ok = printf("%d\n", 3); print "$ok\n";',
    system => 'my $rc = system("true"); print "$rc\n";',
);
for my $name ( sort keys %value_context ) {
    subtest "$name used for its value is on the chain" => sub {
        my $w = wire( $value_context{$name} ) or return fail 'no wire';
        my @calls = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq $name }
            map { $_->{nodes}->@* } values $w->{methods}->%*;
        ok scalar(@calls), "a $name call is in the graph" or return;
        is [ grep { !defined $_->{control_in} } @calls ], [], 'it has a control_in';
        is [ map { "$_->{rule} $_->{detail}" }
             grep { $_->{rule} =~ /\A(?:effect-rides-value|write-floating)\z/ } SoN::Verify::verify($w)->{violations}->@* ],
            [], 'the verifier sees no effect off the chain';
    };
}

# THE TABLE IS THE ONLY STATEMENT. The seven sets are gone from the walk, and
# the verifier's own list with them.
subtest 'no second list' => sub {
    for my $file ( 'lib/SoN/FromOptree.pm', 'lib/SoN/Verify.pm' ) {
        open my $fh, '<', $file or die "$file: $!";
        my $src = do { local $/; <$fh> };
        my @sets = $src =~ /^\s*my (%(?:GLOBAL_STATE|HANDLE_MEMORY|HANDLE_READ|STACK_READ|HANDLE_SELECT|HANDLER|VARIABLE_STATE_READ)_BUILTIN|%WRITES|%READS_STATE)\b/mg;
        is \@sets, [], "$file keeps no effect set of its own";
    }
};

done_testing;
