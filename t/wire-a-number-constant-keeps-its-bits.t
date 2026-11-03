# ABOUTME: a Num constant on the wire reads back as the same double -- 15 digits
# ABOUTME: do not always say which double (0.1 + 0.2 folded is not 0.3).
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir(CLEANUP => 1);

sub constants ($src) {
    my $file = "$dir/c.pl";
    open my $fh, '>', $file or die; print {$fh} "$src\n"; close $fh;
    my $json = qx{$^X -Ilib -MO=-q,SoN,json,not_package=SoN $file 2>$dir/c.err};
    my $w = JSON::PP->new->decode($json);
    return grep { $_->{op} eq 'Constant' && ( $_->{fields}{const_type} // '' ) eq 'number' }
        $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
}

# perl folds 0.1 + 0.2 to 0.30000000000000004, which prints as 0.3 -- and was
# written so, which a reader parses back to 0.3: `$x == 0.3` became true.
my ($sum) = constants('my $x = 0.1 + 0.2; print $x == 0.3 ? "eq" : "ne";');
ok defined $sum, 'the folded sum is a number constant' or BAIL_OUT('no constant');
cmp_ok 0 + $sum->{fields}{value}, '==', 0.1 + 0.2, 'it reads back as the same double';

# A number 15 digits do say exactly is written as perl prints it.
my ($half) = constants('my $x = 0.5; print $x;');
is $half->{fields}{value}, '0.5', 'a short number is written short';

# A NUM AMONG STRS is read as what it is: the element of `(0.1 + 0.2, "x")`
# was stamped Str (the join), so `== 0.3` compared its printed digits.
{
    my $file = "$dir/m.pl";
    open my $fh, '>', $file or die; print {$fh} 'my @b = (0.1 + 0.2, "x"); print $b[0] == 0.3 ? "eq" : "ne";', "\n"; close $fh;
    my $w = JSON::PP->new->decode(scalar qx{$^X -Ilib -MO=-q,SoN,json,not_package=SoN $file 2>$dir/m.err});
    my ($sub) = grep { $_->{op} eq 'Subscript' } $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    isnt $sub->{stamp}, 'Str', 'an element of numbers and strings is not read as a Str';
}

done_testing;
