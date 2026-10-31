sub answer { "[@_]" }
sub outer {
    print answer(), "\n";
    print answer, "\n";
    print &answer, "\n";
    print &answer(), "\n";
}
outer(1, 2);
