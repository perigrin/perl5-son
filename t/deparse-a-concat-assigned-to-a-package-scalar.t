# ABOUTME: `$G = $x . "ab"` stores $x's concatenation into $G. perl pushes the stacked
# ABOUTME: destination last; taken for the first operand, it stored $G . "ab" instead.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use SoN::Deparse;

my $dir = tempdir( CLEANUP => 1 );
sub run_perl ($code) {
    my $f = "$dir/r." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $code; close $fh;
    my $out = qx($^X $f 2>&1); unlink $f;
    return $out;
}
for my $src (
    qq{our \$G = "g";\nmy \$x = \$ENV{X} // "z";\n\$G = \$x . "ab";\nprint "\$G\\n";\n},
    qq{our \$G = "g";\nsub sv { my \$x = \$ENV{X} // "z"; \$G = \$x . "ab" . \$x; return 1 }\nsv();\nprint "\$G\\n";\n},
    qq{our \$G = "g";\n\$G = \$G . "ab";\nprint "\$G\\n";\n},
    qq{our \$G = "g";\nmy \$x = "y";\n\$G .= \$x . "ab";\nprint "\$G\\n";\n},
) {
    my $f = "$dir/p.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null);
    my $d   = SoN::Deparse->new;
    my $out = $d->render( JSON::PP->new->decode($json) );
    is run_perl( $out // '' ), run_perl($src), 'as perl: ' . ( $src =~ s/\n/ /gr ) or diag $out // $d->gap;
}
done_testing;
