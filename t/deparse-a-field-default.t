# ABOUTME: A class field's default survives the round trip -- an aggregate's list of
# ABOUTME: constants is emitted; a default the wire cannot carry refuses by name.

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
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh>;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    if (!$data || $err =~ /skipped/) {
        fail "$name: translates"; diag $err; return;
    }
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

# AN AGGREGATE FIELD'S LIST WAS DROPPED. `field %m = (a => 1)` compiles its
# default to a list, which the default extractor did not recognise, so the
# emission declared `field %m;` and every read found it empty.
round_trips(<<'SRC', 'a hash field with a list default');
use v5.42; use experimental 'class';
class K { field %m = (a => 1, b => 2); method all { join ",", map { "$_=$m{$_}" } sort keys %m } }
print K->new->all, "\n";
SRC

round_trips(<<'SRC', 'an array field with a list default');
use v5.42; use experimental 'class';
class K { field @l = (3, 4, 5); method n { scalar @l } method last_ { $l[-1] } }
my $o = K->new; print $o->n, $o->last_, "\n";
SRC

round_trips(<<'SRC', 'a scalar default, and a ref default that rendered as a list');
use v5.42; use experimental 'class';
class K { field $n = 3; field $r = [1, 2]; method all { $n . scalar(@$r) } }
print K->new->all, "\n";
SRC

# A REQUIRED :param HAS NO DEFAULT. Its initfield still has a child -- the
# lookup, with a `die` for a missing argument -- and reading any child as a
# default refused 11 of chalk's lib/ classes for a default they do not have.
round_trips(<<'SRC', 'a required :param, which has no default');
use v5.42; use experimental 'class';
class K { field $v :param; method v { $v } }
print K->new(v => 4)->v, "\n";
SRC

# `= undef` AND `= {}` / `= []` ARE CONSTANTS TOO: an undef op and an
# emptyavhv, one each in chalk's Scheduler and Target::Perl.
round_trips(<<'SRC', 'an undef default, with and without :param');
use v5.42; use experimental 'class';
class K { field $a :param = undef; field $b = undef; method all { (defined $a ? "d" : "u") . (defined $b ? "d" : "u") } }
print K->new->all, K->new(a => 1)->all, "\n";
SRC

round_trips(<<'SRC', 'an empty hash and array ref default');
use v5.42; use experimental 'class';
class K { field $h = {}; field $l = []; method add($k) { $h->{$k} = 1; push @$l, $k; return scalar(keys %$h) . scalar(@$l) } }
my $o = K->new; $o->add("a"); print $o->add("b"), K->new->add("c"), "\n";
SRC

# `= false` WAS DROPPED, and the :param became REQUIRED: the constant reader
# knew Int, Num and Str, returned no stamp for a boolean, and the caller
# skipped the field. chalk's Node::Return `synthetic`, Node::Call
# `paren_form` and four more -- "Required parameter is missing" in 69 of
# chalk's test files against the emitted lib/.
round_trips(<<'SRC', 'a boolean default on a :param field');
use v5.42; use experimental 'class';
class K { field $s :param :reader = false; field $t :param :reader = true; }
my $o = K->new; print $o->s ? "s" : "-", $o->t ? "t" : "-", K->new(s => 1)->s ? "S" : "-", "\n";
SRC

# A COMPUTED DEFAULT IS A GRAPH, run at each construction. It was refused
# as one the wire could not carry, which held chalk's four MOP classes
# (`field $graph :param :reader = Chalk::IR::Graph->new`) out of the round
# trip. Each object gets its own: two objects' defaults are two calls.
round_trips(<<'SRC', 'a computed default, run once per object');
use v5.42; use experimental 'class';
class K { field $t = time; method has { defined $t ? "y" : "n" } }
print K->new->has, "\n";
SRC

round_trips(<<'SRC', 'a :param default that constructs an object');
use v5.42; use experimental 'class';
my $made = 0;
package Box { sub new ($c) { $made++; bless { n => $made }, $c } sub n ($s) { $s->{n} } }
class K { field $b :param :reader = Box->new; }
my $x = K->new;
my $y = K->new;
my $z = K->new(b => bless { n => 9 }, 'Box');
print $x->b->n, $y->b->n, $z->b->n, " $made\n";
SRC

# A BARE FIELD HAS NO INITIALISER AT ALL, and reading one as an expression
# crashed the producer for every class beside it -- chalk's MOP::Class.
round_trips(<<'SRC', 'a computed default beside a bare field');
use v5.42; use experimental 'class';
class K { field @l; field $t = time; method has { push @l, 1; (defined $t ? "y" : "n") . scalar @l } }
print K->new->has, "\n";
SRC

# AN AGGREGATE'S COMPUTED DEFAULT IS ITS WHOLE LIST. Holding an anonymous
# hash it is computed, not constant, and the graph returned the top of the
# stack alone: `field %items = {7, "V"}`, an odd-sized hash and no key `r`.
round_trips(<<'SRC', 'a hash field whose list holds an anonymous hash');
use v5.42; use experimental 'class';
class K { field %items = (r => { 7 => "V" }, s => [1, 2]); method g { $items{r}{7} . scalar($items{s}->@*) . join(",", sort keys %items) } }
print K->new->g, "\n";
SRC
round_trips(<<'SRC', 'an array field whose list holds references');
use v5.42; use experimental 'class';
class K { field @l = ([1], { a => 2 }, 3); method g { scalar(@l) . $l[0][0] . $l[1]{a} . $l[2] } }
print K->new->g, "\n";
SRC

# A DEFAULT THAT READS AN EARLIER FIELD -- or any lexical -- reaches outside
# its own graph, which has no edge to it. Refused by name, not emitted
# reading an undeclared variable.
for my $case (
    [ 'an earlier field', <<'SRC', qr/GAP: the default of field `\$b` in class K/ ],
use v5.42; use experimental 'class';
class K { field $a = 1; field $b = $a + 1; method b { $b } }
print K->new->b, "\n";
SRC
    [ 'a file lexical', <<'SRC', qr/GAP: the default of field `\$b` in class K/ ],
use v5.42; use experimental 'class';
my $base = 5;
class K { field $b = $base * 2; method b { $b } }
print K->new->b, "\n";
SRC
) {
    my ($what, $src, $want) = @$case;
    my $data = graph_of($src);
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    ok !defined $out, "a default that reads $what refuses";
    like $d->gap // '', $want, '... naming the field and its class';
}

done_testing;
