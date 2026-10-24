# ABOUTME: A block eval whose body makes a value that may die says so on its join, so a
# ABOUTME: consumer that cannot see an unused one (it is not in the graph) still knows.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub eval_regions ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f;
    my $data = JSON::PP->new->decode($j);
    return [ map { $_->{fields}{eval_may_die} ? 1 : 0 }
        grep { $_->{op} eq 'Region' && defined $_->{fields}{eval_entry} }
        $data->{methods}{'main::__PROGRAM__'}{nodes}->@* ];
}

# AN UNUSED DIVISION STILL DIES. `eval { my $q = 1 / $z; 1 }` is undef for a
# zero $z, but $q is never read, so the Divide is not in the graph at all.
is eval_regions(q{my $z = $ENV{NO_SUCH_VAR} // 0; my $r = eval { my $q = 1 / $z; 1 }; print defined $r ? 1 : 0;}),
    [1], 'an unused division by a variable';
is eval_regions(q{my $z = $ENV{NO_SUCH_VAR} // 0; my $r = eval { my $q = 7 % $z; 1 }; print defined $r ? 1 : 0;}),
    [1], 'and a modulus';
is eval_regions(q{my @a = (1, 2); my $r = eval { my $p = \$a[-5]; 1 }; print defined $r ? 1 : 0;}),
    [1], 'an unused reference to an array element';
is eval_regions(q{my %h = (a => 1); my $r = eval { my $p = \$h{b}; 1 }; print defined $r ? 1 : 0;}),
    [0], 'a reference to a hash element cannot die';
# A literal nonzero divisor cannot die; nor can an eval with no division.
is eval_regions(q{my $x = $ENV{NO_SUCH_VAR} // 6; my $r = eval { $x / 2 }; print $r;}),
    [0], 'a division by a literal';
is eval_regions(q{my $r = eval { 1 }; print $r;}), [0], 'no division';

done_testing;
