#!/usr/bin/perl
use warnings;
use strict;
use autodie;
use Data::Dump;
sub XXX { warn "### ",Data::Dump::dump(@_) };

open(my $ifstat, '-|',
qq{ifstat -s 'infosl_com_koo7Kaph@#10.20.0.2' -t -b -a -n -A 1 1});

while(<$ifstat>) {
	chomp;
	warn "# [$_]\n";
	s/^\s+//;
	my @v = split(/\s+/);
	XXX(@v);

}


