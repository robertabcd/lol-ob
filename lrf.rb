# coding: utf-8

require 'json'
require 'stringio'

class LrfFile
	def initialize io
		@unk0 = 0 # seems to be 68352 (0x10b00) in spectator replays
		@meta = nil
		@parts = []

		load_file io if not io.nil?
	end

	def load_file f
		@unk0, meta_size = f.read(8).unpack('VV')
		@meta = JSON.parse(f.read(meta_size), {:symbolize_names => 1})
		@objects = {}

		data_offset = f.tell

		@meta[:dataIndex].each do |d|
			key, offset, size = d[:Key], d[:Value][:offset], d[:Value][:size]
			#$stderr.puts "#{d[:Key]} offset #{offset} size #{size}"
			f.seek data_offset + offset
			@parts << key.to_sym
			@objects[key.to_sym] = load_part d[:Key], StringIO.new(f.read(size))
		end
	end

	def load_part key, io
		case key
		when 'stream'
			LrfStream.new io
		when /^s\d$/
			LrfScreenShot.new io
		else
			raise "Unknown key: #{key}"
		end
	end

	def save io
		offset = 0
		ios = {}
		@meta[:dataIndex] = @parts.map do |key|
			ios[key] = StringIO.new
			@objects[key].save ios[key]
			ios[key].rewind
			m = {
				:Key => key,
				:Value => {
					:offset => offset,
					:size => ios[key].size
				}
			}
			offset += ios[key].size
			m
		end
		json = @meta.to_json
		io.write [@unk0, json.bytesize].pack('VV')
		io.write json
		@parts.each do |key|
			IO.copy_stream ios[key], io
		end
	end

	def [] k
		@objects[k]
	end

	attr_accessor :unk0
	attr_accessor :meta
end

class LrfBinaryChunk
	def initialize io=nil
		@data = io.read if not io.nil?
	end

	def save io
		io.write @data
	end

	attr_accessor :data
end

class LrfScreenShot < LrfBinaryChunk
	def initialize io=nil
		super io
	end
end

class LrfStream
	def initialize io=nil
		@type = nil
		@payload = nil

		if not io.nil?
			@type, size = io.read(5).unpack('CV')
			bin = StringIO.new io.read(size - 5)

			case @type
			when 0x4e
				@payload = LrfSpectatorStream.new bin
			else
				raise "Unknown type 0x%02x" % [@type]
			end
		end
	end

	def save io
		buf = StringIO.new
		@payload.save buf
		buf.rewind

		io.write [@type, 5 + buf.size].pack('CV')
		IO.copy_stream buf, io
	end

	def to_s
		"#<LrfStream type=0x%02x>" % [@type]
	end

	attr_accessor :type
	attr_accessor :payload
end

class LrfSpectatorStream
	def initialize io=nil
		@objects = []

		if not io.nil?
			io_size = io.size
			payload_size = io.read(4).unpack('V')[0]
			raise "Size mismatch expected #{payload_size + 4} got #{io_size}" if io_size != payload_size + 4

			while not io.eof?
				@objects << LrfSpectatorObject.new(io)
			end
		end
	end

	def save io
		payload = StringIO.new
		@objects.each do |obj|
			obj.save payload
		end
		payload.rewind

		io.write [payload.size].pack('V')
		IO.copy_stream payload, io
	end

	attr_accessor :objects
end

class LrfSpectatorObject
	def initialize io=nil
		@unk0, @unk1 = 0, 0
		@uri, @data = '', ''

		if not io.nil?
			@unk0, size0, @uri = read_one io
			@unk1, size1, @data = read_one io
		end
	end

	def read_one io
		unk0, size = io.read(8).unpack('VV')
		obj = io.read(size)
		magic = io.read(1).unpack('C')[0]
		raise "Magic error: expected 0x0a got 0x%02x" % magic if magic != 0x0a
		return unk0, size, obj
	end

	def save io
		io.write [@unk0, @uri.bytesize].pack('VV')
		io.write @uri
		io.write [0x0a].pack('C')

		io.write [@unk1, @data.bytesize].pack('VV')
		io.write @data
		io.write [0x0a].pack('C')
	end

	def to_s
		"#<LrfSpectatorObject unk0=#{@unk0} unk1=#{@unk1} #data=#{@data.size} uri=#{@uri}>"
	end

	attr_accessor :uri
	attr_accessor :data
end
