# ABOUTME: a shared variable that is the FILE's (the program's, or one a named sub or the
# ABOUTME: program's sort block reaches out to) says file; a sub's own a closure captures does not.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub shared ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
    my %by;
    for my $m (keys %{ $j->{methods} }) {
        my $walk; $walk = sub ($x) {
            if (ref $x eq 'HASH') { push @{ $by{$m} }, $x->{fields} if ( $x->{op} // '' ) eq 'PadAccess' && $x->{fields}{shared}; $walk->($_) for values %$x }
            elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
        };
        $walk->($j->{methods}{$m});
    }
    return \%by;
}
my $by = shared(q{my $n = 0; sub f { $n++ } f(); print "$n\n";});
ok(( grep { $_->{file} } @{ $by->{'main::__PROGRAM__'} // [] } ), 'the program\'s view of its lexical a sub shares: file');
ok(( grep { $_->{file} } @{ $by->{'main::f'} // [] } ), 'the sub\'s view: file');
$by = shared(q{my %h = (x => 1, y => 2); print join(",", sort { $h{$a} <=> $h{$b} } keys %h), "\n";});
ok(( grep { $_->{file} } @{ $by->{'main::__PROGRAM__::__SORTCMP__:1'} // [] } ), 'a program sort block\'s view of its hash: file');
$by = shared(q{sub f { my @a; my $c = sub { push @a, $_[0] }; $c->(1); scalar @a } print f(), f(), "\n";});
my @own = map { @$_ } values %$by;
ok(@own && !( grep { $_->{file} } @own ), 'a sub\'s own array a closure captures: not file');
done_testing;
