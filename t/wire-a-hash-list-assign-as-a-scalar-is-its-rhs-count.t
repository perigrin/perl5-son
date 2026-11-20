# ABOUTME: A list assignment to a hash, read as a scalar, is the count of its RIGHT side:
# ABOUTME: a Count of the list assigned, never the hash itself handed to a scalar reader.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

# THE DEFECT (docs/memory/chalk-takes-the-class-read-wire.md). perl's value of
# a list assignment in scalar context is the number of elements on its right:
# `(%h = (a => 1, a => 2))` is 4, though the hash then holds one key. The wire
# handed the HashLiteral itself to the If, the Not, the TernaryExpr or the
# Coerce -- a reader could only take the hash's truth or its key count, and
# chalk refused the shape (WireCheck's _hash_assigns_read_as_scalars) after
# `our %g; sub f { () } (%g = f()) ? "t" : "f"` printed `t`.
#
# THE SAME COUNT SERVES `() = LIST`, which had two wrong answers of its own:
# a reference in the list was counted as its referent's length, and a hash as
# its keys (it flattens to twice that).

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub run_perl ($src) {
    my $f = "$dir/r" . ++$n . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    return scalar qx(/usr/bin/timeout 10 $^X $f 2>/dev/null);
}

sub graph_of ($src) {
    my $f = "$dir/g" . ++$n . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return eval { JSON::PP->new->decode($j) };
}

# A hash (its literal, its package entry, its pad slot) in a slot that wants
# ONE value: the shapes chalk's rule refused.
sub hashes_read_as_scalars (@nodes) {
    my %by = map { $_->{id} => $_ } @nodes;
    my %scalar_slot = ( If => 1, TernaryExpr => 0, Not => 0, Coerce => 0, VarDecl => 1 );
    my @bad;
    for my $user (@nodes) {
        my ( $op, $in ) = ( $user->{op}, $user->{inputs} // [] );
        for my $slot ( 0 .. $#$in ) {
            my $v = $by{ $in->[$slot] // '' } // next;
            next unless ( $v->{fields}{sigil} // '' ) eq '%' && $v->{op} =~ /\A(?:PadAccess|HashLiteral|EntryDef)\z/;
            # (a VarDecl of the hash itself declares it; one of a scalar reads it)
            next if $op eq 'VarDecl' && ( $by{ $in->[0] }{fields}{sigil} // '' ) eq '%';
            push @bad, "$op#$user->{id} reads $v->{op}#$v->{id}"
                if $op =~ /\A(?:Concat|Add|Subtract|Multiply|And|Or|Xor|DefinedOr|NumEq|NumGt|NumLt)\z/
                || exists $scalar_slot{$op} && $scalar_slot{$op} == $slot;
        }
    }
    return @bad;
}

for my $case (
    [ 'a package hash from a call that returns nothing, as a condition',
        q{our %g; sub f { () } print((%g = f()) ? "t" : "f"); print "\n";} ],
    [ 'the same from a call that returns pairs',
        q{our %g; sub f { (a => 1, b => 2) } print((%g = f()) ? "t" : "f"); print " ", join(",", sort keys %g), "\n";} ],
    [ 'if (my %h = f())',
        q{sub f { @_ } if (my %h = f()) { print "y\n" } else { print "n\n" } if (my %i = f(a => 1)) { print "y $i{a}\n" } else { print "n\n" }} ],
    [ 'my $n = (%h = f())',
        q{sub f { (a => 1, a => 2) } my %h; my $n = (%h = f()); print "$n ", scalar(keys %h), "\n";} ],
    [ 'a duplicate key: the count is of the list, not of the hash',
        q{my $n = (my %h = (a => 1, a => 2)); print "$n ", scalar(keys %h), "\n";} ],
    [ 'a hash copied from a hash counts both keys and values',
        q{my %g = (a => 1, b => 2, c => 3); my %h; my $n = (%h = %g); print "$n\n";} ],
    [ 'an array and pairs',
        q{my @p = (1, 2); my %h; my $n = (%h = (@p, c => 3)); print "$n $h{1} $h{c}\n";} ],
    [ 'a hash assigned from itself and more: counted before the store',
        q{our %g = (a => 1); my $n = (%g = (%g, b => 2)); print "$n ", join(",", sort keys %g), "\n";} ],
    [ 'not',
        q{sub f { @_ } my %h; print !(%h = f()) ? "empty" : "full", " ", !(%h = f(1, 2)) ? "empty" : "full", "\n";} ],
    [ 'a ternary of lists',
        q{my $c = @ARGV; my %h; my $n = (%h = ($c ? (1, 2) : ())); print "$n\n";} ],
    [ 'while (my %i = f())',
        q{my @q = ([a => 1], [b => 2, c => 3], []); sub f { @{ shift @q } } my $t = 0; while (my %i = f()) { $t += keys %i } print "$t\n";} ],
) {
    my ( $what, $src ) = $case->@*;
    subtest $what => sub {
        my $data = graph_of($src) or return fail 'a wire';
        ok $data->{methods}{'main::__PROGRAM__'}, 'the program has a graph' or return;
        my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        is [ hashes_read_as_scalars(@nodes) ], [], 'no hash is handed to what wants a scalar';
        my $d   = SoN::Deparse->new;
        my $out = $d->render($data);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

subtest 'the Count is of the right side, at the version before the store' => sub {
    my $data  = graph_of(q{our %g; sub f { () } print((%g = f()) ? "t" : "f"); print "\n";});
    my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    my %by    = map { $_->{id} => $_ } @nodes;
    my ($tern)  = grep { $_->{op} eq 'TernaryExpr' } @nodes;
    my $cond    = $by{ $tern->{inputs}[0] };
    is $cond->{op}, 'Count', 'the condition is a Count';
    my $list = $by{ $cond->{inputs}[0] };
    is $list->{op}, 'ArrayLiteral', '... of a list';
    ok !defined $list->{fields}{symbol}, '... that is no variable';
    is $by{ $list->{inputs}[0] }{op}, 'Call', '... holding the call';
    my ($store) = grep { $_->{op} eq 'EntryWrite' } @nodes;
    isnt $cond->{inputs}[1], $store->{id}, 'it does not read the memory after the store';
};

# `() = LIST` counts the same way.
for my $case (
    [ 'a reference in the list is one element', q{my $r = [1, 2, 3]; my $n = () = ($r, $r); print "$n $r->[2]\n";} ],
    [ 'a hash in the list is its keys and its values', q{my %h = (a => 1, b => 2); my $n = () = %h; print "$n\n";} ],
    [ 'a hash, an array and a scalar', q{my %h = (a => 1, b => 2); my @a = (1, 2, 3); my $n = () = (%h, @a, 5); print "$n\n";} ],
    [ 'a call', q{sub g { (1, 2, 3) } my $n = () = g(); print "$n\n";} ],
) {
    my ( $what, $src ) = $case->@*;
    subtest "() = LIST: $what" => sub {
        my $data = graph_of($src) or return fail 'a wire';
        my $d    = SoN::Deparse->new;
        my $out  = $d->render($data);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

done_testing;
