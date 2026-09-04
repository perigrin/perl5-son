# ABOUTME: A builtin whose result type perl defines must not reach the wire Unknown.
# ABOUTME: An unstamped Call is indistinguishable from a genuinely unknowable one.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub call_stamp ($src, $name, $callee) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    my $w = (length $out && $out =~ /^\{/)
          ? eval { JSON::PP->new->decode($out) } : undef;
    return 'NO GRAPH' unless $w;
    my ($c) = grep {
        $_->{op} eq 'Call' && (($_->{fields} // {})->{name} // '') eq $callee
    } map { $_->{nodes}->@* } values $w->{methods}->%*;
    return 'NO CALL' unless $c;
    return $c->{stamp} // 'NO STAMP';
}

# AN UNSTAMPED BUILTIN CALL IS A FAILURE UNKNOWN, not an honest one. perl
# DEFINES what these return, so a consumer that sees Unknown cannot tell them
# apart from a call into a sub nobody can name -- which is the distinction the
# whole honest-vs-failure split rests on.
#
# Measured on 5.42.0, and the subtleties are the point:
#
#     printf   returns a real boolean (is_bool true) -- but CAN FAIL, so the
#              honest type is join(Boolean, Undef) = Scalar, exactly the trade
#              `print` already makes.
#     formline same: is_bool true, and can fail.
#     caller   returns the package name (Str) in scalar context, and UNDEF at
#              the top frame -- so join(Str, Undef) = Scalar.
#     prototype returns undef for a sub that has no prototype -> Scalar.
#     sprintf  always returns a string, and cannot fail -> Str.
#
# So most of these are Scalar rather than the tighter type they look like, and
# claiming Boolean or Str for the failing ones would be a WRONG answer, not a
# more precise one.

subtest 'printf is Scalar -- it can fail' => sub {
    my $st = call_stamp(
        'open my $fh, ">", "/dev/null" or die; my $r = printf {$fh} "%s", "x";'
      . ' print defined $r ? 1 : 0;', 'bc-printf', 'prtf');
    isnt $st, 'NO CALL', 'a printf Call is built' or return;
    is $st, 'Scalar', 'stamped Scalar (Boolean joined with the failure undef)';
};

subtest 'caller is Scalar -- undef at the top frame' => sub {
    my $st = call_stamp('sub f { my $c = caller; print defined $c ? 1 : 0 } f();',
                        'bc-caller', 'caller');
    isnt $st, 'NO CALL', 'a caller Call is built' or return;
    is $st, 'Scalar', 'stamped Scalar (Str joined with undef)';
};

subtest 'sprintf is Str -- it cannot fail' => sub {
    # A RUNTIME FORMAT, or there is no sprintf op at all: perl compiles
    # `sprintf("%s", $v)` to MULTICONCAT, and folds a fully-constant call away
    # entirely. Only a runtime format string leaves a real sprintf.
    my $st = call_stamp('my $f = shift(@ARGV) // "%s";'
                      . ' my $s = sprintf($f, 1); print $s;',
                        'bc-sprintf', 'sprintf');
    isnt $st, 'NO CALL', 'a sprintf Call is built' or return;
    is $st, 'Str', 'stamped Str, not the weaker Scalar';
};

subtest 'prototype is Scalar -- undef when there is none' => sub {
    my $st = call_stamp('sub f {} my $p = prototype("main::f");'
                      . ' print defined $p ? 1 : 0;', 'bc-proto', 'prototype');
    isnt $st, 'NO CALL', 'a prototype Call is built' or return;
    is $st, 'Scalar', 'stamped Scalar';
};

# A CALLEE WHOSE BODY IS VISIBLE IS ALREADY INFERRED -- `sub g { 42 }` stamps
# its call Int, which is better than a Call-is-always-Unknown story would
# suggest. What stays honestly unknown is a callee the graph CANNOT see.
subtest 'a visible callee is inferred; an external one is not' => sub {
    my $vis = call_stamp('sub g { 42 } my $x = g(); print $x;',
                         'bc-visible', 'main::g');
    is $vis, 'Int', 'a visible sub body gives its call a real type';

    # utf8::encode is compiled elsewhere, so its return type is not on the
    # wire. Stamping it would be inventing an answer.
    my $ext = call_stamp('my $s = "x"; utf8::encode($s); print $s;',
                         'bc-external', 'utf8::encode');
    ok +($ext eq 'Unknown' || $ext eq 'NO STAMP' || $ext eq 'NO CALL'),
        "an external callee stays unknown ($ext)";
};

# THE COMMON SPELLING IS NOT A sprintf OP AT ALL. perl compiles
# `sprintf("%s", $v)` to multiconcat and folds a fully-constant call away, so
# the sprintf entry is reachable only with a RUNTIME format. Pinned because a
# list entry that matches nothing is the allow-list hazard this project has
# already been bitten by: it looks like coverage and silently is not.
subtest 'the folded sprintf spelling is Str by another path' => sub {
    my $file = "$dir/bc-fold.pl";
    open my $fh, '>', $file or die;
    print {$fh} qq{use 5.42.0;\nno warnings;\n}
              . qq{my \$v = shift(\@ARGV) // "x";\n}
              . qq{my \$s = sprintf("%s", \$v); print \$s;\n};
    close $fh;
    my $out = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
    my $w = ($out =~ /^\{/) ? eval { JSON::PP->new->decode($out) } : undef;
    ok $w, 'it lowers' or return;

    my @cat = grep { $_->{op} eq 'Concat' }
              map  { $_->{nodes}->@* } values $w->{methods}->%*;
    ok scalar(@cat), 'it becomes Concat nodes, not a sprintf Call' or return;
    is scalar(grep { ($_->{stamp} // '') ne 'Str' } @cat), 0,
        'and every one of them is Str';
};

done_testing;
