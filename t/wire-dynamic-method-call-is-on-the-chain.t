# ABOUTME: A dynamic method call ($o->$m()) is a call: on the control chain, and the
# ABOUTME: memory version after it, in void context as in any other.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use lib 'lib';
use SoN::Verify;

# THE DEFECT (audit 2026-11-19, W3). Every other sub call is pinned and made
# the current memory where it stands; `$o->$m()` was pushed as a bare value.
# In void context nothing read it and it was gone -- `$o->$m(); print
# $o->{n}` printed 0 for perl's 1 -- and used for its value it ran at its
# first use, with the reads around it at the version before.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;

sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    return length $json ? JSON::PP->new->utf8->decode($json) : undef;
}

my $class = 'package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; return 5 } package main; my $o = C->new; my $m = "inc"; ';
my %shape = (
    'void'            => $class . '$o->$m(); print $o->{n}, "\n";',
    'for its value'   => $class . 'my $r = $o->$m(); print "$r $o->{n}\n";',
    'with arguments'  => $class . '$o->$m(1, 2); print $o->{n}, "\n";',
    'in an arm'       => $class . 'if (@ARGV) { $o->$m() } else { $o->$m(); $o->$m() } print $o->{n}, "\n";',
);

for my $name ( sort keys %shape ) {
    subtest $name => sub {
        my $w = wire( $shape{$name} ) or return fail 'no wire';
        my @nodes = $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
        my @dyn = grep { $_->{op} eq 'Call' && $_->{fields}{dispatch_kind} eq 'dynamic_method' } @nodes;
        ok scalar(@dyn), 'the call is in the graph' or return;
        is [ grep { !defined $_->{control_in} } @dyn ], [], 'every one has a control_in';
        is [ map { "$_->{rule} $_->{detail}" } grep { $_->{detail} =~ /dynamic_method/ }
             SoN::Verify::verify($w)->{violations}->@* ], [], 'the verifier sees none off the chain';
        # The read of $o->{n} after it names a version at or after the call.
        my ($read) = grep { $_->{op} eq 'Subscript' && @{ $_->{inputs} } == 3 } reverse @nodes;
        ok $read, 'the element is read at a memory version' or return;
        my %dyn = map { $_->{id} => 1 } @dyn;
        my %by  = map { $_->{id} => $_ } @nodes;
        my $v   = $by{ $read->{inputs}[2] };
        ok $dyn{ $v->{id} } || ( $v->{op} eq 'Phi' && $v->{fields}{memory} ),
            'and that version is the call (or the merge of the arms that made it)';
    };
}

subtest 'its context rides the call, as a method call\'s does' => sub {
    my $w = wire( $class . 'my @l = $o->$m(); $o->$m(); print scalar(@l), "\n";' ) or return fail 'no wire';
    my @dyn = grep { $_->{op} eq 'Call' && $_->{fields}{dispatch_kind} eq 'dynamic_method' }
        $w->{methods}{'main::__PROGRAM__'}{nodes}->@*;
    is [ sort map { $_->{fields}{want} // 'none' } @dyn ], [ 'list', 'void' ], 'want: list and void';
};

done_testing;
