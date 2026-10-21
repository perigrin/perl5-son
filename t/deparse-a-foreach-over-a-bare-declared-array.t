# ABOUTME: A foreach over a lexical array whose binding carries no stamp -- declared bare
# ABOUTME: and pushed to, or captured from file scope -- or over a $_-iterated deref, round trips.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

round_trips(q{sub f { my @a; push @a, 1, 2; my $s = 0; for my $x (@a) { $s += $x } $s } print f(), "\n";},
    'a bare-declared array filled by push');
round_trips(q{my @F = qw(a b c); sub f { my $s = ""; for my $x (@F) { $s .= $x } return $s } print f(), "\n";},
    'a file-scoped array captured by a sub');
round_trips(q{sub f { my @a; push @a, 1, 2; for my $x (@a) { $x *= 10 } "@a" } print f(), "\n";},
    'an iterator write reaches a bare-declared array');
round_trips(q{sub f { my @a; push @a, 3, 4; my $s = ""; for (@a) { $s .= $_ } $s } print f(), "\n";},
    'an implicit $_ over a bare-declared array');
round_trips(q{use v5.42; sub c($k) { my %s; $s{$_} = 1 for $k->@*; join ",", sort keys %s } print c([2,1]), "\n";},
    'an implicit $_ over a dereferenced parameter');
round_trips(q{sub f { my $r = $_[0]; my $t = ""; for (@$r) { $t .= $_ } $t } print f([7,8]), "\n";},
    'an implicit $_ over @$r');

# A MERGED BINDING OF UNSTAMPED ARRAYS -- `@l = @n` in one arm -- was a Phi
# stamped List, which the renderer declared a scalar (`02` for `aabbab`).
# Two arrays merge to an array. And the copy `@l = @n` is a read of @n at its
# place: floating, it was spelled in the prologue, before the loop filled @n.
# chalk's EmitHelpers::emit_cfg_loop rewrites `@lines` so in two ifs.
round_trips(q{sub f { my @l; push @l, "a", "b"; if ($_[0]) { my @n; for my $x (@l) { push @n, $x, $x } @l = @n; } my $s=""; for my $y (@l) { $s .= $y } $s } print f(1), f(0), "\n";},
    'a foreach over an array reassigned in one arm');
round_trips(q{sub f { my @lines; push @lines, "a", "b"; if ($_[0]) { my @n; for my $l (@lines) { push @n, uc $l } @lines = @n } if ($_[1]) { my @n; for my $l (@lines) { push @n, "$l$l" } @lines = @n } my $s = ""; for my $l (@lines) { $s .= $l } return $s } print f(1, 0), f(0, 1), f(1, 1), f(0, 0), "\n";},
    'an array rewritten in two ifs, then iterated');
round_trips(q{sub f { my @l = (1); my @n = (2, 3); @l = @n if $_[0]; push @n, 4; return "@l" } print f(1), "|", f(0), "\n";},
    'a copy of an array, the source pushed after');
# TWO `my @n` IN SIBLING BLOCKS are two arrays, and spelled by name they were
# one: the second pushed onto the first's leftovers (`1;1 2;` for `1;2;`).
round_trips(q{sub f { my $s = ""; if ($_[0]) { my @n; push @n, 1; $s .= "@n;" } if ($_[1]) { my @n; push @n, 2; $s .= "@n;" } $s } print f(1, 1), f(0, 1), "\n";},
    'two sibling arrays of one name');
round_trips(q{sub f { my $s = ""; if ($_[0]) { my %h; $h{a}++; $s .= join(",", %h) . ";" } if ($_[1]) { my %h; $h{b}++; $s .= join(",", sort keys %h) . ";" } $s } print f(1, 1), "\n";},
    'two sibling hashes of one name');

# A LOOP'S HEADER Phi of such an array is no join merge: a pushed array
# cleared in an arm, read inside the enclosing loop, as chalk's Earley
# drains `@pending_sweeps`.
round_trips(q{sub f { my @p; my $out = ""; for my $pos (0 .. 5) { push @p, $pos if $pos % 2; if (@p > 1) { for my $s (@p) { $out .= $s } $out .= "|"; @p = (); } } return "$out @p" } print f(), "\n";},
    'a pushed array drained and cleared in an arm of a loop');

# A MERGE OF AN ARRAY'S BINDINGS THROUGH AN UNSTAMPED LOOP PHI: `@body =
# $s->@* if defined $s` in a loop was declared `$phi71`, the array's last
# element (chalk's Perl::Actions::MethodDefinition; `|1` for perl's `|3`).
round_trips(<<'SRC', 'an array rebound under a condition in a loop, by elsif arms');
package L { sub new { bless { f => $_[1], r => $_[2] }, $_[0] } sub extract { $_[0]{f} } sub rule { $_[0]{r} } }
sub stmts { return $_[0] } sub leaves { @_ }
sub f {
    my @leaves = leaves(@_);
    my $name; my @params; my @body;
    for my $leaf (@leaves) {
        my $focus = $leaf->extract();
        my $rule = $leaf->rule();
        if (!ref $focus && !defined $name) {
            $name = $focus;
        } elsif (defined $rule && $rule eq 'Block') {
            my $stmts = stmts($focus);
            @body = $stmts->@* if defined $stmts;
        } elsif (ref($focus) eq 'ARRAY') {
            if (defined $rule && $rule eq 'Signature') {
                @params = $focus->@*;
            } else {
                if (!@body) {
                    @body = $focus->@*;
                }
            }
        }
    }
    return "$name|@params|@body";
}
print f(L->new("method"), L->new([1, 2], "Signature"), L->new([3], "Block"), L->new([4], undef)), "\n";
SRC

# ...AND WITH A REFERENCE TO IT AFTER THE LOOP, each whole assign is a named
# version (`@body__89`), declared ahead of the conditions that guard it:
# `my @body__89 = ($focus->@*)` died on a $focus the arm had ruled out
# ("Not an ARRAY reference"; chalk's Perl::Actions::MethodDefinition).
round_trips(<<'SRC', 'a referenced array rebound under conditions in a loop');
use v5.42;
package L { sub new { bless { f => $_[1], r => $_[2] }, $_[0] } sub extract { $_[0]{f} } sub rule { $_[0]{r} } }
package K { sub new { bless {}, $_[0] } }
sub stmts { return $_[0]{s} } sub leaves { @_ }
sub f {
    my @leaves = leaves(@_);
    my $name; my @params; my @body; my $graph;
    for my $leaf (@leaves) {
        my $focus = $leaf->extract();
        my $rule = $leaf->rule();
        if ($focus isa K && !defined $name) {
            $name = "k";
        } elsif (defined $rule && $rule eq 'Block') {
            my $stmts = stmts($focus);
            @body = $stmts->@* if defined $stmts;
            if (ref($focus) eq 'HASH' && defined $focus->{graph}) {
                $graph = $focus->{graph};
            }
        } elsif (ref($focus) eq 'ARRAY') {
            if (defined $rule && $rule eq 'Signature') {
                @params = $focus->@*;
            } else {
                if (!@body) {
                    @body = $focus->@*;
                }
            }
        }
    }
    my $fb = \@body;
    return "$name|@params|@$fb|" . ($graph // "-");
}
print f(L->new(K->new), L->new([1, 2], "Signature"), L->new({ s => [3], graph => "g" }, "Block"), L->new([4], undef)), "\n";
SRC

# A LATCH OF AN ARRAY -- the value a `next` carries to the step -- was
# declared `$latchN`, and `$latchN = @phi` took the count (`n|1|3` for
# perl's `n|1 2|3 4 5`; chalk's Perl::Actions::SubroutineDefinition).
round_trips(<<'SRC', 'arrays carried past a next in a loop');
sub f {
    my @body; my @params; my $name;
    for my $x (@_) {
        if (!ref $x) {
            next if $x eq 'sub';
            $name = $x;
        } elsif (ref $x eq 'ARRAY') {
            if (@params) { @body = $x->@* } else { @params = $x->@* }
        }
    }
    return "$name|@params|@body";
}
print f("sub", "n", [1, 2], [3, 4, 5]), "\n";
SRC

# A PUSH ONTO AN ARRAY MERGED AT A JOIN: the mutator's container is spelled
# uncached (never a stale copy), and a join Phi uncached refused -- its
# binding, the join variable, IS the aggregate (chalk's
# EmitHelpers::emit_cfg_loop, `push @lines, "}"`).
round_trips(<<'SRC', 'a push onto an array merged at a join');
sub f { my ($c, @n) = @_; my @l = (1); if ($c) { if ("@l" =~ /1/ && "@n" =~ /2/) { my @x; push @x, @n; @l = @x } } push @l, "}"; return "@l" } print f(1, 2, 3), "|", f(0, 2), "\n";
SRC

# A GREP OVER AN ARRAY PUSHED INTO SINCE IT WAS COPIED read the copy's
# source: the push marks the slot, the grep flattened the literal by node
# (`0` for perl's `0 1`; chalk's Perl::Actions::_finalize_body_graph,
# `grep { ... } @seeds` after the schedule's pushes).
round_trips(q{sub f { my ($sc, @r) = @_; my @s = @r; push @s, 1; my @w = grep { defined } @s; return "@w" } print f([1], 0), "\n";},
    'a grep over a copied array pushed into');
round_trips(q{sub f { my ($sc, @r) = @_; my @s = @r; for my $h (@$sc) { push @s, $h } my @w = map { $_ * 2 } @s; return "@w" } print f([1, 2], 3), "\n";},
    'a map over a copied array pushed into in a loop');

# AN ARM THAT ENDS IN `next` AFTER A `die if`: the nested statement-modifier
# If bounded the walk for the latch, so the arm was not seen as a `next` and
# its fall-through paid the latch an unbound join -- refused (chalk's
# LLVM::Context::_compile_regex_pattern).
round_trips(<<'SRC', 'a next after a die-if, in a nested while');
sub f {
    my ($pattern) = @_;
    my @chars = split //, $pattern;
    my @out;
    my $i = 0;
    while ($i <= $#chars) {
        my $c = $chars[$i];
        if ($c eq '[') {
            my $j = $i + 1;
            while ($j <= $#chars && $chars[$j] ne ']') {
                my $cc = $chars[$j];
                if ($cc eq '\\') {
                    my $e = $chars[ $j + 1 ] // die "bare backslash";
                    if ($e =~ /^[dws]$/) {
                        die "unsupported" if $e =~ /[DWS]/;
                        push @out, "\\$e";
                        $j += 2;
                        next;
                    }
                }
                my $k = $j + 1;
                if (($chars[$k] // '') eq '-' && ($chars[ $k + 1 ] // ']') ne ']') {
                    push @out, "$cc-$chars[$k + 1]";
                    $k += 2;
                } else {
                    push @out, $cc;
                }
                $j = $k;
            }
            $i = $j + 1;
            next;
        }
        push @out, $c;
        $i++;
    }
    return join "|", @out;
}
print f('a[b-d\\wx]e'), "\n";
SRC

# ...AND A `next` WHOSE PAYMENT READS A JOIN INSIDE ITS ARM: the payment was
# rendered before the arm, so the join was not yet bound -- refused.
round_trips(<<'SRC', 'a next paying a value an if in its arm set');
sub esc { my ($c, $k) = @_; return (ord($c->[$k]), 2) }
sub f {
    my ($pattern) = @_;
    my @chars = split //, $pattern;
    my @out;
    my $j = 0;
    while ($j <= $#chars) {
        my $cc = $chars[$j];
        my ($lo, $lo_used) = (ord($cc), 1);
        my $k = $j + $lo_used;
        if (($chars[$k] // '') eq '-' && ($chars[ $k + 1 ] // ']') ne ']') {
            my ($hi, $hi_used) = (ord($chars[ $k + 1 ]), 1);
            if ($chars[ $k + 1 ] eq '\\') {
                ($hi, $hi_used) = esc(\@chars, $k + 2);
            }
            die "lo > hi" if $lo > $hi;
            push @out, "$lo-$hi";
            $j = $k + 1 + $hi_used;
            next;
        }
        push @out, $lo;
        $j = $k;
    }
    return "@out";
}
print f('a-cxb-\\z'), "\n";
SRC

done_testing;
