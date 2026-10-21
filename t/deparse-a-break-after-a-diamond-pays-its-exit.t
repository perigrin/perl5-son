# ABOUTME: A `last` after a postfix if in the same arm pays the loop's exit
# ABOUTME: values: the payment walk passes the diamond as the edge test does.

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

# THE PAYMENT WALK STOPPED AT THE NESTED IF that the edge test passes over by
# its merge, and found no exit edge: `$base = $args->[0] if $args->@* > 0;
# last` (chalk's EmitHelpers::_build_exists_delete_native).
round_trips(<<'SRC', 'a last after a postfix if, in a method loop');
use v5.42; use experimental "class";
package Chalk::IR::Node { sub new { my ($c, %a) = @_; bless {%a}, $c } sub inputs { $_[0]{in} } sub value { $_[0]{v} } }
package Chalk::IR::Node::Subscript { our @ISA = ('Chalk::IR::Node') }
package Chalk::IR::Node::Unwind { our @ISA = ('Chalk::IR::Node') }
class X {
    method _emit_expr($n, $d) { "e" . ($n // 'u') }
    method _field_sigil_for_expr($e) { $e =~ /h/ ? '%' : undef }
    method f($node, $declared_vars, @subscripts) {
        my $cur = $node;
        my $builtin_name;
        my $base_node;
        while (defined $cur && $cur isa Chalk::IR::Node) {
            if ($cur isa Chalk::IR::Node::Subscript) {
                $builtin_name = $cur->inputs()->[0]->value();
                my $args = $cur->inputs()->[1];
                $base_node = $args->[0] if $args->@* > 0;
                last;
            }
            if ($cur isa Chalk::IR::Node::Unwind) {
            }
        }
        my $base = $self->_emit_expr($base_node, $declared_vars);
        my $out = $base;
        if ($builtin_name eq 'exists') {
            my $expr = $base;
            for my $i (0 .. $#subscripts) {
                my ($idx_node, $sty) = $subscripts[$i]->@*;
                my $is_last = ($i == $#subscripts);
                my $field_sig = $self->_field_sigil_for_expr($expr);
                if ($sty eq 'array') {
                    my $av = (defined $field_sig && $field_sig eq '@')
                        ? "(HV*)$expr" : "(HV*)SvRV($expr)";
                    $out .= $av;
                    if ($is_last) { $out .= '!' }
                }
            }
        }
        return $out;
    }
}
my $sub = Chalk::IR::Node::Subscript->new(in => [Chalk::IR::Node->new(v => 'exists'), ['h']]);
print X->new->f($sub, {}, [1, 'array'], [2, 'hash'], [3, 'array']), "\n";
SRC

# A COUNT NOTHING READS is not bound: bound at the outer loop's exit, a dead
# `scalar(@flat)` named an array declared in the body (chalk's
# LLVM::Context::_reads_mutable_location).
round_trips(<<'SRC', 'a labelled last out of a nested loop over a body array');
package N { sub new { my ($c, @in) = @_; bless { in => [@in] }, $c } sub inputs { $_[0]{in} } }
package C { sub new { bless { memo => {} }, shift }
sub f { my ($self, $node) = @_; my $r = 0;
  $self->{memo}{"$node"} = 0;
  INPUT: for my $input ($node->inputs()->@*) {
    my @flat = (ref($input) eq 'ARRAY') ? $input->@* : ($input);
    for my $el (@flat) { next unless defined $el && ref $el; if ($self->f($el)) { $r = 1; last INPUT } }
  }
  return $self->{memo}{"$node"} = $r || 1 } }
print C->new->f(N->new(1, [2, 3])), C->new->f(N->new(1, [2, N->new])), "\n";
SRC

done_testing;
