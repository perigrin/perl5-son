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
my $topic = qr/GAP: a foreach, map or grep's \$_ \(or a package iterator\) read after a call that may store its list/;
my $list  = qr/GAP: a foreach over a list of several items, or one a call returns, whose aggregate a call in its body may store/;
like compile( $_->[0] ), $_->[1], "refused: $_->[0]" for
    [ 'my @a=(1,2); sub z { $a[1]=7 } print map { z(); $_ } @a; print "\n";', $topic ],
    [ 'my @a=(1,2); sub z { $a[1]=7 } my @g=grep { z(); $_ > 1 } @a; print "@g\n";', $topic ],
    [ 'my @a=(1,2); sub z { $a[0]=7 } for (@a) { z(); print } print "\n";', $topic ],
    [ 'my @a=(1,2); my @b=(3,4); sub z { $b[0]=7 } for my $x (@a,@b) { z(); print $x } print "\n";', $list ],
    [ 'my %h=(a=>1); sub z { $h{a}=7 } for my $x (values %h) { z(); print $x } print "\n";', $list ],
    [ 'my @a=(3,1); sub z { $a[0]=7 } for my $x (sort @a) { z(); print $x } print "\n";', $list ];
unlike compile($_), qr/GAP/, "lowered: $_" for
    'my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { z(); print $x } print "\n";',
    'my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { print $x; z() } print "\n";',
    'sub apply { my ($f,@l)=@_; map { $f->($_) } @l } my @r=apply(sub { $_[0]*2 }, 1,2); print "@r\n";',
    'my $v=1; my @subs=(sub { $v+=1 }, sub { $v*=3 }); for my $s (@subs, reverse @subs) { $s->() } print "$v\n";';
done_testing;
