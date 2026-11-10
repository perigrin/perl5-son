# ABOUTME: a call to an XS sub carries xs on the wire: it has no Perl source, so a
# ABOUTME: backend refuses it by name. A pure-Perl sub from another module does not.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub calls ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null);
    my %by;
    my $walk; $walk = sub ($x) {
        if (ref $x eq 'HASH') { $by{ $x->{fields}{name} } = $x->{fields} if ( $x->{op} // '' ) eq 'Call' && defined $x->{fields}{name}; $walk->($_) for values %$x }
        elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
    };
    $walk->(decode_json($json));
    return \%by;
}

my $c = calls(qq{use List::Util qw(sum);\nmy \$i = \$ENV{X} // 2;\nprint sum(\$i, 1), "\\n";\n});
ok($c->{'main::sum'}, 'the XS call is there');
ok($c->{'main::sum'}{xs}, 'and says it is XS');

$c = calls(qq{use Text::Wrap qw(wrap);\nprint wrap('', '', \$ENV{X} // 'a b'), "\\n";\n});
# A PURE-PERL MODULE IS FOLLOWED: its sub is on the wire, so the imported
# call names the sub's home (wire-a-used-module-s-subs-are-included.t).
ok($c->{'Text::Wrap::wrap'}, 'the pure-Perl call is there, by its home name');
ok(!$c->{'Text::Wrap::wrap'}{xs}, 'and is not XS');
done_testing;
