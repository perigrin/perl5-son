# ABOUTME: The wire carries per-sub METADATA, not just a node list.
# ABOUTME: params/uses_args come from the CV walk so consumers never scan the graph.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

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
        # goto &f hands the CALLER'S @_ to the target and names `_` NOWHERE in
        # the optree. A false negative here means @_ is not materialised for a
        # sub that passes it onward.
        'sub other { 1 } sub f { goto &other }' => 1,
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

# Arity is metadata too. The backend's current arity check COUNTS positional
# reads in the callee graph; that is the scan this record exists to retire.
subtest 'declared arity is recorded' => sub {
    my $wire = wire_for('sub f { my ($a,$b) = @_; $a+$b } print f(1,2), "\n";', 'arity');
    my $rec  = sub_record($wire, 'main', 'f');
    ok defined $rec, 'record exists' or return;
    # NOT `exists` -- that passes for any value, including junk, and this
    # subtest would then be a green light over an untested path. Pin the
    # documented contract: a signature-less sub declares NO params.
    is_deeply $rec->{params}, [],
        'a signature-less sub declares no params';
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
    # PRE-EXISTING, not introduced here: _extract_class classifies EVERY CV in a
    # feature-class package as a method, so a plain `sub helper` inside a class
    # lands in {methods} too and is correctly skipped by the same guard. That
    # conflation is upstream of this record -- pinned here as the observed
    # behaviour so a later fix to the classifier shows up as this test changing,
    # rather than being asserted as if it were already correct.
    ok exists( ( $w->{methods} // {} )->{helper} ),
        'a plain sub in a class is (currently) classified as a method';
    ok !exists( ( $w->{subs} // {} )->{helper} ),
        'and so is not double-listed under subs';
};

done_testing;
