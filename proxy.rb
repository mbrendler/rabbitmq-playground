#! /usr/bin/env ruby
# frozen_string_literal: true

require 'socket'

connect_host = '127.0.0.1'
connect_port = 5672

listen_host = '127.0.0.1'
listen_port = 4444

class PrettyFrame
  FRAME_TYPES = {
    1 => :method,
    2 => :content_header,
    3 => :body
  }.freeze

  def call(data)
    return if data.nil? || data.empty?

    type, channel, size = parse_header(data)
    if type == 65
      p(data)
      return
    end
    print_header(type, channel, size)
    print_body(data[7...7 + size])
    raise 'End of Frame not found' if data[7 + size].ord != 0xCE

    call(data[8 + size..-1])
  end

  def parse_header(raw)
    # 0      1         3      7
    # | type | channel | size |
    raw.unpack('CnN')
  end

  def print_header(type, channel, size)
    puts("channel(#{channel}) - #{FRAME_TYPES[type]}(#{type}) - size(#{size})")
  end

  def print_body(raw)
    width = 16
    raw.bytes.each_slice(16).with_index do |slice, i|
      numbers = slice.map { |n| n.to_s(width).rjust(2, '0') }.join(' ')
      str = slice.map(&:chr).join.gsub(/[^[:print:]]/, '.')
      range = "#{i * width}..#{i * width + slice.size - 1}"
      puts("#{range.rjust(12)} | #{numbers.ljust(47)} | #{str.inspect}")
    end
  end
end

s = TCPServer.new(listen_host, listen_port)

while got = s.accept
  connect_socket = TCPSocket.new(connect_host, connect_port)
  puts('new connection')
  pretty_frame = PrettyFrame.new
  loop do
    r = IO.select([got, connect_socket], nil, nil)[0]

    if r.include?(got)
      w = IO.select(nil, [connect_socket], nil, 0)[1]
      if w == [connect_socket]
        gotty = got.recv 1024
        if gotty.empty?
          connect_socket.close
          break
        end
        pretty_frame.call(gotty)
        connect_socket.write(gotty)
      end
    end

    if r.include?(connect_socket)
      w = IO.select(nil, [got], nil, 0)[1]
      if w == [got]
        got.write(connect_socket.recv(1024))
      end
    end
  end
end

s.close
