# ABOUTME: CPAN dependency specification for the SoN distribution.
# ABOUTME: Requires perl 5.42.0 for feature class and modern builtins.

requires 'perl', '5.042000';
requires 'B';

on 'build' => sub {
    requires 'Module::Build', '0.42';
};

on 'test' => sub {
    requires 'Test2::V0';
};
