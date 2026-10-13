# ABOUTME: An emitted module still works when another package requires it: a
# ABOUTME: file starts in its requirer's package, so file-scope subs must say main.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

# A required file is compiled in the package that required it -- measured,
# `package Foo; require "f.pm"` with `print __PACKAGE__` in f.pm prints Foo --
# so a lifted sub emitted at file scope lands in Foo, and the method's
# `main::` call to it dies. chalk's TestPipeline loads Grammar::BNF::Actions
# that way, and 91 of chalk's tests died on it.
sub required_from_foo ($name, $module, $call, $want) {
    my $src = "$dir/$name.pm";
    open my $fh, '>', $src or die $!; print $fh $module; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $src 2>$dir/err);
    my $data = eval { JSON::PP->new->decode($j) };
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) { fail "$name: renders"; diag $d->gap; return }
    my $emitted = "$dir/$name.emitted.pm";
    open $fh, '>', $emitted or die $!; print $fh $out; close $fh;
    for my $file ($src, $emitted) {
        my $got = qx($^X -e 'package Foo; require "$file"; print $call, "\\n"' 2>&1);
        is $got, "$want\n", "$name: " . ($file eq $src ? 'the source' : 'the emission')
            or diag $out;
    }
}

required_from_foo('lexsub', <<'SRC', 'K->new->m(4)', 8);
use 5.42.0;
use experimental "class";
class K {
    my sub helper ($n) { return $n * 2 }
    method m ($n) { return helper($n) }
}
1;
SRC

required_from_foo('anonsub', <<'SRC', 'K2->new->m(4)', 12);
use 5.42.0;
use experimental "class";
class K2 {
    method m ($n) { my $f = sub ($v) { $v * 3 }; return $f->($n) }
}
1;
SRC

required_from_foo('package', <<'SRC', 'P::m(5)', 10);
use 5.42.0;
package P {
    my sub helper ($n) { return $n * 2 }
    sub m ($n) { return helper($n) }
}
1;
SRC

done_testing;
