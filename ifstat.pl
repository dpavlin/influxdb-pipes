#!/usr/bin/perl
use warnings;
use strict;
use autodie;

my $host = shift @ARGV || die "usage: INFLUX=http://127.0.0.1:8086/write?db=snmp COMMUNITY=snmp-comminity $0 host";
my $community = $ENV{COMMUNITY} || 'public';
my $influx    = $ENV{INFLUX} || 'http://127.0.0.1:8086/write?db=snmp';

use Data::Dump qw(dump);
sub XXX { warn "XXX ", scalar(@_), Data::Dump::dump(@_), join(' ',caller), "\n"; };

my ($sec,$min,$hour,$dd,$mm,$yyyy) = localtime(time); $mm++;
my $time;
use Time::Local;
sub update_time {
	#warn "# time $yyyy-$mm-$dd $hour:$min:$sec $time\n";
	$time = timelocal($sec,$min,$hour,$dd,$mm-1,$yyyy) * 1000_000_000;
	return $time;
}

# FIXME add -A to pull interfaces if they go up and down
# -l loopback
# -a all
my $cmd = qq{ifstat -s '$community@#$host' -a -l -b -n -t 1};
warn "# $cmd\n";
open(my $ifstat, '-|', $cmd);

my $first_skipped = 0;

my $curl;
sub reopen_curl {
	if ( $ENV{INFLUX} ) {
		open($curl, '|-', qq( curl -XPOST $influx --data-binary \@- ));
	} else {
		open($curl, '|-', 'tee /dev/shm/curl.debug');
	}
}

my $stat;

my @if;
my @direction;

my $lines;
my $host_tags = $host;
$host_tags =~ s/\./,domain=/;

while(<$ifstat>) {
	chomp;
	#warn "# [$_]\n";
	s/^\s+//;
	s/(\w) (in|out)/$1_$2/g;
	my @v = split(/\s+/);
	#warn "## [",join(' ',@v), "]\n";
	if ( $v[0] eq 'Time' ) {
		shift @v;
		@if = @v;
	} elsif ( $v[0] eq 'HH:MM:SS' ) {
		shift @v;
		@direction = map { s/\W+/_/g; s/^K//; $_ } @v;
	} elsif ( $v[0] =~ m/^(\d\d):(\d\d):(\d\d)/ ) {
		next unless $first_skipped++;
		$hour = $1; $min = $2; $sec = $3; update_time;

		reopen_curl;
		my $total;

		foreach my $i ( 0 .. $#if ) {

			my $if = $if[$i];
			
			my @tags = ( "if=$if", "host=$host_tags", $ENV{TAGS} || 'no_tags=true' );
=for later
			if ( $if =~ m/if(\d\d)(\d\d\d\d)/ ) {
				push @tags, "is_vlan=T,prefix=$1,vlan=$2";
			} elsif ( $if =~ m/if(\d+)/ ) {
				push @tags, "is_vlan=F,port=$1";
			} else {
				push @tags, "unknown_if=$if";
			}
=cut

			my $v1 = int( $v[$i*2+1] * 1024 );
			my $v2 = int( $v[$i*2+2] * 1024 );

			print $curl "ifstat,", join(',', @tags),
				" ", $direction[$i*2],   "=${v1}i",
				",", $direction[$i*2+1], "=${v2}i",
				" $time\n" if $v1 < 100_000_000_000_000 && $v2 < 100_000_000_000_000;

			$total += $v[$i*2+1];

			$lines++;
		}

		warn "# $host ", $curl->tell, " total=$total\n";
		close($curl);
	} else {
		die "UNPARSED [$_]";
	}
}


