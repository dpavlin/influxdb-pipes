#!/usr/bin/perl
use warnings;
use strict;
use autodie;

my $host = shift @ARGV || die "usage: INFLUX=http://127.0.0.1:8086/write?db=snmp COMMUNITY=snmp-community $0 host";
my $community = $ENV{COMMUNITY} || 'public';
my $influx    = $ENV{INFLUX} || 'http://127.0.0.1:8086/write?db=snmp';

use Data::Dump qw(dump);
sub XXX { warn "XXX ",scalar @_, Data::Dump::dump(@_) };

my ($sec,$min,$hour,$dd,$mm,$yyyy) = localtime(time); $mm++;
my $time;
use Time::Local;
sub update_time {
	warn "# time $yyyy-$mm-$dd $hour:$min:$sec $time\n";
	$time = timelocal($sec,$min,$hour,$dd,$mm-1,$yyyy) * 1000_000_000;
	return $time;
}

# FIXME add -A to pull interfaces if they go up and down
# -l loopback
# -a all
my $cmd = qq{ifstat -s '$community@#$host' -b -n -t 1};
warn "# $cmd\n";
open(my $ifstat, '-|', $cmd);

my $first_skipped = 0;

my $curl;
sub reopen_curl {
	if ( $ENV{INFLUX} ) {
		open($curl, '|-', qq( curl -i -XPOST $influx --data-binary \@- ));
	} else {
		open($curl, '|-', 'cat');
	}
}

my $stat;

my @if;
my @direction;

my $lines;

while(<$ifstat>) {
	chomp;
	#warn "# [$_]\n";
	s/^\s+//;
	s/(\w) (in|out)/$1_$2/g;
	my @v = split(/\s+/);
	if ( $v[0] eq 'Time' ) {
		shift @v;
		@if = @v;
	} elsif ( $v[0] eq 'HH:MM:SS' ) {
		shift @v;
		@direction = map { s/\W+/_/g; s/^K//; $_ } @v;
	} elsif ( $v[0] =~ m/^(\d\d):(\d\d):(\d\d)/ ) {
		next unless $first_skipped++;
XXX $stat;
		$hour = $1; $min = $2; $sec = $3; update_time;

		reopen_curl;
		my $total;

		foreach my $i ( 0 .. $#if ) {

			my $port = $if[$i];
			my $vlan = '';
			my $is_port = 'T';
			$vlan = ",vlan=$1" if $port =~ m/if(\d\d\d\d\d\d)/;

			print $curl "ifstat,host=$host,port=$port$vlan ",
				$direction[$i*2],   "=", $v[$i*2+1]   * 1024, ",",
				$direction[$i*2+1], "=", $v[$i*2+2] * 1024,
				" $time\n";

			$total += $v[$i*2+1];

			$lines++;
		}

		warn "# $host ", $curl->tell, " total=$total\n";
		close($curl);
	} else {
		die "UNPARSED [$_]";
	}
}


