# ABOUTME: a scalar deref may die, so it names its site (file, line, eval) and whether `strict
# ABOUTME: refs` holds there, as a may-die divide does -- and in an eval body it is pinned.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub derefs ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
    my @d;
    my $walk; $walk = sub ($x) {
        if (ref $x eq 'HASH') { push @d, $x if ( $x->{op} // '' ) eq 'PostfixDeref' && ( $x->{fields}{sigil} // '' ) eq '$'; $walk->($_) for values %$x }
        elsif (ref $x eq 'ARRAY') { $walk->($_) for @$x }
    };
    $walk->($j);
    return ($pl, @d);
}
{   my ($pl, @d) = derefs(qq{use strict;\nmy \$x = 1; my \$r = \\\$x;\nprint \$\$r, "\\n";\n});
    is($d[0]{fields}{line}, 3, 'its line');
    is($d[0]{fields}{file}, $pl, 'its file');
    ok($d[0]{fields}{strict}, 'under strict refs');
}
{   my (undef, @d) = derefs(q{my $x = 1; my $r = \$x; print $$r, "\n";});
    ok(!$d[0]{fields}{strict}, 'not under strict refs');
}
{   my (undef, @d) = derefs(q{use strict; my $r = [1]; eval { my $t = $$r; 1 }; print "x\n";});
    ok(@d && defined $d[0]{fields}{eval_id}, 'in an eval body: names its eval');
    ok(@d && defined $d[0]{control_in}, 'and is on the chain, though its value is unused');
}
done_testing;
