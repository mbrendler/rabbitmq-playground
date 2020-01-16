#! /usr/bin/env ruby
# frozen_string_literal: true

require 'socket'
require 'amq/protocol'
require 'amq/protocol/frame'

connect_host = '127.0.0.1'
connect_port = 5672

listen_host = '127.0.0.1'
listen_port = 4444

module Tput
  MAP = {
    red: 'setaf 1',
    yellow: 'setaf 3',
    blue: 'setaf 4'
  }.freeze

  (%i[bold op sgr0] + MAP.keys).each do |name|
    if $stdout.tty?
      define_singleton_method(name) do
        instance_variable_get("@#{name}") ||
          instance_variable_set("@#{name}", `tput #{MAP.fetch(name, name)}`)
      end
    else
      define_singleton_method(name) { '' }
    end
  end

  def self.clean
    "#{op}#{sgr0}"
  end

  def self.header
    "#{yellow}#{bold}"
  end

  def self.connection
    "#{red}#{bold}"
  end

  def self.method_name
    blue
  end
end

class PrettyFrame
  def call(data)
    return if data.nil? || data.empty?

    type, channel, size = parse_header(data)
    if type == 65
      puts("#{Tput.header}unhandled frame#{Tput.clean}")
      print_body(data)
      puts
      return
    end
    print_header(type, channel, size)
    type_name = AMQ::Protocol::Frame::TYPES_REVERSE[type]
    if type_name == :method
      method_frame = AMQ::Protocol::MethodFrame.new(data[7...7 + size], nil)
      puts("  #{Tput.method_name}#{method_frame.method_class.name}#{Tput.clean}")
      begin
        payload = method_frame.decode_payload
        payload.instance_variables.each do |ivar_name|
          value = payload.instance_variable_get(ivar_name)
          puts("  #{ivar_name.to_s[1..-1]}: #{format_value(value)}")
        end
      rescue NoMethodError
      end
    elsif type_name == :headers
      header_frame = AMQ::Protocol::HeaderFrame.new(data[7...7 + size], nil)
      header_frame.properties.each do |name, value|
        puts("  #{name}: #{value}")
      end
    end
    print_body(data[7...7 + size])
    raise 'End of Frame not found' if data[7 + size].ord != 0xCE

    puts
    call(data[8 + size..-1])
  end

  def format_value(value, indent: 4)
    return value unless value.is_a?(Hash)

    value.map do |k, v|
      "\n#{' ' * indent}#{k}: #{format_value(v, indent: indent + 2)}"
    end.join
  end

  def parse_header(raw)
    # 0      1         3      7
    # | type | channel | size |
    raw.unpack('CnN')
  end

  def print_header(type, channel, size)
    type_name = AMQ::Protocol::Frame::TYPES_REVERSE[type]
    puts("#{Tput.header}channel(#{channel}) - #{type_name}(#{type}) - size(#{size})#{Tput.clean}")
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

while (client_socket = s.accept)
  connect_socket = TCPSocket.new(connect_host, connect_port)
  puts("#{Tput.connection}new connection#{Tput.clean}\n")
  pretty_frame = PrettyFrame.new
  loop do
    r = IO.select([client_socket, connect_socket], nil, nil)[0]

    if r.include?(client_socket)
      w = IO.select(nil, [connect_socket], nil, 0)[1]
      if w == [connect_socket]
        data = client_socket.recv(1024)
        if data.empty?
          connect_socket.close
          client_socket.close
          puts("#{Tput.connection}connection closed#{Tput.clean}\n")
          break
        end
        pretty_frame.call(data)
        connect_socket.write(data)
      end
    end

    if r.include?(connect_socket)
      w = IO.select(nil, [client_socket], nil, 0)[1]
      if w == [client_socket]
        data = connect_socket.recv(1024)
        pretty_frame.call(data)
        client_socket.write(data)
      end
    end
  end
end

s.close
