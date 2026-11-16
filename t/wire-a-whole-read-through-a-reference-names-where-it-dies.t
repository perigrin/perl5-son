# ABOUTME: `@$a > 0`, `my %c = %$h`: a whole array or hash read through a reference in an rvalue
# ABOUTME: context names its site and strict refs (perl dies of an undef there under them), and stands there.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use JSON::PP;

sub graph ($src, $sub = 'main::f') {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $j = decode_json(scalar qx($^X -Ilib -MO=-q,SoN,json $pl 2>/dev/null));
    return { map { $_->{id} => $_ } @{ $j->{methods}{$sub}{nodes} // [] } };
}
sub derefs ($n, $sigil) { grep { $_->{op} eq 'PostfixDeref' && $_->{fields}{sigil} eq $sigil } values %$n }

{   my $n = graph(q{use strict; sub f { my ($c) = @_; my $a = $c->{a}; return @$a > 0 ? 1 : 0 } print f({a => [1]}), "\n";});
    my @d = derefs($n, '@');
    is(scalar @d, 1, 'one whole array read');
    ok(@d && $d[0]{fields}{line} == 1 && $d[0]{fields}{file} =~ /\.pl\z/, 'it names its file and line');
    ok(@d && $d[0]{fields}{strict}, 'and that strict refs hold there');
    ok(@d && defined $d[0]{control_in}, 'it stands where the program reads it');
}
{   my $n = graph(q{sub f { my ($c) = @_; my $a = $c->{a}; return @$a > 0 ? 1 : 0 } print f({a => [1]}), "\n";});
    my @d = derefs($n, '@');
    ok(@d && defined $d[0]{fields}{line} && !$d[0]{fields}{strict}, 'without strict refs: its site, not strict');
}
{   my $n = graph(q{use strict; sub f { my ($h) = @_; my %c = %$h; return join ",", keys %c } print f({a => 1}), "\n";});
    my @d = derefs($n, '%');
    ok(@d >= 1 && !grep({ !defined $_->{fields}{line} || !$_->{fields}{strict} } @d), 'a hash copied whole: each of its reads names its site');
}
for my $case (
    [ q{use strict; sub f { my ($c) = @_; my $n = 0; for my $e (@$c) { $n++ } $n } print f([1]), "\n";}, 'a foreach walking it' ],
    [ q{use strict; sub f { my ($c) = @_; my @m = map { $_ } @$c; scalar @m } print f([1]), "\n";}, 'a map over it' ],
    [ q{use strict; sub f { my ($h) = @_; my @k = keys %$h; scalar @k } print f({a => 1}), "\n";}, 'keys of it' ],
    [ q{use strict; sub g { scalar @_ } sub f { my ($c) = @_; g(@$c) } print f([1]), "\n";}, "a call's argument" ],
) {
    my ($src, $name) = @$case;
    my $n = graph($src);
    ok(!grep({ defined $_->{fields}{line} } derefs($n, '@'), derefs($n, '%')), "$name: perl makes it there, and dies of nothing: no site");
}
for my $case (
    [ q{use strict; sub f { my @r = ("Zy" .. "AAb"); scalar(@r) } print f(), "\n";}, 'a list perl folded to a constant array' ],
    [ q{use strict; sub f { my $n = @{[1, 2]}; $n } print f(), "\n";}, 'a fresh [...]' ],
) {
    my ($src, $name) = @$case;
    my $n = graph($src);
    ok(!grep({ defined $_->{fields}{line} } derefs($n, '@'), derefs($n, '%')), "$name: never other than an array: no site");
}
{   # AN ARM IN A LOOP BODY on its own Proj pins it where it stands (pvm c221)
    my $n = graph(q{sub f { my ($c) = @_; my $n = 0; while ($n < 3) { if (ref $c) { my $a = $c->{a}; $n = 7 if @$a > 0 } $n++ } $n } print f({a => [1]}), "\n";});
    my @d = derefs($n, '@');
    ok(@d && defined $d[0]{control_in}, "in an if's arm in a loop body: where it stands");
    my ($el) = grep { $_->{op} eq 'Subscript' && $_->{fields}{kind} eq 'hash' } values %$n;
    ok($el && defined $el->{control_in}, 'as is the element read through the reference before it');
}
done_testing;
