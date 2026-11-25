# ABOUTME: A foreach/map/grep item read after a call that may store its list (audit 2, K3): a lexical
# ABOUTME: iterator over one array is aliased by reference; what no reference stands for is refused by name.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1);
}
# (DESIGN B: an array item of the list is its place, aliased per element,
# and the topic reads through its alias -- the topic and several-items
# refusals are deleted; a list a call returns as aliases (values, sort) is
# refused where the body may store it, by _refuse_aliased_call_list.)
my $call_list = qr/GAP: a foreach, map or grep over what a call returns as aliases/;
like compile( $_->[0] ), $_->[1], "refused: $_->[0]" for
    [ 'my @a=(3,1); sub z { $a[0]=7 } for my $x (sort @a) { z(); print $x } print "\n";', $call_list ],
    # (a code value the body calls may store anything -- but not a `my` array
    # of this sub that no reference or closure reaches: refused where one does)
    [ 'my @s=(1,2); my $c = sub { $s[0] = 9 }; my $t=""; for my $x (reverse @s) { $c->(); $t .= $x } print "$t\n";', $call_list ];
unlike compile($_), qr/GAP/, "lowered: $_" for
    # (the code values close over $v, not @subs: nothing they run can store it)
    'my $v=1; my @subs=(sub { $v+=1 }, sub { $v*=3 }); for my $s (@subs, reverse @subs) { $s->() } print "$v\n";',
    # (values %h: each value aliased by chalk -- HSliceAlias by its keys)
    'my %h=(a=>1); sub z { $h{a}=7 } for my $x (values %h) { z(); print $x } print "\n";',
    'my @a=(1,2); sub z { $a[1]=7 } print map { z(); $_ } @a; print "\n";',
    'my @a=(1,2); sub z { $a[1]=7 } my @g=grep { z(); $_ > 1 } @a; print "@g\n";',
    'my @a=(1,2); sub z { $a[0]=7 } for (@a) { z(); print } print "\n";',
    'my @a=(1,2); my @b=(3,4); sub z { $b[0]=7 } for my $x (@a,@b) { z(); print $x } print "\n";',
    'my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { z(); print $x } print "\n";',
    'my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { print $x; z() } print "\n";',
    'sub apply { my ($f,@l)=@_; map { $f->($_) } @l } my @r=apply(sub { $_[0]*2 }, 1,2); print "@r\n";',
    'my %h=(a=>1); sub z { $h{a}=7 } for my $v ($h{a}, 2) { z(); print $v } print "\n";';
done_testing;
