# ABOUTME: A sub argument or invocant perl aliases is passed as a place (fields.place, no mem_in) where
# ABOUTME: the callee may see its source written by name; a value only where B::SoN proves it private.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir(CLEANUP => 1);

# wire($src) -> (decoded wire, stderr)
sub wire ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $err = do { local ( @ARGV, $/ ) = "$dir/err"; <> } // '';
    return ( ( $json =~ /\S/ ? decode_json($json) : undef ), $err );
}

# args($wire, $callname) -> the program's Call to $callname: its input nodes
sub args ($w, $name) {
    return () unless $w;
    my @n = ( $w->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    my %by = map { $_->{id} => $_ } @n;
    my ($c) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) =~ /(?:\A|::)\Q$name\E\z/ } @n;
    return $c ? map { $by{$_} } $c->{inputs}->@* : ();
}
sub is_place ($n = undef) { $n && $n->{fields} && $n->{fields}{place} && !exists $n->{mem_in} ? 1 : 0 }

# any_place($wire) -> a sub Call of any graph on the wire passes a place
sub any_place ($w) {
    return 0 unless $w;
    for my $g ( values $w->{methods}->%* ) {
        my @n = ( $g->{nodes} // [] )->@*;
        my %by = map { $_->{id} => $_ } @n;
        return 1 if grep { is_place( $by{$_} ) } map { $_->{inputs}->@* } grep { $_->{op} eq 'Call' && ( $_->{fields}{dispatch_kind} // '' ) ne 'builtin' } @n;
    }
    return 0;
}

# NOT PRIVATE: the callee stores the source by name, then reads @_ (class C);
# a method stores $_[0], the caller's invocant (class H); a sub stores through
# $_[N] (a written alias is a place). Each was a GAP by name, or (the last)
# a value chalk wrote back through.
for my $src (
    'my $x=1; sub f { $x=2; $_[0] } print f($x), "\n";',
    'our $x=1; sub f { $x=2; $_[0] } print f($x), "\n";',
    'my $x=1; sub f { $x++; $_[0]+0 } print f($x),"\n";',
    'our $x=1; sub f { my $o=$_[0]; $x=2; "$o$_[0]" } print f($x),"\n";',
    'our @a=(1); sub f { $a[0]=2; $_[0] } print f($a[0]),"\n";',
    'my %h=(k=>1); sub f { $h{k}=2; $_[0] } print f($h{k}),"\n";',
    'our $x=1; sub g { $x=2 } sub f { g(); $_[0] } print f($x),"\n";',
    'our $x=1; sub f { $x=2; my ($v)=@_; $v } print f($x),"\n";',
    'our $x=1; sub f { $x=2; shift } print f($x),"\n";',
    'my $x=1; my $f=sub { $x=2; $_[0] }; print $f->($x),"\n";',
    'package C; our $x=1; sub m1 { $x=2; $_[1] } package main; print C->m1($C::x),"\n";',
    'my $o={n=>1}; sub f { $o->{n}=2; $_[0] } print f($o->{n}),"\n";',
    'my @a=(1); sub f { $a[0]=2; $_[0] } print f($a[0]),"\n";',
    'package C; sub new { bless {}, shift } sub repl { $_[0] = "gone" } package main; my $o=C->new; $o->repl; print ref($o) ? "obj" : $o, "\n";',
    'package C; sub new { bless {}, shift } sub nul { $_[0] = undef } package main; my $o=C->new; $o->nul; print defined $o ? "d" : "u", "\n";',
    'my $x=1; sub inc { $_[0]++ } inc($x); print "$x\n";',
    'my @a=(1); sub inc { $_[0]++ } inc($a[0]); print "@a\n";',
    # (a call nothing here sees into, before the read, on a captured variable)
    'sub k { $_[1]->(); $_[0] } sub w { my $v=1; my $s=sub { $v=9 }; k($v,$s) } print w(),"\n";',
) {
    my ( $w, $err ) = wire($src);
    unlike $err, qr/GAP:/, "not refused: $src";
    ok any_place($w), "an argument is a place: $src";
}

# PRIVATE: nothing the callee runs writes the source before it reads @_, and
# it stores through no argument -- the fast path, a value.
for my $src (
    'our $x=1; sub f { $x=2 } f($x); print "$x\n";',
    'my $x=1; sub f { $_[0] + 1 } print f($x), "\n";',
    'my $x=1; my $y=5; sub f { $y=2; $_[0] } print f($x), "\n";',
    'my @a=(1,2); sub f { $a[1]=9; $_[0] } print f($a[0]), "\n";',
    'our $x=1; sub f { my ($v)=@_; $x=2; $v } print f($x),"\n";',
    'our $x=1; sub f { local $x=2; $_[0] } print f($x),"\n";',
    'my @a=(1); sub f { push @a,2; $_[0] } print f($a[0]),"\n";',
    'our $x=1; sub f { $x=2; my $s=0; $s+=$_ for @_; $s } print f($x,$x),"\n";',
    # (an unknown call cannot name a `my` nothing captures or references)
    'my $x=1; sub k { $_[1]->(); $_[0] } print k($x, sub { 1 }),"\n";',
    'package C; sub new { bless {}, shift } sub m { $_[0]{k} = 1; 1 } package main; my $o=C->new; $o->m; print $o->{k}, "\n";',
    'package C; sub new { bless {}, shift } sub m { my $s = shift; $s = 5; 1 } package main; my $o=C->new; $o->m; print ref $o, "\n";',
) {
    my ( $w, $err ) = wire($src);
    unlike $err, qr/GAP:/, "not refused: $src";
    ok !any_place($w), "every argument is a value: $src";
}

done_testing;
