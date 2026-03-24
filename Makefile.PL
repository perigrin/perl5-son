# ABOUTME: Build script for the SoN distribution.
# ABOUTME: Uses ExtUtils::MakeMaker to handle XS compilation for FieldInfo.xs.

use v5.42.0;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'SoN',
    VERSION_FROM     => 'lib/SoN.pm',
    ABSTRACT         => 'Sea of Nodes IR for Perl 5',
    AUTHOR           => 'Chris Prather <chris@prather.org>',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.042000',
    PREREQ_PM        => {
        'B' => '0',
    },
    TEST_REQUIRES    => {
        'Test2::V0' => '0',
    },
    XS               => { 'FieldInfo.xs' => 'FieldInfo.c' },
    OBJECT           => 'FieldInfo$(OBJ_EXT)',
    META_MERGE       => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/perigrin/perl5-son.git',
                web  => 'https://github.com/perigrin/perl5-son',
            },
        },
    },
);
