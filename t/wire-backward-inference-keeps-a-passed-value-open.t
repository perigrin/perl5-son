# ABOUTME: a read whose raw value a consumer takes as it is (defined, a call's
# ABOUTME: argument, a return) is not typed by its other uses: it may be undef.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $dir = tempdir(CLEANUP => 1);

sub nodes_of ($src, $graph) {
    my $file = "$dir/g" . int(rand 1e9) . ".pl";
    open my $fh, '>', $file or die $!; print {$fh} $src; close $fh;
    my $json = qx{$^X -Ilib -MO=-q,SoN,json,not_package=SoN $file 2>/dev/null};
    my $w = eval { JSON::PP->new->decode($json) } or return [];
    return $w->{methods}{$graph}{nodes} // [];
}

sub stamps_of_v ($src) {
    return join ',', sort map { $_->{stamp} // '' }
        grep { $_->{op} eq 'PadAccess' && ( $_->{fields}{symbol} // '' ) eq 'v' } nodes_of($src, 'main::f')->@*;
}

# `$v =~ /x/` typed $v Str; the same read was g's argument, and the undef the
# caller passed reached g as "" -- defined (chalk printed "-d" for perl's
# "-u"). `defined $v` beside `$v =~` typed it Str too, and a Str is always
# defined.
for my $src (
    q{sub f { my ($v) = @_; return ($v =~ /x/ ? "x" : "-") . (defined(g($v)) ? "d" : "u") } sub g { return $_[0] } print f(undef), "\n";},
    q{sub f { my ($v) = @_; if (defined $v && $v =~ /^a/) { return 1 } return 0 } print f(undef), "\n";},
    q{sub f { my ($v) = @_; my $n = $v + 1; return $v } print defined(f(undef)) ? 1 : 0, "\n";},
) {
    unlike stamps_of_v($src), qr/\b(?:Str|Num|Int)\b/, "a read handed on as it is stays open: $src";
}

# A read every use of which requires a reading is still typed by them.
like stamps_of_v(q{sub f { my ($v) = @_; return $v + 1 } print f(2), "\n";}), qr/\bNum\b/,
    'a read only added to is Num';

done_testing;
