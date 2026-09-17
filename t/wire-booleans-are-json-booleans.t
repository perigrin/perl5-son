# ABOUTME: the class section's flags must reach the wire as JSON true/false.
# ABOUTME: pins the wire so decoupling the model from JSON::PP cannot change it.
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

# THE RAW TEXT, not a decoded value. JSON::PP decodes `true` and `1` to values
# that compare equal under `==`, so a decoded check cannot tell them apart --
# and the difference is exactly what a consumer's schema sees. Chalk's loader
# replays this section through its MOP, so a flag arriving as 1 where it
# declared a boolean is a contract change, not a formatting one.
sub wire_text ( $src, $name, $pkg = 'main' ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    return qx{$PERL -Ilib -MO=SoN,json,package=$pkg $file 2>/dev/null};
}

# Every boolean the model builds lands in the `classes` section, which the
# serializer emits RAW -- there is no _extract_fields pass over it. So these
# flags are the ones a model/encoder decoupling could silently flip to 1/0.
subtest 'a class section flag is a JSON boolean' => sub {
    my $json = wire_text( <<'SRC', 'flags', 'Point' );
use feature 'class';
no warnings 'experimental::class';
class Point {
    field $x :param = 0;
    field $y :reader = 1;
    method sum { $x }
}
SRC
    ok length $json, 'it translates' or return;

    like $json, qr/"is_param"\s*:\s*(?:true|false)/,
        'is_param is a JSON boolean';
    like $json, qr/"has_default"\s*:\s*true/,
        'has_default is a JSON boolean';
    like $json, qr/"is_reader"\s*:\s*true/,
        'is_reader is a JSON boolean';
    like $json, qr/"invocant"\s*:\s*true/,
        'invocant is a JSON boolean';

    unlike $json, qr/"is_param"\s*:\s*[01]\b/,
        'and not a bare 1/0 that a schema would reject';
};

# uses_args rides on a plain sub rather than a class, so it needs its own
# program to appear at all.
subtest 'uses_args is a JSON boolean' => sub {
    my $json = wire_text( 'sub f { my $n = shift; return $n } print f(1);',
        'uses-args' );
    ok length $json, 'it translates' or return;
    like $json, qr/"uses_args"\s*:\s*(?:true|false)/,
        'uses_args is a JSON boolean';
    unlike $json, qr/"uses_args"\s*:\s*[01]\b/, 'not a bare 1/0';
};

done_testing;
