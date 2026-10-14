# ABOUTME: A lexical sub at the top of a module the program `use`s shares that module's
# ABOUTME: lexicals by name, as one at the top of the program does; its body is not emitted.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);
mkdir "$dir/lib";

sub write_file ($path, $text) {
    open my $fh, '>', $path or die "$path: $!"; print $fh $text; close $fh;
}

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    write_file($f, $src);
    my $out = qx(/usr/bin/timeout 10 $^X -I$dir/lib $f 2>&1); unlink $f; return $out;
}

# translate($modules, $main) -> (wire, producer stderr): the modules are
# written to lib/ and the MAIN PROGRAM is what B::SoN is asked to compile.
sub translate ($modules, $main) {
    write_file("$dir/lib/$_.pm", $modules->{$_}) for keys %$modules;
    my $f = "$dir/main.pl";
    write_file($f, $main);
    my $json = qx($^X -Ilib -I$dir/lib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    my $err = do { local (@ARGV, $/) = "$dir/err"; <> } =~ s/^\S+ syntax OK\n//mr;
    unlink "$dir/lib/$_.pm" for keys %$modules;
    return (eval { JSON::PP->new->decode($json) }, $err);
}

sub round_trips ($modules, $main, $name) {
    write_file("$dir/lib/$_.pm", $modules->{$_}) for keys %$modules;
    my $want = run_perl($main);
    my ($data, $err) = translate($modules, $main);
    is $err, '', "$name: the producer says nothing";
    return fail "$name: translates" unless $data;
    my $d = SoN::Deparse->new;
    my $out = $d->render($data) // return fail "$name: renders (" . ($d->gap // '?') . ')';
    # THE MODULE IS LOADED, NOT RE-EMITTED, and its lifted bodies with it: a
    # body read the module's lexicals by name, and in this file they are not
    # declared.
    unlike $out, qr/__ANON__/, "$name: no body of the module is emitted";
    write_file("$dir/lib/$_.pm", $modules->{$_}) for keys %$modules;
    is run_perl($out), $want, $name or diag "--- emitted ---\n$out";
    unlink "$dir/lib/$_.pm" for keys %$modules;
}

my $main = 'use v5.36; use M; print M->new->m(4), "\n";';

# chalk's TypeInferenceActions, used by TypeInference: a predicate held in a
# class-block lexical, passed on by `my sub`s the methods call.
round_trips({ M => 'use v5.36; use experimental "class";
class M { my $x = sub ($n) { $n * 2 }; my sub f ($v) { $x->($v) } method m ($v) { f($v) } }
1;' }, $main, 'a lexical sub over a class-block code ref');

round_trips({ M => 'use v5.36; use experimental "class";
my $k = 3; my @a = (1, 2); my %h = (a => 10);
class M { my sub f ($v) { $v + $k + $a[1] + $h{a} + scalar(@a) } method m ($v) { f($v) } }
1;' }, $main, 'a lexical sub over a file scalar, array and hash');

round_trips({ M => 'use v5.36; use experimental "class";
class M { my $c = 0; my sub bump () { $c++ } method m ($v) { bump(); bump(); $c + $v } }
1;' }, $main, 'a lexical sub writing the module lexical it closes over');

round_trips({ M => 'package M; use v5.36;
my $x = sub ($n) { $n * 3 }; my sub f ($v) { $x->($v) }
sub new { bless {}, shift } sub m ($s, $v) { f($v) }
1;' }, $main, 'a lexical sub in a package rather than a class');

# TWO MODULES, ONE NAME: each lexical is its own file's, so a name declared
# once in each is declared once per file.
round_trips({
    M => 'use v5.36; use experimental "class";
class M { my $x = 1; my sub f ($v) { $v + $x } method m ($v) { f($v) + N->new->m($v) } }
1;',
    N => 'use v5.36; use experimental "class";
class N { my $x = 100; my sub f ($v) { $v * $x } method m ($v) { f($v) } }
1;',
}, 'use v5.36; use N; use M; print M->new->m(4), N->new->m(2), "\n";', 'two modules, each closing over its own $x');

# BY NAME IS ONE VARIABLE PER NAME IN THE FILE: a module declaring the name
# twice still refuses, in the module's own words.
{
    my (undef, $err) = translate({ M => 'use v5.36; use experimental "class";
class M { my $x = 1; my sub f { $x } { my $x = 2; my sub g { $x } method n { g() } } method m ($v) { f() + $v } }
1;' }, $main);
    like $err, qr/a lexical sub closing over \$x is not yet lowered -- the file declares that name more than once/,
        'a module declaring the captured name twice refuses';
}

done_testing;
