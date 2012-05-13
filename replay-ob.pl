#!/usr/bin/perl

{
package LOL::OB::Replay;
use strict;
use utf8;
use lib './lib';
use JSON;
use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);

my %dispatch = (
    'getGameMetaData' => \&getGameMetaData,
    'getLastChunkInfo' => \&getLastChunkInfo,
    'getGameDataChunk' => \&getGameDataChunk,
    'getKeyFrame' => \&getKeyFrame,
    'version' => \&version
);

sub workdir {
    my ($s, $val) = @_;
    if ($val) {
	$s->{workdir} = $val;

	open my $fh, '<', $s->{workdir} . "/meta.json" or return undef;
	my $m = decode_json(<$fh>);
	close $fh;

	print STDERR $m->{key}, " ", $m->{gameKey}->{gameId}, "\n";

	$s->{chunks} = $m->{pendingAvailableChunkInfo};

	delete $m->{key};
	$m->{clientBackFetchingEnabled} = JSON::true;

	for (qw(pendingAvailableChunkInfo pendingAvailableKeyFrameInfo)) {
	    $m->{$_} = hash_to_sorted_array($m->{$_});
	}

	my $max_chunk_id = -1;
	for (@{$m->{pendingAvailableChunkInfo}}) {
	    $max_chunk_id = int($_->{id}) if ($max_chunk_id < int($_->{id}));
	}

	$s->{metadata} = $m;
	$s->{max_chunk_id} = $max_chunk_id;
	$s->{do_startup} = 1;
    }
    return $s->{workdir};
}

sub handle_request {
    my ($s, $cgi) = @_;

    my $path = $cgi->path_info();

    if ($path =~ m{^/observer-mode/rest/consumer/([^/]+)(.*)$}) {
	my $handler = $dispatch{$1};
	my @args = split(/\//, $2);
	shift @args if $#args > -1 and $args[0] eq '';
	if (ref($handler) eq 'CODE') {
	    $handler->($s, $cgi, @args);
	    return;
	}
    }

    print "HTTP/1.0 500 Error\r\n";
    print "Connection: close\r\n";
    print "\r\n";
}

sub serve_file {
    my ($fn) = @_;
    my $buf;
    open my $fh, '<', $fn or return undef;
    binmode $fh;
    binmode STDOUT;
    while (read($fh, $buf, 65536) and print $buf) {}
    close $fh;
    return 1;
}

sub version {
    my ($s, $cgi, $region, $gid, $idx, $token) = @_;
    print "HTTP/1.0 200 OK\r\n", $cgi->header;
    print "1.59.01";
}

sub getGameDataChunk {
    my ($s, $cgi, $region, $gid, $idx, $token) = @_;
    print "HTTP/1.0 200 OK\r\n", $cgi->header;
    serve_file($s->{workdir} . "/chunk/$idx");
}

sub getKeyFrame {
    my ($s, $cgi, $region, $gid, $idx, $token) = @_;
    print "HTTP/1.0 200 OK\r\n", $cgi->header;
    serve_file($s->{workdir} . "/keyframe/$idx");
}

sub getLastChunkInfo {
    my ($s, $cgi, $region, $gid, $interval, $token) = @_;

    my $gm = $s->{metadata};
    my $ckid = $s->{max_chunk_id};
    my $chunk = $s->{chunks}->{"$ckid"};
    my $obj = {
	chunkId => $ckid,
	availableSince => 30000,
	nextAvailableChunk => 30000,
	keyFrameId => $gm->{lastKeyFrameId},
	nextChunkId => $s->{max_chunk_id},
	endStartupChunkId => $gm->{endStartupChunkId},
	startGameChunkId => $gm->{startGameChunkId},
	duration => $chunk ? $chunk->{duration} : 30000
    };

    print STDERR "do_startup=>", $s->{do_startup}, "\n";
    if ($s->{do_startup} < 10) {
	$ckid = $s->{do_startup};
	$chunk = $s->{chunks}->{"$ckid"};
	my $kf = find_keyframe($s, $ckid);
	$obj->{chunkId} = $ckid;
	$obj->{keyFrameId} = int $kf->{id};
	$obj->{nextChunkId} = $kf->{nextChunkId};
	$obj->{nextAvailableChunk} = 10000;
	$obj->{duration} = $chunk ? $chunk->{duration} : 30000;
	$s->{do_startup}++;
    }

    print "HTTP/1.0 200 OK\r\n", $cgi->header;
    print STDERR encode_json($obj), "\n";
    print encode_json($obj);
}

sub getGameMetaData {
    my ($s, $cgi, $region, $gid, $zero, $token) = @_;

    print "HTTP/1.0 200 OK\r\n", $cgi->header;
    print encode_json($s->{metadata});
}

sub find_keyframe {
    my ($s, $ckid) = @_;
    my $gm = $s->{metadata};
    my $kf;
    for (@{$gm->{pendingAvailableKeyFrameInfo}}) {
	if (not $kf or $_->{nextChunkId} <= $ckid) {
	    $kf = $_;
	} else {
	    last;
	}
    }
    return $kf;
}

sub hash_to_sorted_array {
    my ($h) = @_;
    return [sort { int($a->{id}) <=> int($b->{id}) } values %$h];
}

}


if ($#ARGV != 0) {
    print STDERR "Usage: $0 dir\n";
    exit(-1);
}
my $server = LOL::OB::Replay->new(8088);
print "8088\n";
$server->workdir($ARGV[0]);
$server->run();
