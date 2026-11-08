# ABOUTME: a push onto a field array is a memory version, as one onto any array is: a count
# ABOUTME: after it reads the push's version, not the method's entry (1 for perl's 2).
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh q{use feature "class"; no warnings "experimental::class"; class Q { field @items; method add ($x) { push @items, $x; return scalar @items } } my $q = Q->new; $q->add("a"); print $q->add("b"), "\n";};
close $fh;
my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
my (@push, @count);
my $walk; $walk = sub ($x) {
    if (ref $x eq 'HASH') {
        if (ref $x->{nodes} eq 'ARRAY' && grep { ( $_->{op} // '' ) eq 'Count' } @{ $x->{nodes} }) {
            my %n = map { ( $_->{id} => $_ ) } @{ $x->{nodes} };
            @push  = grep { ( $_->{op} // '' ) eq 'Call' && ( $_->{fields}{name} // '' ) eq 'push' } values %n;
            @count = grep { ( $_->{op} // '' ) eq 'Count' } values %n;
        }
        $walk->($_) for values %$x;
    }
    elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
};
$walk->($j);
is(scalar @push, 1, 'one push onto the field array');
ok($push[0] && $push[0]{fields}{memory_input}, 'it takes memory');
ok(@count && $count[0]{inputs}[1] == $push[0]{id}, 'the count after it reads its version');
done_testing;
