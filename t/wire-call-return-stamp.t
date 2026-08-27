# ABOUTME: A Call to a statically-resolved callee is stamped with the callee's return type.
# ABOUTME: The producer already computes return_type; this asserts the callsite reads it.
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
    my $filter = $opt{filter} // ',package=main';
    my $json = qx{$PERL -Ilib -MO=SoN,json$filter $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

# Every Call node in $graph whose callee name is $name.
sub calls_named ($wire, $graph, $name) {
    my $g = $wire->{methods}{$graph} or return ();
    return grep { $_->{op} eq 'Call' && ($_->{fields}{name} // '') eq $name }
           ($g->{nodes} // [])->@*;
}

# THE DEFECT. `return_type` is computed by _graph_return_type, serialized onto
# the sub's metadata record, and was never read back at the callsite -- so a
# call to a sub the producer had already typed arrived stamped `Unknown`.
# The answer was on the wire, in the same document, on a different record.
subtest 'a direct sub call takes the callee return type' => sub {
    my $wire = wire_for('sub add1 { my $n = 5; return $n + 1 } my $x = add1(); say($x);',
                        'direct');
    is $wire->{classes}{main}{subs}{add1}{return_type}, 'Int',
        'the callee return_type is Int on the sub record';
    my ($call) = calls_named($wire, 'main::__PROGRAM__', 'main::add1');
    ok defined $call, 'the callsite Call node exists' or return;
    is $call->{stamp}, 'Int', 'the Call node carries the callee return type';
};

# A method call resolves through method_return_types, the class-section
# equivalent of the sub record's return_type.
subtest 'a method call takes the method return type' => sub {
    my $src = <<'SRC';
use feature 'class';
no warnings 'experimental::class';
class Counter { field $n = 0; method val { return $n } }
my $c = Counter->new; my $v = $c->val; say($v);
SRC
    my $wire = wire_for($src, 'method', filter => '');
    is $wire->{classes}{Counter}{method_return_types}{val}, 'Int',
        'the method return type is recorded on the class section';
    my ($call) = calls_named($wire, 'main::__PROGRAM__', 'val');
    ok defined $call, 'the method callsite exists' or return;
    is $call->{stamp}, 'Int', 'the method Call node carries the return type';
};

# THE OTHER DIRECTION. A callee whose own return is genuinely undetermined must
# still arrive Unknown -- the fix must propagate the answer, not invent one.
# Without this, stamping every Call `Int` would pass the tests above.
subtest 'an undetermined callee still yields Unknown' => sub {
    my $wire = wire_for('sub r { my $n = shift; return $n } my $x = r(); say($x);',
                        'undetermined');
    my ($call) = calls_named($wire, 'main::__PROGRAM__', 'main::r');
    ok defined $call, 'the callsite exists' or return;
    is $call->{stamp}, 'Unknown',
        'a callee with no determined return type leaves the call Unknown';
};

# A recursive call has no completed callee stamp to read at its own build time.
# It must not crash and must not claim a type it cannot support.
subtest 'a recursive call does not fabricate a type' => sub {
    my $wire = wire_for('sub fact { my $n = shift; return $n } my $x = fact(); say($x);',
                        'recursive');
    my ($call) = calls_named($wire, 'main::__PROGRAM__', 'main::fact');
    ok defined $call, 'the callsite exists' or return;
    ok defined $call->{stamp}, 'the call still carries a stamp, never an absence';
};

done_testing;
