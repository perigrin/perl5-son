sub vals { ({ a => 1 }, [2], { b => 1 }) }
my @v = vals(); print scalar(@v), " ", ref($v[1]), "\n";
