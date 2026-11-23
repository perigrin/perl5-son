# ABOUTME: rand and srand take an optional argument and mkdir one or two: each pops the
# ABOUTME: operands its op says it has, not the op table's one fixed count.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub wire ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $err  = do { local ( @ARGV, $/ ) = "$dir/err"; <> } =~ s/^\S+ syntax OK\n//mr;
    return ( ( $json =~ /\S/ ? JSON::PP->new->decode($json) : undef ), $err );
}

# THE SIXTH OPTIONAL-ARITY OPERATOR (after bless, select, unpack, exit and
# binmode; audit 2026-11-22, risk 9: probes aue1, rn1): OpMap declares rand
# and srand a fixed 1-pop and mkdir a 2-pop, so `rand()` and `mkdir $d`
# popped operands that were never pushed -- "Stack underflow", an INTERNAL
# ERROR -- or, worse, someone else's: in `5 + rand()` rand took the 5.
for my $src ( 'my $a = rand(); print "$a\n";', 'srand; print "x\n";', 'my $d = "x"; mkdir $d; print "y\n";' ) {
    my ( undef, $err ) = wire($src);
    unlike $err, qr/INTERNAL ERROR/, "no internal error: $src";
}

my ( $w ) = wire('my $x = 5 + rand(); print "$x\n";');
my @n = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
my %by = map { $_->{id} => $_ } @n;
my ($rand) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'rand' } @n;
ok $rand, 'rand is a Call';
is scalar( ( $rand->{inputs} // [] )->@* ), 0, 'rand() takes no operand';
my ($add) = grep { $_->{op} eq 'Add' } @n;
is [ map { $by{$_}{op} } $add->{inputs}->@* ], [ 'Coerce', 'Call' ], '5 + rand(): the add has both (the 5 made a Num)';

done_testing;
