# ABOUTME: A followed module's package variables, as its file-level code left them at `use` time, are put on
# ABOUTME: the wire as a BEGIN block after the program's own; what a literal cannot say (an object) is refused.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# THE DEFECT (second final audit, class K9): `use ZUp; print "$ZUp::n"` --
# the module says `our $n = 1` -- printed an empty line. perl runs a used
# module's file at compile time and frees its code; the wire held the
# module's subs and nothing of the state its file left.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ( $src, $err = '2>&1' ) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o "use lib 't/lib'; $src";
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f $err);
}
sub begin_writes ($json) {
    my $w = JSON::PP->new->decode($json);
    my @b = grep { $_->{phase} eq 'BEGIN' } ( $w->{phase_blocks} // [] )->@*;
    return [] unless @b;
    my @n = $b[-1]{nodes}->@*;    # (after the program's own)
    my %by = map { $_->{id} => $_ } @n;
    return [ sort map {
        my ( $t, $v ) = map { $by{$_} } $_->{inputs}->@[ 0, 1 ];
        "$t->{fields}{package}::$t->{fields}{symbol}=" . ( $v->{fields}{value} // 'undef' )
    } grep { $_->{op} eq 'EntryWrite' && ( $by{ $_->{inputs}[0] }{fields}{package} // '' ) eq 'K9::Mod' } @n ];
}

{   my $json = compile( 'use K9::Mod; print "$K9::Mod::n $K9::Mod::s\n";', '2>/dev/null' );
    is begin_writes($json), [ 'K9::Mod::n=1', 'K9::Mod::s=a"b' ], 'the scalars the program reads, after its BEGIN blocks';
}
{   my $json = compile( 'use K9::Mod; K9::Mod::bump(); print K9::Mod::get(), "\n";', '2>/dev/null' );
    is begin_writes($json), ['K9::Mod::n=1'], 'a scalar only a sub of the module reads';
}
unlike compile('use K9::Mod; print "@K9::Mod::l $K9::Mod::r->[0] @{ $K9::Mod::h{k} }\n";'), qr/GAP/, 'arrays, hashes and references of plain values: lowered';
like compile('use K9::Mod; print ref($K9::Mod::o), "\n";'), qr/GAP: a followed module's package variable its file-level code set \(\$K9::Mod::o\)/, 'an object: refused';
{   my $json = compile( 'use K9::Mod; BEGIN { $K9::Mod::n = 5 } print "$K9::Mod::n\n";', '2>/dev/null' );
    is begin_writes($json), ['K9::Mod::n=5'], 'a BEGIN block that writes it: the state after it, after it';
}
like compile('use K9::Mod; BEGIN { $main::c = $K9::Mod::n } print "$main::c\n";'), qr/GAP: a followed module's package variable .* read by a BEGIN block of the program/, 'a BEGIN block that reads it: refused';
unlike compile('use K9::Mod; print defined $K9::Mod::u ? "d" : "u", "\n";'), qr/GAP/, 'an undef one: nothing to say';
done_testing;
