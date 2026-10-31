sub classify {
    return "zero" if $_[0] == 0;
    return "negative" if $_[0] < 0;
    return "positive";
}
print classify(0), " ", classify(-5), " ", classify(7), "\n";
