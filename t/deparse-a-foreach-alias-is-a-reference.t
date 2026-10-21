# ABOUTME: A foreach over a list a call can reach aliases each element by reference:
# ABOUTME: its iterator reads the element where the read stands, as perl's alias does.

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

# THE ITERATOR IS AN ALIAS, and the lowering bound it to the element read
# at the top of the pass -- a copy. A callee that reaches the list changes
# what perl's alias reads and not the copy, so such a body refused (chalk's
# Analysis, Context, Actions: `for my $n (@$nodes) { $self->visit($n) ...`).
# A reference taken at the top of the pass is the alias: read through it,
# the iterator sees an in-place change, and a shift does not move it.
round_trips(q{sub g { $_[0][$_[1]] = $_[0][$_[1]] . "!" } sub f { my $l = [qw(a b c)]; my $s = ""; my $i = 0; for my $x (@$l) { g($l, $i++); $s .= $x } "$s|@$l" } print f(), "\n";},
    'a callee changes the element in place');
round_trips(q{sub g { shift @{$_[0]} } sub f { my $l = [qw(a b c d)]; my $s = ""; for my $x (@$l) { $s .= $x; g($l); $s .= $x . ";" } "$s|@$l" } print f(), "\n";},
    'a callee shifts the list under the iterator');
round_trips(q{package V { sub new { bless { seen => [] }, shift } sub visit { my ($s, $n) = @_; push $s->{seen}->@*, $n->{id}; $n->{id} = $n->{id} . "v" } } sub f { my ($nodes) = @_; my $v = V->new; my @out; for my $n (@$nodes) { $v->visit($n); push @out, $n->{id} } return "@out|" . join(",", $v->{seen}->@*) } print f([{ id => 1 }, { id => 2 }]), "\n";},
    'a method call takes the iterator');
round_trips(q{sub f { my @q; push @q, 1; my $s = ""; for my $x (@q) { push @q, $x + 1 if $x < 3; $s .= $x } "$s|@q" } print f(), "\n";},
    'the body pushes onto the list it iterates');
round_trips(q{sub g { $_[0] = uc $_[0] } sub f { my $l = [qw(a b)]; my $s = ""; for my $x (@$l) { g($x); $s .= $x } "$s|@$l" } print f(), "\n";},
    'a callee writes the iterator through @_');

# A READ IN A BRANCH stays unpinned: an if/else whose arms only rebind
# scalars is a value merge, its arms sharing one control node, and a pin in
# each gave it two successors. The stale-read rules hold it in order.
round_trips(q{sub g { 1 } sub f { my $l = [3, 4, 5]; my $s = ""; for my $x (@$l) { g(); if ($x > 3) { $s .= "b$x" } else { $s .= "s$x" } } $s } print f(), "\n";},
    'a read in each arm of a value if/else');
round_trips(q{sub g { 1 } sub f { my $l = [1, 2, 3]; my $t = 0; for my $x (@$l) { next if $x == 2; g(); $t += $x; last if $t > 3 } $t } print f(), "\n";},
    'a guard on the iterator, and an accumulator');
round_trips(q{package O { sub new { bless { n => $_[1] }, $_[0] } sub n { $_[0]{n} } } sub g { 1 } sub f { my $l = [O->new(1), O->new(2)]; my $s = 0; for my $o (@$l) { g(); $s += $o->n } $s } print f(), "\n";},
    'the iterator as a method invocant');

# A NESTED LOOP'S SCOUT must not see the outer reference: its probe hung a
# push on the real nodes the reference is built from, and it leaked into
# the graph (chalk's TypedInvariant::check_nodes).
round_trips(q{sub ok { 1 } sub f { my ($nodes) = @_; my @v; for my $node (@$nodes) { ok(); for my $i (0 .. 1) { push @v, $node->[0] } } "@v" } print f([["a", "b"], ["c"]]), "\n";},
    'an inner loop reads the outer iterator');
# AN ITERATOR NEVER READ leaves its reference unread (chalk's Earley::_predict).
round_trips(q{sub g { $_[0] } sub f { my ($items) = @_; my $s = ""; for my $e (@$items) { my ($c, $k) = @$e; unless ($c > 2) { my $v = 1; if ($k) { for my $q (@$k) { $v = g($v); last if !$v } next if !$v } $s .= "$c" } } $s } print f([[1, [2]], [3, [4]]]), "\n";},
    'an inner loop whose iterator is never read');
round_trips(q{sub g { 1 } sub f { my ($items) = @_; my $s = ""; for my $e (@$items) { my ($c, $k) = @$e; g(); $s .= "$c$k" } $s } print f([[1, 2], [3, 4]]), "\n";},
    'the iterator destructured');

# A CALL MAY HAND BACK A REFERENCE TO THE ITERATOR it was passed, which the
# copy cannot be and the reference is -- over a list a call made, which has
# no holes and no container to ask (chalk's LLVM::_populate_registry_from_mop_class).
round_trips(<<'SRC', 'a callee returning a reference to the iterator, over a call\'s list');
package S { sub new { bless { n => $_[1] }, $_[0] } sub name { $_[0]{n} } }
package C { sub new { bless {}, shift } sub subs { (S->new("a"), S->new("b"), S->new("a")) } }
sub root { my ($s) = @_; return \$_[0] }
sub f { my ($cls) = @_; my $reg = { subs => [] }; for my $s ($cls->subs) { my $sname = $s->name; next if grep { ($_->{name} // '') eq $sname } @{ $reg->{subs} }; my $b = root($s); push @{ $reg->{subs} }, { name => $sname, body => ref $b, same => ($$b == $s ? 1 : 0) } } join ",", map { "$_->{name}:$_->{body}:$_->{same}" } @{ $reg->{subs} } }
print f(C->new), "\n";
SRC

# OVER A DEREFERENCE TOO: its later reads go through memory, so a store
# through the reference a callee handed back is seen. Over an array bound as
# its literal it is not, and that still refuses (iterator-reference tests).
for ( [ 'carried out',            'my $r; for my $x (@$a) { g(); $r = k($x) } $$r = 5;' ],
      [ 'pushed',                 'my @r; for my $x (@$a) { g(); push @r, k($x) } ${$r[0]} = 5;' ],
      [ 'stored into a hash',     'my %h; for my $x (@$a) { g(); $h{$x} = k($x) } ${$h{1}} = 5;' ],
      [ 'with no other call',     'my $r; for my $x (@$a) { $r = k($x) } $$r = 5;' ] ) {
    round_trips(qq{sub k { return \\\$_[0] } sub g { 1 } sub f { my (\$a) = \@_; $_->[1] return "\@\$a" } print f([1,2]), "\\n";},
        "a callee's reference to the iterator over a dereference, $_->[0]");
}

# THE COPY THE PASS WOULD HAVE BOUND is unread when the iterator is a
# reference, and it rode into the graph dead: the stale-read pass spelled it
# ahead of the loop whose index it names (chalk's Earley::_run_parse,
# `Global symbol "$phi931"`).
for ( [ 'an unread iterator',               '$n++' ],
      [ 'a grep over the iterator',         '$n += grep { defined } $oh->@*' ] ) {
    round_trips(qq{sub set { my (\$c, \$p) = \@_; push \$c->[\$p]->\@*, [1, undef, 2] }
sub f { my \@chart = map { [] } 0 .. 2; my \$n = 0;
  for my \$pos (0 .. 2) { set(\\\@chart, \$pos);
    if (\$ENV{P} // 1) { for my \$oh (\$chart[\$pos]->\@*) { $_->[1] } }
    \$chart[\$pos - 1] = [] if \$pos > 1 }
  return \$n }
print f(), "\\n";},
        "a nested loop over an element of a referenced array, $_->[0]");
}

# OVER A NAMED ARRAY TOO, once its literal is marked changed: a later read
# names the array itself, which the reference points into. Refused before
# (chalk's LLVM::Context::_process_loop_node, `_require_repr($phi, ...)`
# through a glob alias no compile-time scan can see).
for ( [ 'carried out',        'my $r; for my $x (@a) { $r = k($x) } $$r = 5;' ],
      [ 'pushed',             'my @r; for my $x (@a) { push @r, k($x) } ${$r[0]} = 5;' ],
      [ 'stored into a hash', 'my %h; for my $x (@a) { $h{$x} = k($x) } ${$h{1}} = 5;' ] ) {
    round_trips(qq{sub k { return \\\$_[0] } sub g { (1, 2) } sub f { my \@a = g(); $_->[1] return "\@a" } print f(), "\\n";},
        "a callee's reference to the iterator over a named array, $_->[0]");
}

# A LIST A GREP BUILT is its accumulator, spelled `@phiN`: the reference is
# into it, as into a named array.
round_trips(q{sub k { return \$_[0] } sub g { (1, 2, 3) } sub f { my @a = grep { $_ > 1 } g(); my $r; for my $x (@a) { $r = k($x) } $$r = 5; return "@a" } print f(), "\n";},
    "a callee's reference to the iterator over a list a grep built");

# A WHILE TEST THAT IS A DIAMOND'S JOIN, inside a loop whose body is walked
# twice (an outer foreach aliased by reference): the first walk bound the
# join's `$phiN`, and the second took the bound test for an effect and
# spelled the Phi as one -- refused (chalk's
# Analysis::_stamp_method_call_reprs).
round_trips(<<'SRC', 'a while test over an and, nested in aliased loops');
package Nd { sub new { my ($c, %a) = @_; bless {%a}, $c } sub id { $_[0]{id} } sub class_name { $_[0]{c} } sub name { $_[0]{n} } sub target { undef } }
package G { sub new { bless { n => $_[1] }, $_[0] } sub nodes { $_[0]{n} } }
package P { sub new { bless { s => $_[1] }, $_[0] } sub superclass { $_[0]{s} } }
package Mop { sub new { bless { m => $_[1] }, $_[0] } sub for_class { $_[0]{m}{$_[1]} } }
sub _control_chain_nodes { () }
sub _stamp_method_call_reprs {
    my ($graphs, $mop) = @_;
    my @out;
    for my $g (values %$graphs) {
        my %seen;
        my @nodes = grep { !$seen{ $_->id }++ }
            ($g->nodes->@*, _control_chain_nodes($g));
        for my $node (@nodes) {
            my $class = $node->class_name // next;
            my $mname = $node->name // '';
            my $target = $node->target;
            my $c = ($target && $target->isa('Chalk::MOP::Method'))
                  ? $target->class->name
                  : $class;
            my %walked;
            while (defined $c && !$walked{$c}++) {
                my $pc  = $mop->for_class($c);
                my $sup = $pc ? $pc->superclass : undef;
                push @out, "$mname:$c";
                $c = $sup;
            }
        }
    }
    return "@out";
}
print _stamp_method_call_reprs({ g => G->new([Nd->new(id => 1, c => "A", n => "m"), Nd->new(id => 2), Nd->new(id => 1, c => "Z")]) },
    Mop->new({ A => P->new("B"), B => P->new(undef) })), "\n";
SRC

# A READ OF THE ALIAS IS PERL'S ALIAS READ WHERE IT IS USED: in
# `$h{ k($x) } = $x` perl reads the right side after k() changed it
# (`1!=1!`). The stale-read rule took the read for a copy made before the
# call and refused (chalk's LLVM::Context::_collect_positional_arg_reads).
round_trips(<<'SRC', 'an alias read under an if statement, after calls on it');
use v5.42; use Scalar::Util qw(blessed);
package Nd { sub new { my ($c, %a) = @_; bless {%a}, $c } sub index { $_[0]{i} } sub name { $_[0]{n} } sub op { $_[0]{o} } sub consumers { $_[0]{c} // [] } }
package Gr { sub new { bless { n => $_[1] }, $_[0] } sub nodes { $_[0]{n} } }
package main;
sub f {
    my ($graph) = @_;
    my %params; my @out;
    for my $n ($graph->nodes->@*) {
        if ($n->op eq 'Parameter') {
            $params{ $n->index } = $n;
        }
        if ($n->op eq 'Call' && defined $n->name && ($n->name eq 'shift' || $n->name eq 'pop')) {
            my @other = grep { blessed($_) && !($_->op eq 'Call' && $_->name eq 'shift') } $n->consumers->@*;
            push @out, scalar(@other);
        }
    }
    return join(",", sort keys %params) . "|@out";
}
print f(Gr->new([Nd->new(o => 'Parameter', i => 0), Nd->new(o => 'Call', n => 'shift', c => [Nd->new(o => 'X')]), Nd->new(o => 'Parameter', i => 1)])), "\n";
SRC
round_trips(q{sub k { $_[0] = $_[0] . "!"; 1 } sub f { my ($r) = @_; my %h; for my $x (@$r) { if ($x) { $h{ k($x) . $x } = $x } } return join ",", map { "$_=$h{$_}" } sort keys %h } print f([1, 2]), "\n";},
    'an alias read on the right of an assign whose key calls on it');

done_testing;
