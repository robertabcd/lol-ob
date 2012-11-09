#!/usr/bin/ruby
# encoding: utf-8

# === NOTES ===
# This script decrypts all chunk and keyframe files and save to the
# corresponding `xxx.bin' directory.
#
# The en/decryption method is obtained by reverse engineering the client.
#
# Each chunk and keyframe is gzipped and then encrypted by a 128-bit key
# using Blowfish in ECB mode.
#
# The encryption key can be obtained by decrypting the `encryptionKey',
# a base64-encoded string obtained from the server through the RPC call,
#	`retrieveInProgressSpectatorGameInfo'. This decryption also utilizes
# Blowfish in ECB mode but using `gameId' string as the decryption key.
#
#
# Robert <robertabcd at gmail.com>
# 2012/11/10
# =============

require 'json'
require 'openssl'
require 'base64'
require 'zlib'

class ReplayDecrypter
	def initialize base='.'
		@base = base
		@meta = JSON.parse(read_file('meta.json'))
		@key = bf_ecb_decrypt @meta['gameKey']['gameId'].to_s,
			Base64.decode64(@meta['key'])
	end

	def get_path path
		return '%s/%s' % [@base, path]
	end

	def read_file fn
		return IO.read(get_path(fn))
	end
	private :read_file

	def bf_ecb_decrypt key, data
		c = OpenSSL::Cipher.new 'bf-ecb'
		c.decrypt
		c.key_len = key.bytesize
		c.key = key
		return c.update(data) + c.final
	end
	private :bf_ecb_decrypt

	def decrypt data
		bf_ecb_decrypt @key, data
	end

	def decrypt_all_files dir=nil
		if dir.nil?
			decrypt_all_files 'keyframe'
			decrypt_all_files 'chunk'
			return
		end

		Dir.foreach(get_path(dir)) do |fn|
			next unless fn =~ /^\d+$/
			begin
				plain = decrypt read_file('%s/%s' % [dir, fn])
				first = plain.unpack('C*').slice(0, 8).map{|x| '%02x' % x}.join(' ')
				puts '%s/%s: bytes=%d %s' % [dir, fn, plain.bytesize, first]
				save_file('%s.bin' % dir, fn, plain)
			rescue => ex
				$stderr.puts 'File decrypt or decompression error: %s/%s' % [dir, fn]
				$stderr.puts ex
			end
		end
	end

	def save_file dir, fn, data
		dir = get_path dir
		Dir.mkdir(dir) if not File.directory? dir

		File.open('%s/%s' % [dir, fn], 'w') do |f|
			gz = Zlib::GzipReader.new(StringIO.new(data))
			f.write gz.read
			gz.close
		end
	end
end

base = '.'
base = ARGV[0] if ARGV.size == 1
ReplayDecrypter.new(base).decrypt_all_files
