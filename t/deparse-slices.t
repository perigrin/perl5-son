# ABOUTME: List, array and hash slices must round-trip through the oracle.
# ABOUTME: A hash slice subscripts with braces; only the container's sigil says so.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use lib 'lib';
use SoN::Deparse;

sub run_src ($src) {
    my $file = __FILE__ . ".run.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    # STDOUT ONLY: the emission runs under warnings the source may not.
    my $out = qx($^X $file 2>/dev/null);
    unlink $file;
    return $out;
}

sub emit ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) } or return undef;
    return SoN::Deparse->new->render($data);
}

sub round_trips ($name, $src) {
    my $emitted = emit($src);
    ok defined $emitted, "$name: it renders" or return;
    is run_perl_pair($emitted, $src), 1, "$name: it agrees with perl"
        or diag "emitted:\n$emitted";
}

sub run_perl_pair ($emitted, $src) {
    return run_src($emitted) eq run_src($src) ? 1 : 0;
}

# `(qw(p q r))[1]` is lslice over TWO mark-delimited lists. A fixed arity of 2
# took the last two stack entries: the index and the first value were dropped
# and "p" leaked into the print. The one-element form was a silent WRONG
# ANSWER -- `print( (qw(b))[0] )` emitted nothing where perl prints "b".
subtest 'a list slice renders as (VALUES)[INDICES]' => sub {
    round_trips 'single index', qq{print( (qw(p q r))[1], "\\n" );\n};
    round_trips 'one element',  qq{print( (qw(b))[0], "\\n" );\n};
    round_trips 'two indices',  qq{print( (qw(p q r))[0,2], "\\n" );\n};
    round_trips 'string list',  qq{print( ("a","b","c")[2], "\\n" );\n};
};

# The container form puts the container LAST and every index before it. The
# renderer accepted only two inputs, so a multi-index array slice -- three
# inputs -- was refused although it is perfectly spellable.
subtest 'an array slice takes every index' => sub {
    round_trips 'two indices',
        qq{my \@a = ("x","y","z");\nprint( \@a[0,2], "\\n" );\n};
    round_trips 'one index',
        qq{my \@a = ("x","y","z");\nprint( \@a[1], "\\n" );\n};
};

# `@h{...}` and `@a[...]` are both Slice nodes carrying an `@` sigil of their
# own. Only the CONTAINER's sigil says which brackets to emit, and `@h[...]`
# would index a different variable that need not even exist.
subtest 'a hash slice subscripts with braces' => sub {
    round_trips 'two keys',
        qq{my \%h = (k1=>"v1", k2=>"v2");\nprint( \@h{"k1","k2"}, "\\n" );\n};
};

# A SLICE OF AN ARRAY THE LOOP MAKES EACH PASS is a slice of the variable
# its merge is declared as: `@p` is fresh per pass and reaches the slice
# through a Phi, which has no symbol of its own but is spelled `@phiN`.
# chalk's Dominators::from_return_node takes `@preds[1..$#preds]` so.
round_trips('a slice of an array made in the loop body',
    q{sub f { my %idom = (a => 1, b => 2, c => 3); my $out = ""; for my $k (qw(x y)) { my @p = grep { exists $idom{$_} } qw(a b c); next unless @p; my $n = $p[0]; for my $q (@p[1 .. $#p]) { $n .= $q } $out .= "$k$n " } $out } print f(), "\n";});

# A SLICE OF A DEREFERENCE is a postfix slice: `$r->@[...]`, `$r->@{...}`.
round_trips('a slice of a dereferenced array and hash',
    q{use v5.42; sub f ($r, $h) { my @a = $r->@[1, 2]; my @b = $h->@{qw(x y)}; return "@a|@b" } print f([5, 6, 7], { x => 1, y => 2 }), "\n";});
# A SLICE IN AN ALIASED LIST -- grep's, map's -- is the same slice, though
# perl flags it modifiable: chalk's FilterComposite greps
# `$semirings->@[0 .. $#{ $semirings } - 1]`.
round_trips('a slice of a referenced field, grepped',
    q{use v5.42; use experimental 'class'; class K { field $r = [3, 4, 5, 6]; method s { my @x = grep { $_ > 3 } $r->@[0 .. $#{ $r } - 1]; "@x" } } print K->new->s, "\n";});
round_trips('a hash slice of a reference, mapped',
    q{use v5.42; sub f ($h) { join ",", map { $_ * 2 } $h->@{qw(a b)} } print f({ a => 1, b => 2 }), "\n";});
round_trips('a slice of an array field',
    q{use v5.42; use experimental 'class'; class K { field @f = (4, 5, 6); method s { my @x = @f[0, 2]; "@x" } } print K->new->s, "\n";});

# A SLICE THROUGH A REFERENCE THE PROGRAM COMPUTED -- `$n->{in} // []` -- slices
# postfix off that expression; it has no name to give (chalk's
# LLVM::Context::_lower_list_append).
round_trips('a slice through a defaulted reference',
    q{sub f { my ($n) = @_; my $i = $n->{in} // []; my @r = grep { defined } @{[ @$i[1 .. $#$i] ]}; return "@r" } print f({ in => [1, 2, 3] }), "|", f({}), "\n";});

# A SLICE BY A GREP INSIDE AN ARM, into a named array: the array's declaration
# followed its bound `inputs()` call and named the grep's result above its loop
# (chalk's IR::Analysis::_element_repr, `@phi102` undeclared).
round_trips('a slice by a grep in an elsif arm, over a call result',
    q{sub mk { my ($op, @in) = @_; { op => $op, in => [@in] } } sub operation { $_[0]{op} } sub inputs { $_[0]{in} } sub f { my ($c) = @_; my $op = operation($c); my @in = inputs($c)->@*; my @e; if ($op eq "A") { @e = @in } elsif ($op eq "H") { @e = @in[ grep { $_ % 2 } 0 .. $#in ] } else { return "u" } return "@e" } print f(mk("A", 1, 2)), "|", f(mk("H", "k", 1, "j", 2)), "|", f(mk("X")), "\n";});

# A SLICE THROUGH A SCALAR HOLDING A REFERENCE -- `@{$c}[...]` -- slices the
# referent: spelled by the scalar's name as `@c[...]` it named an array that
# does not exist (chalk's LLVM::Context::_regex_escape_byte).
round_trips('a slice through a scalar reference',
    q{sub f { my ($c, $i) = @_; return join "", grep { defined } @{$c}[$i + 1, $i + 2] } sub g { my ($h) = @_; return join ",", @{$h}{qw(a b)} } print f([qw(a b c d)], 0), f([qw(a b)], 0), g({a => 1, b => 2}), "\n";});

done_testing;
