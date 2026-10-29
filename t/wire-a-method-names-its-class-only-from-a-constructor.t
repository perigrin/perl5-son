# ABOUTME: a method call takes its class from a constructor invocant only: a
# ABOUTME: method on another method's value does not inherit that one's class.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub calls_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    my $w = eval { JSON::PP->new->decode($j) } or return [];
    return [ grep { $_->{op} eq 'Call' } @{ $w->{methods}{'main::__PROGRAM__'}{nodes} // [] } ];
}

# `$x->b->n`: ->b returns a Box, so ->n is not K::n (it was, and a program
# whose types lined up would have called the wrong method).
my $calls = calls_of(q{use v5.42; use experimental 'class';
package Box { sub new ($c) { bless { n => 1 }, $c } sub n ($s) { "box" } }
class K { field $b :param :reader = Box->new; method n { "K" } }
my $x = K->new;
print $x->b->n, "\n";
});
my ($n) = grep { ( $_->{fields}{name} // '' ) eq 'n' } @$calls;
ok $n, 'the ->n call is there';
isnt $n->{fields}{class_name} // '', 'K', '->n on ->b is not named K';

# ...but a constructor's object still names its class.
$calls = calls_of(q{use v5.42; use experimental 'class';
class K { method n { "K" } }
print K->new->n, "\n";
});
($n) = grep { ( $_->{fields}{name} // '' ) eq 'n' } @$calls;
is $n->{fields}{class_name}, 'K', 'K->new->n is K::n';

done_testing;
