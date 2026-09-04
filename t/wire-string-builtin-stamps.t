# ABOUTME: uc/lc/hex/ord and friends have result types perl defines -- stamp them.
# ABOUTME: Found by cross-checking B::SoN's stamps against pvm's precision corpus.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

# Returns the stamp of the value reaching the final Print, stepping past a
# Coerce (a representation change, not the value).
sub printed_stamp ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
    my $w = ($out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    return 'NO GRAPH' unless $w;
    my @n = map { $_->{nodes}->@* } values $w->{methods}->%*;
    my %by = map { $_->{id} => $_ } @n;
    my ($pr) = grep { $_->{op} eq 'Print' } @n;
    return 'NO PRINT' unless $pr;
    my $node = $by{ ($pr->{inputs} // [])->[0] // '' };
    $node = $by{ ($node->{inputs} // [])->[0] // '' }
        while $node && $node->{op} eq 'Coerce';
    return ($node // {})->{stamp} // 'NONE';
}

# FOUND BY CROSS-CHECK, not by a failing test. Running B::SoN's stamps against
# pvm's 57-observation precision corpus turned up `uc($s)` reaching the wire
# Unknown where perl observes Str -- a FAILURE Unknown, since perl defines what
# these return. Surveying the family found eight.
#
# MEASURED, each against a real perl run through the same observer:
#
#     uc lc ucfirst lcfirst   Str
#     chr                     Str
#     hex oct ord             Int
#     sqrt                    Num  -- and this one is the reason to measure:
#                                     sqrt(16) observes Int and sqrt(2) observes
#                                     Num, so Int would be WRONG for most
#                                     inputs while Num is right for all.
#
# A RUNTIME ARGUMENT throughout, or perl constant-folds the call and there is
# no node to stamp.

subtest 'case-folding builtins are Str' => sub {
    for my $b (qw(uc lc ucfirst lcfirst)) {
        my $st = printed_stamp(
            "my \$s = shift(\@ARGV) // 'Hello'; my \$x = $b(\$s); print \$x;",
            "sb-$b");
        is $st, 'Str', "$b is stamped Str";
    }
};

subtest 'numeric-from-string builtins are Int' => sub {
    for my $b (['hex', '"ff"'], ['oct', '"0755"'], ['ord', '$s']) {
        my ($name, $arg) = $b->@*;
        my $st = printed_stamp(
            "my \$s = shift(\@ARGV) // 'A'; my \$x = $name($arg); print \$x;",
            "sb-$name");
        is $st, 'Int', "$name is stamped Int";
    }
};

subtest 'chr is Str and sqrt is Num' => sub {
    my $chr = printed_stamp(
        'my $n = shift(@ARGV) // 65; my $x = chr($n); print $x;', 'sb-chr');
    is $chr, 'Str', 'chr is stamped Str';

    # NOT Int. sqrt(16) observes Int but sqrt(2) observes Num, so Int would be
    # a WRONG answer for most inputs -- Num admits both.
    my $sq = printed_stamp(
        'my $n = shift(@ARGV) // 2; my $x = sqrt($n); print $x;', 'sb-sqrt');
    is $sq, 'Num', 'sqrt is stamped Num, which admits both its observed types';
};

# ALREADY CORRECT, and pinned so a change to the table cannot quietly widen
# them: these carry types inferred from their inputs, not from a builtin entry.
subtest 'the already-typed neighbours are undisturbed' => sub {
    is printed_stamp('my $s = shift(@ARGV) // "hi"; print length($s);',
                     'sb-length'), 'Int', 'length stays Int';
    is printed_stamp('my $s = shift(@ARGV) // "hi"; print index($s,"i");',
                     'sb-index'), 'Int', 'index stays Int';
    is printed_stamp('my $s = shift(@ARGV) // "hi"; print quotemeta($s);',
                     'sb-qm'), 'Str', 'quotemeta stays Str';
};

done_testing;
