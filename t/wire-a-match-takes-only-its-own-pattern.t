# ABOUTME: `$s =~ $re` takes $re as its pattern, not values an earlier list left
# ABOUTME: on the stack: only a regcomp whose kid is a list joins parts into one.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub match_rhs ($src, $sub) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    my $w = decode_json( scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null) );
    my @n = @{ $w->{methods}{$sub}{nodes} };
    my ($m) = grep { $_->{op} eq 'Match' } @n;
    return $m ? $n[ $m->{inputs}[1] ] : undef;
}

# A MARK STILL OPEN -- `my $ok = ...`'s -- was taken for the pattern's: the
# pattern became $got's ternary . $s . $re (Test::Chalk's like, a silent wrong).
my $rhs = match_rhs( <<'EOT', 'main::like' );
sub like { my ( $got, $re ) = @_; my $s = defined $got ? $got : ''; my $ok = $s =~ $re ? 1 : 0; return $ok }
print like( 'abc', qr/b/ ), "\n";
EOT
is $rhs && $rhs->{op}, 'PadAccess', 'the pattern is $re itself' or diag explain $rhs;
is $rhs && $rhs->{fields}{symbol}, 're', '... by name';

# AN INTERPOLATED PATTERN still joins its parts.
$rhs = match_rhs( qq{my \$p = \$ENV{P} // "a"; my \$s = \$ENV{S} // "xay";\nprint \$s =~ /x\${p}y/ ? 1 : 0, "\\n";\n}, 'main::__PROGRAM__' );
is $rhs && $rhs->{op}, 'Concat', 'x${p}y: its parts joined' or diag explain $rhs;

done_testing;
