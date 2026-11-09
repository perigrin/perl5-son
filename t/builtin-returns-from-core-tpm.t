# ABOUTME: builtin return types come from pvm's CORE.tpm (a copy, lib/B/SoN/CORE.tpm)
# ABOUTME: where no measured row says otherwise -- each one checked against perl.

use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(looks_like_number);
use B::SoN::TypeLibrary;

my $r = sub ($name) { B::SoN::TypeLibrary::result_for( [ 'Call', $name ] ) };

subtest 'a CORE.tpm row types a builtin no measured row covers' => sub {
    is $r->('length'),    'Int',            'length is Int';
    is $r->('uc'),        'Str',            'uc is Str';
    is $r->('wantarray'), 'Maybe[Boolean]', 'Boolean|Undef is Maybe[Boolean]';
};

subtest 'a measured row wins over CORE.tpm' => sub {
    is $r->('close'), 'Boolean', 'close: the measured Boolean';
    is $r->('open'),  'Maybe[Int]', 'open: the measured Maybe[Int]';
};

subtest 'a type the lattice does not have, or that says nothing, is not loaded' => sub {
    is $r->('exit'), undef, 'None (exit never returns) is not a row';
    is $r->('bless'),   undef, "bless: CORE.tpm's Object is any blessed ref; chalk's is a class instance";
    is $r->('dbmopen'), undef, 'dbmopen: likewise';
    is $r->('caller'),  undef, 'caller: one type cannot say both contexts';
    ok !grep( { ( $r->($_) // '' ) =~ /Inf|Optional|\|/ } B::SoN::TypeLibrary::core_builtins() ),
        'no Inf, Optional or bare union reached the table';
};

# THE COPY IS pvm's FILE. Where a pvm checkout is at hand, it must match.
subtest 'the copy matches pvm' => sub {
    my $pvm = $ENV{PVM_SRC} // '/home/user/perigrin/pvm';
    my $src = "$pvm/internal/parse/declarations/CORE.tpm";
    plan skip_all => "no pvm checkout at $pvm (set PVM_SRC)" unless -f $src;
    my $slurp = sub ($f) { open my $h, '<', $f or die "$f: $!"; local $/; <$h> };
    ok $slurp->($src) eq $slurp->( B::SoN::TypeLibrary::core_tpm_path() ),
        'lib/B/SoN/CORE.tpm is pvm\'s CORE.tpm, unchanged';
};

# MEASURED, each declared type against what perl returns: a declaration is a
# claim, and a wrong one becomes a wrong program. Only builtins safe to call.
my %call = (
    length => 'length("abc")',          uc => 'uc("ab")',        lc => 'lc("AB")',
    ucfirst => 'ucfirst("ab")',         lcfirst => 'lcfirst("AB")',
    index => 'index("abc","c")',        rindex => 'rindex("abc","z")',
    substr => 'substr("abc",1)',        sprintf => 'sprintf("%d",3)',
    join => 'join(",",1,2)',            chr => 'chr(65)',        ord => 'ord("A")',
    int => 'int(3.7)',                  sqrt => 'sqrt(4)',       hex => 'hex("ff")',
    oct => 'oct("17")',                 ref => 'ref([])',        time => 'time()',
    defined => 'defined(undef)',        exists => 'exists $h{x}', reverse => 'scalar reverse("ab")',
    quotemeta => 'quotemeta("a.b")',    lcfirst => 'lcfirst("X")', crypt => 'crypt("a","ab")',
    fc => 'fc("A")',                    sin => 'sin(0)',         cos => 'cos(0)',
    exp => 'exp(0)',                    log => 'log(1)',         atan2 => 'atan2(1,1)',
    rand => 'rand()',                   wantarray => 'wantarray()', getppid => 'getppid()',
    chdir => 'chdir(".")',              umask => 'umask()',      sleep => 'sleep(0)',
);
my %in = (
    Int     => sub ($v) { defined $v && !ref $v && $v =~ /\A-?\d+\z/ },
    Num     => sub ($v) { defined $v && !ref $v && looks_like_number($v) },
    Str     => sub ($v) { defined $v && !ref $v },
    Boolean => sub ($v) { defined $v && builtin::is_bool($v) },
);
subtest 'each callable CORE.tpm row holds in perl' => sub {
    my $n = 0;
    for my $b ( sort keys %call ) {
        my $t = $r->($b) // next;
        my ($inner) = $t =~ /\AMaybe\[(\w+)\]\z/;
        my $check = $in{ $inner // $t } // next;
        no warnings;
        my %h;
        my $v = eval "use feature 'fc'; $call{$b}";
        ok !$@ && ( ( $inner && !defined $v ) || $check->($v) ),
            "$b: $call{$b} is a $t" or diag "got: " . ( $v // 'undef' ) . " $@";
        $n++;
    }
    cmp_ok $n, '>=', 25, "measured $n rows";
};

done_testing;
