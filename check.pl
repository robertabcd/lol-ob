#!/usr/bin/perl

use utf8;
use strict;
use lib './lib';
use JSON;

sub max_id {
    my ($h) = @_;
    my $max = 0;
    for (keys %$h) {
	$max = int $_ if $max < int $_;
    }
    return $max;
}

sub check_meta_and_files {
    my ($prefix, $m, $max) = @_;
    for (my $i = 1; $i <= $max; $i++) {
	print STDERR "$prefix:$i: no metadata found\n" unless exists $m->{"$i"};
	print STDERR "$prefix:$i: no data file found\n" unless -e "$prefix/$i";
    }
}

sub check_dir {
    my ($dir) = @_;

    open my $fh, "<", "$dir/meta.json";
    my $m = decode_json(<$fh>);
    close $fh;

    print STDERR "$dir: meta.json: no key\n" unless $m->{key} and $m->{key} ne '';

    my $max_chunk_id = max_id($m->{pendingAvailableChunkInfo});
    check_meta_and_files("$dir/chunk", $m->{pendingAvailableChunkInfo}, $max_chunk_id);

    my $max_keyframe_id = max_id($m->{pendingAvailableKeyFrameInfo});
    check_meta_and_files("$dir/keyframe", $m->{pendingAvailableKeyFrameInfo}, $max_keyframe_id);
}

if ($#ARGV < 0) {
    print STDERR "Usage: $0 dir ...\n";
    exit(-1);
}
check_dir($_) for @ARGV;
