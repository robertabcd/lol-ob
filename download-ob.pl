#!/usr/bin/perl

use utf8;
use strict;
use lib './lib';
use LWP::UserAgent;
use LWP::Simple;
use JSON qw(encode_json decode_json);
use Time::HiRes qw(usleep gettimeofday tv_interval);


my $tostop = 0;
my $ua = LWP::UserAgent->new(
    agent => '',
    timeouts => 10
);

my $rest_prefix = 'http://112.121.84.194:8088/observer-mode/rest/consumer';
my $rest_region = 'TW';

sub rest_url {
    my ($func, $game_id, $arg) = @_;
    my $prefix = "$rest_prefix/$func/$rest_region/$game_id";
    return "$prefix/null" if $func eq 'endOfGameStats';
    return "$prefix/$arg/token";
}

sub rest_call {
    my ($func, $game_id, $arg) = @_;
    my $resp = $ua->get(rest_url($func, $game_id, $arg));

    debug($resp->decoded_content);
    return decode_json($resp->decoded_content) if $resp->is_success;

    debug("rest_call($func,$game_id,$arg)=>", $resp->code);

    return undef;
}

sub download {
    my ($workdir, $type, $game_id, $index, $overwrite) = @_;
    my $func_map = {
	chunk => 'getGameDataChunk',
	keyframe => 'getKeyFrame',
	endstats => 'endOfGameStats'
    };
    return undef unless $func_map->{$type};

    my $fn = "$workdir/$game_id/$type/$index";
    $fn = "$workdir/$game_id/$type" if $type eq 'endstats';

    return 1 if not $overwrite and -e $fn;

    my $resp = $ua->get(rest_url($func_map->{$type}, $game_id, $index),
	':content_file' => $fn);

    debug("download($type,$game_id,$index)=>", $resp->code);

    return $resp->is_success;
}

sub ensure_dirs {
    my ($workdir, $game_id) = @_;
    `mkdir -p '$workdir/$game_id/$_'` for (qw(chunk keyframe));
}

sub save_meta {
    my ($workdir, $game_id, $obj) = @_;
    open my $fh, ">", "$workdir/$game_id/meta.json";
    print {$fh} encode_json($obj);
    close $fh;
}

sub load_meta {
    my ($workdir, $game_id, $obj) = @_;

    my $fn = "$workdir/$game_id/meta.json";
    return {} unless (-e $fn);

    open my $fh, "<", $fn;
    my $obj = decode_json(<$fh>);
    close $fh;
    return $obj;
}

sub populate_metadata {
    my ($game_id, $m) = @_;

    my $append_keys = {pendingAvailableChunkInfo => 1, pendingAvailableKeyFrameInfo => 1};
    my $gm = rest_call('getGameMetaData', $game_id, 0);

    for my $k (keys %$gm) {
	next if exists $append_keys->{$k};
	$m->{$k} = $gm->{$k};
    }

    for my $k (keys %$append_keys) {
	next if not exists $gm->{$k};
	my $max = -1;
	for (@{$gm->{$k}}) {
	    $m->{$k} = {} if not exists $m->{$k};
	    $m->{$k}->{$_->{id}} = $_ if not exists $m->{$k}->{$_->{id}};
	    $max = int $_->{id} if $max < int $_->{id};
	}
	debug("max($k)=>$max");
    }
}

sub stream {
    my ($workdir, $game_id, $key) = @_;

    ensure_dirs($workdir, $game_id);

    my $m = load_meta($workdir, $game_id);
    my $chunk_id = -1;
    my $keyframe_id = -1;
    my $endchunk = 0;

    $m->{key} = $key;

    while (!$tostop) {
	populate_metadata($game_id, $m);

	my $info = rest_call('getLastChunkInfo', $game_id, 30000);
	my $t0 = [gettimeofday];

	debug("stream: at chunk $chunk_id, keyframe $keyframe_id");

	for (my $i = $chunk_id + 1; $i <= $info->{chunkId}; $i++) {
	    $chunk_id = $i if download($workdir, 'chunk', $game_id, $i, 0);
	}
	for (my $i = $keyframe_id + 1; $i <= $info->{keyFrameId}; $i++) {
	    $keyframe_id = $i if download($workdir, 'keyframe', $game_id, $i, 0);
	}

	if ($endchunk <= 0 and $info->{endGameChunkId} > 0) {
	    $endchunk = $info->{endGameChunkId};
	    debug("stream: end game detected, at chunk $info->{endGameChunkId}");
	}

	save_meta($workdir, $game_id, $m);

	last if $endchunk > 0 and $chunk_id >= $endchunk;

	my $tosleep = int(1000 * $info->{nextAvailableChunk} - 1000000 * tv_interval($t0) + 500000);
	usleep($tosleep) if $tosleep > 0;
    }
    return if $tostop;

    unless (download($workdir, 'endstats', $game_id, 0, 0)) {
	debug("stream: cannot download end of game stats");
    }
}

sub stop_stream {
    $tostop = 1;
    debug("stream: signal caught stopping");
}

sub debug {
    print STDERR @_, "\n";
}


if ($#ARGV != 2) {
    print STDERR "Usage: $0 workdir game_id key\n";
    exit(1);
}
$SIG{'INT'} = 'stop_stream';
stream($ARGV[0], $ARGV[1], $ARGV[2]);
