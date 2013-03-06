# coding: utf-8

require 'stringio'

module Rofl
	class RoflFile
		def initialize
			@magic = "RIOT\0\0"
			@signature = "\0" * 256
			@metadata = ''
			@payload = Payload.new
		end

		attr_accessor :magic, :signature, :metadata, :payload
	end

	class Payload
		def initialize
			@game_id = 0
			@game_length = 0
			@chunks = []
			@keyframes = []
			@end_startup_chunk_id = 0
			@start_game_chunk_id = 0
			@keyframe_interval = 60000
			@encryption_key = ''
		end

		attr_accessor :game_id, :game_length, :chunks, :keyframes
		attr_accessor :end_startup_chunk_id
		attr_accessor :start_game_chunk_id
		attr_accessor :keyframe_interval
		attr_accessor :encryption_key
	end

	class Entry
		def initialize
			@id = 0
			@type = 0
			@next_chunk_id = 0
			@data = ''
		end

		def to_s
			t = case @type
					when 1; 'CHUNK'
					when 2; 'KEYFRAME'
					else; '%d' % [@type]
					end

			'#<Entry id=%d type=%s nxck=%d data.length=%d>' % [
				@id, t, @next_chunk_id, @data.bytesize
			]
		end

		attr_accessor :id, :type, :next_chunk_id, :data
	end

	class Reader
		def initialize io
			@io = io
		end

		def read
			rofl = RoflFile.new

			buf = @io.read 0x120
			rofl.magic = buf.byteslice(0, 6)
			rofl.signature = buf.byteslice(6, 256)
			hl, fl, moff, ml, phoff, phl, poff = buf.byteslice(262, 26).unpack('vV*')
			raise 'Header length is not 0x120' if not hl == 0x120
			buf += @io.read(fl - hl)

			rofl.metadata = buf.byteslice(moff, ml)

			_read_payload rofl.payload,
				StringIO.new(buf.byteslice(phoff, phl)),
				StringIO.new(buf.byteslice(poff, fl - poff))

			rofl
		end

		def _read_payload p, hio, pio
			gidl, gidh, p.game_length, nr_keyframes, nr_chunks,
				p.end_startup_chunk_id, p.start_game_chunk_id,
				p.keyframe_interval, enckl = hio.read(34).unpack('VVVVVVVVv')
			p.game_id = (gidh << 32) | gidl
			p.encryption_key = hio.read(enckl)

			eio = StringIO.new pio.read(17 * (nr_chunks + nr_keyframes))
			buf = pio.read
			nr_chunks.times do
				p.chunks << _read_entry(eio, buf)
			end
			nr_keyframes.times do
				p.keyframes << _read_entry(eio, buf)
			end
			nil
		end
		private :_read_payload

		def _read_entry eio, buf
			e = Entry.new
			e.id, e.type, len, e.next_chunk_id, off = eio.read(17).unpack('VCVVV')
			e.data = buf.byteslice(off, len)
			e
		end
		private :_read_entry
	end

	class Writer
		def initialize io
			@io = io
		end

		def write rofl
			raise 'Magic is not of size 6' if rofl.magic.size != 6
			raise 'Signature is not of size 256' if rofl.signature.size != 256
			outio = StringIO.new
			hio = StringIO.new
			eio = StringIO.new
			pio = StringIO.new

			_write_payload rofl.payload, hio, eio, pio

			fl = 0x120 + rofl.metadata.bytesize + hio.tell + eio.tell + pio.tell
			ml = rofl.metadata.bytesize

			outio.write rofl.magic
			outio.write rofl.signature
			outio.write [
				0x120,
				fl,
				0x120,
				ml,
				0x120 + ml,
				hio.tell,
				0x120 + ml + hio.tell,
			].pack('vVVVVVV')

			hio.rewind
			eio.rewind
			pio.rewind
			outio.rewind

			@io.write outio.read
			@io.write rofl.metadata
			@io.write hio.read
			@io.write eio.read
			@io.write pio.read
		end

		def _write_payload p, hio, eio, pio
			hio.write [
				p.game_id & 0xffffffff,
				(p.game_id >> 32) & 0xffffffff,
				p.game_length,
				p.keyframes.size,
				p.chunks.size,
				p.end_startup_chunk_id,
				p.start_game_chunk_id,
				p.keyframe_interval,
				p.encryption_key.bytesize
			].pack('VVVVVVVVv')
			hio.write p.encryption_key
			p.chunks.each do |c|
				_write_entry c, eio, pio
			end
			p.keyframes.each do |k|
				_write_entry k, eio, pio
			end
			nil
		end
		private :_write_payload

		def _write_entry e, eio, pio
			eio.write [
				e.id,
				e.type,
				e.data.bytesize,
				e.next_chunk_id,
				pio.tell
			].pack('VCVVV')
			pio.write e.data
			nil
		end
		private :_write_entry
	end
end
