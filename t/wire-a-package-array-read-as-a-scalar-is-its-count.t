# ABOUTME: A package array read as a scalar -- a condition, an operand -- is a Count of it at
# ABOUTME: a memory version, as a lexical array's is: a read each side of a store differs.

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
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

# `our @g = (1); print @g ? "t" : "f"; shift @g; print @g ? "t" : "f"` handed
# the ArrayLiteral itself to one TernaryExpr both prints shared: "tt" for
# perl's "tf". `my @a` in the same places was already a Count (the padav
# handler); the package spelling (rv2av over a gv) pushed the array.
for my $case (
    [ 'a ternary each side of a shift',
        q{our @g = (1); print @g ? "t" : "f"; shift @g; print @g ? "t" : "f", "\n";}, 2 ],
    [ 'an array never assigned, each side of a call that pushes',
        q{our @g; sub add { push @g, $_[0]; return } my $a = @g ? 1 : 0; add("k"); my $b = @g ? 1 : 0; print "$a $b\n";}, 2 ],
    [ 'if, unless, not and arithmetic',
        q{our @g = (4, 5); my $n = @g + 1; print "two\n" if @g == 2; pop @g; pop @g; print "empty\n" unless @g; print !@g ? "e" : "ne", " $n\n";}, 2 ],
    [ 'a while on a package array',
        q{our @g = (1, 2, 3); my $i = 0; while (@g) { shift @g; $i++ } print "$i\n";}, undef ],
    [ 'its last index and its elements are not its count',
        q{our @g = (7, 8, 9); my $n = @g; print "$#g $g[-1] $n ", scalar(@g), " @g[0, 1]\n";}, 1 ],
) {
    my ( $what, $src, $versions ) = $case->@*;
    subtest $what => sub {
        my $data  = graph_of($src) or return fail 'a wire';
        my @nodes = $data->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        my %by    = map { $_->{id} => $_ } @nodes;
        my @bare  = grep {
            my $user = $_;
            $user->{op} =~ /\A(?:If|TernaryExpr|Not|And|Or|Add|NumEq|Coerce)\z/ && grep {
                my $n = $by{ $_ // '' };
                $n && ( $n->{fields}{sigil} // '' ) eq '@' && $n->{op} =~ /\A(?:ArrayLiteral|EntryDef)\z/
            } $user->{inputs}->@*
        } @nodes;
        is [ map { "$_->{op}#$_->{id}" } @bare ], [], 'no array is handed to what wants a scalar';
        my @counts = grep { $_->{op} eq 'Count' } @nodes;
        ok scalar(@counts), 'the wire counts the array';
        is [ grep { !defined $_->{mem_in} } @counts ], [], q(every Count is of its array, at a memory version);
        if ( defined $versions ) {
            my %seen = map { $_->{mem_in} => 1 } @counts;
            is scalar( keys %seen ), $versions, "they read $versions memory versions";
        }
        my $d   = SoN::Deparse->new;
        my $out = $d->render($data);
        ok defined $out, 'the deparser renders it' or diag $d->gap;
        is run_perl( $out // '' ), run_perl($src), 'and it prints what perl prints';
    };
}

done_testing;
