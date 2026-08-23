# ABOUTME: The wire carries per-sub METADATA, not just a node list.
# ABOUTME: params/uses_args come from the CV walk so consumers never scan the graph.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;
use B;
use B::SoN;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

# Fixtures for the optree-scan subtest below, which calls _cv_uses_args
# directly rather than going through the wire.
sub goto_target { 1 }
sub goto_fwd    { goto &goto_target }
sub no_args     { my $z = 5; $z + 1 }

# Compile $src through B::SoN and return the decoded wire structure.
sub wire_for ($src, $name, %opt) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    # package=main keeps the emitted set small, but it also EXCLUDES any other
    # package -- so a test about a non-main class must drop the filter or it
    # asserts against a section the filter removed, not against the feature.
    my $filter = $opt{no_filter} ? '' : ',package=main';
    my $json = qx{$PERL -Ilib -MO=SoN,json$filter $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

# The `subs` record hangs off the owning class. Every sub has one -- a
# file-level sub belongs to class `main`, because all code belongs to a class.
sub sub_record ($wire, $class, $name) {
    my $cls = $wire->{classes}{$class} or return undef;
    return ($cls->{subs} // {})->{$name};
}

subtest 'a file-level sub is recorded under class main' => sub {
    my $wire = wire_for('sub f { 42 } print f(), "\n";', 'plain');
    ok exists $wire->{classes}, 'the wire carries a classes section';
    my $rec = sub_record($wire, 'main', 'f');
    ok defined $rec, 'sub f is recorded under main'
        or diag explain $wire->{classes};
};

# uses_args is the CALLEE property the calling convention keys on: materialise
# @_ only when the body actually touches it. Recorded by the CV walk, which
# knows -- NOT recovered by scanning the graph, which cannot be done reliably
# (@_ has three IR spellings and vanishes entirely for `my ($a,$b) = @_`).
subtest 'uses_args is recorded per callee' => sub {
    my %want = (
        'sub f { 42 }'                      => 0,   # no @_ at all
        'sub f { my $z = 5; $z + 1 }'       => 0,   # own lexical only
        'sub f { my $n = shift; $n+1 }'     => 1,   # shift @_
        'sub f { $_[0] + 1 }'               => 1,   # positional subscript
        'sub f { my ($a,$b) = @_; $a+$b }'  => 1,   # list-assign (vanishes in IR!)
        'sub f { scalar @_ }'               => 1,   # reflective
        'sub f { my @c = @_; scalar @c }'   => 1,   # @_ copied as a list
        'sub f { $#_ }'                     => 1,   # last index of @_
        # THE BILATERAL CASE, and the one that caught a real false positive:
        # `$_` and `@_` are DIFFERENT variables sharing the glob name `_`.
        # Matching the name alone reported this sub as using @_, which would
        # materialise an argument array for a sub that never asked for one.
        # The sigil lives on the OP KIND -- gvsv is scalar $_, not @_.
        'sub f { $_ = "x"; /x/ ? 1 : 0 }'   => 0,   # $_ is NOT @_
        'sub f { $_ }'                      => 0,   # a bare $_ read
        # The `goto &other` case moved to its own subtest below -- a sub
        # containing goto no longer TRANSLATES, so it emits no wire record to
        # assert against. See there for why that is the right level.
    );
    my $i = 0;
    for my $body (sort keys %want) {
        $i++;
        my $wire = wire_for("$body\nprint 1;", "ua$i");
        my $rec  = sub_record($wire, 'main', 'f');
        ok defined $rec, "record exists for: $body" or next;
        is !!$rec->{uses_args}, !!$want{$body},
            sprintf('uses_args=%d for: %s', $want{$body}, $body);
    }
};

subtest 'goto-forwarded @_ is detected at the optree scan' => sub {
    # `goto &other` hands the CALLER'S @_ to the target and names `_` NOWHERE
    # in the optree. A false negative means @_ is not materialised for a sub
    # that passes it onward -- the reason this case exists.
    #
    # It is asserted against _cv_uses_args directly rather than against the
    # wire, because a sub containing `goto` is now REFUSED by the translator
    # (%UNBUILT_OP_GAP) and so emits no sub record at all. Asserting a record
    # existed would require goto to keep silently dropping, trading a loud
    # refusal for a miscompile to keep a metadata row about a sub the compiler
    # then skips.
    #
    # The detection itself is untouched by that refusal: _cv_uses_args is an
    # optree walk in B/SoN.pm, independent of graph translation. This subtest
    # pins exactly that independence.
    my $cv = B::svref_2object(\&goto_fwd);
    ok !!B::SoN::_cv_uses_args($cv),
        'goto &other forwards @_ and is detected as using it';

    ok !B::SoN::_cv_uses_args(B::svref_2object(\&no_args)),
        'and the negative direction still holds (bilateral)';
};

# Arity is metadata too. The backend's current arity check COUNTS positional
# reads in the callee graph; that is the scan this record exists to retire.
subtest 'declared arity is recorded' => sub {
    my $wire = wire_for('sub f { my ($a,$b) = @_; $a+$b } print f(1,2), "\n";', 'arity');
    my $rec  = sub_record($wire, 'main', 'f');
    ok defined $rec, 'record exists' or return;
    # NOT `exists` -- that passes for any value, including junk, and this
    # subtest would then be a green light over an untested path.
    #
    # THE CONTRACT CHANGED, deliberately: EVERY SUB HAS A SIGNATURE, and
    # `sub f {}` is exactly `sub f(@_)` -- one implicit slurpy parameter. This
    # previously read `[]`, which conflated signature-less (the most PERMISSIVE
    # declaration) with `sub f()` (the most RESTRICTIVE -- arity zero, enforced
    # by perl: "Too many arguments for subroutine 'main::empty'"). Those are
    # opposite meanings and must not share a representation.
    # See docs/plans/2026-08-22-parameter-node-design.md in chalk.
    is_deeply $rec->{params}, ['@_'],
        'a signature-less sub is implicitly (@_)';
    is $rec->{signature}{kind}, 'implicit',
        'and the signature says so, distinct from a declared one';
    is $rec->{signature}{slurpy}, '@',
        'slurpy array';
};

# A sub in a real class keeps working -- the subs record must not disturb the
# existing methods/fields replay.
subtest 'a class still carries its methods' => sub {
    my $wire = wire_for(<<'PERL', 'cls', no_filter => 1);
package Counter { sub bump { 1 } }
print Counter::bump(), "\n";
PERL
    my $rec = sub_record($wire, 'Counter', 'bump');
    ok defined $rec, 'a package sub is recorded under its own class'
        or diag explain $wire->{classes};
};

# THE UNFILTERED PATH, which every other subtest here hides. `package=main`
# filters away exactly the two things most worth testing, so these run without
# it -- both defects below shipped green under the filter.
subtest 'no ambient module leaks in as a class' => sub {
    my $wire = wire_for(<<'PERL', 'leak', no_filter => 1);
sub f { 42 }
print f(), "\n";
PERL
    my @names = sort keys $wire->{classes}->%*;
    my @leaked = grep { /^(?:strict|warnings|utf8|B|Carp|Exporter|JSON|Scalar|List)\b/ } @names;
    is_deeply \@leaked, [],
        'a package we merely LOADED is not recorded as a class'
        or diag "leaked: @leaked";
    ok exists $wire->{classes}{main}, 'the compiled file still gets its class';
};

# A method and a sub are different callables: different dispatch, and one
# carries an implicit invocant. Recording a method under BOTH keys hands the
# loader one callable with two contradictory descriptions.
subtest 'a method is not also recorded as a sub' => sub {
    my $wire = wire_for(<<'PERL', 'dual', no_filter => 1);
use feature 'class';
no warnings 'experimental::class';
class Widget { field $n :param = 0; method get { $n } sub helper { 7 } }
print Widget->new(n => 1)->get, "\n";
PERL
    my $w = $wire->{classes}{Widget} or do {
        fail 'Widget class recorded'; return;
    };
    ok exists( ( $w->{methods} // {} )->{get} ), 'get is a method';
    ok !exists( ( $w->{subs} // {} )->{get} ),
        'get is NOT also listed as a sub';
    # FIXED IN 1b (this test previously pinned the opposite as observed-not-
    # endorsed): _extract_class used to put EVERY non-:reader CV into {methods}
    # regardless of the flag it had already computed, so a plain `sub helper`
    # inside a class block was reported as a method. It now honours
    # CvFLAGS & CVf_METHOD, which is the same distinction the loader needs to
    # choose MOP::Method vs MOP::Sub -- a method carries an implicit invocant
    # and a sub does not.
    ok exists( ( $w->{subs} // {} )->{helper} ),
        'a plain sub in a class is recorded as a SUB';
    ok !exists( ( $w->{methods} // {} )->{helper} ),
        'and not as a method';
};

# A `:reader` accessor is SYNTHESIZED by the backend from the field attribute.
# Its CV is still in the stash, so it must not ALSO be recorded as a sub --
# that would declare the accessor twice, the second shadowing the first.
# Measured before the guard: subs came back [util, x].
subtest 'a :reader accessor is not recorded as a sub' => sub {
    my $wire = wire_for(<<'PERL', 'rdr', no_filter => 1);
use feature 'class';
no warnings 'experimental::class';
class Pt { field $x :param :reader = 0; method dbl { $x * 2 } sub util { 9 } }
my $p = Pt->new(x => 3);
print $p->x + $p->dbl, "\n";
PERL
    my $c = $wire->{classes}{Pt} or do { fail 'Pt recorded'; return };
    my ($f) = grep { ( $_->{name} // '' ) eq '$x' } ( $c->{fields} // [] )->@*;
    ok $f && $f->{is_reader}, 'the field is tagged :reader';
    ok !exists( ( $c->{subs} // {} )->{x} ),
        'the synthesized accessor is NOT also a sub';
    ok exists( ( $c->{subs} // {} )->{util} ),
        'a genuine sub alongside it still is';
};

# THE REFERENCED-CLASS PATH, which neither the other subtests here nor the
# chalk corpus gate exercise: the gate puts EVERY class in its package= filter,
# so _emit_referenced_classes is never taken there. A class reached only by
# being CALLED (out of filter) is translated by that path alone -- and it used
# to reach a plain sub only because every CV was recorded under {methods}.
# Measured before the fix: MyMod::helper vanished from the graph set while
# main's Call node still named it. An unresolvable callee, no GAP, no warning.
subtest 'a referenced out-of-filter class keeps its subs' => sub {
    my $moddir = "$dir/lib";
    mkdir $moddir unless -d $moddir;
    open my $mf, '>', "$moddir/MyMod.pm" or die $!;
    print {$mf} <<'PERL';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class MyMod { field $n :param = 0; method get { $n } sub helper { 7 } }
1;
PERL
    close $mf;

    my $file = "$dir/refcls.pl";
    open my $fh, '>', $file or die $!;
    print {$fh} "use 5.42.0;\nuse lib '$moddir';\nuse MyMod;\n"
        . "print MyMod->new(n=>1)->get + MyMod::helper(), \"\\n\";\n";
    close $fh;

    # The DEFAULT filter -- this is the shape that breaks.
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/refcls.err};
    die 'no JSON' unless length $json;
    my $wire = JSON::PP->new->decode($json);

    ok exists $wire->{methods}{'MyMod::get'},
        'the referenced class method is translated';
    ok exists $wire->{methods}{'MyMod::helper'},
        'and its plain SUB still has a graph'
        or diag 'graphs: ' . join ',', sort keys $wire->{methods}->%*;
};

done_testing;
