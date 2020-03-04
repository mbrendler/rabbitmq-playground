#! /usr/bin/env ruby
# frozen_string_literal: true

require 'uri'
require 'socket'
require 'amq/protocol'
require 'amq/protocol/frame'
require_relative 'tput'

RABBITMQ_URL = URI.parse(
  ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@127.0.0.1:5672')
)

OPTIONS =
  Struct
  .new(:listen_host, :listen_port, :remote_host, :remote_port)
  .new('127.0.0.1', 4444, RABBITMQ_URL.host, RABBITMQ_URL.port)

class PrettyFrame
  def call(data, from_rabbitmq)
    return if data.nil? || data.empty?

    if from_rabbitmq
      puts("#{Tput.from_rabbitmq}client <<<<<<<<<<<<<<<< RabbitMQ#{Tput.clean}")
    else
      puts("#{Tput.from_client}client >>>>>>>>>>>>>>>> RabbitMQ#{Tput.clean}")
    end
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
    call(data[8 + size..-1], from_rabbitmq)
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

class Proxy
  def self.run(listen_host, listen_port, remote_host, remote_port)
    listen_socket = TCPServer.new(listen_host, listen_port)
    puts("Connect to RABBITMQ_URL=#{listen_uri(listen_host, listen_port)}")
    while (client_socket = listen_socket.accept)
      remote_socket = TCPSocket.new(remote_host, remote_port)
      puts("#{Tput.connection}new connection#{Tput.clean}\n")
      new(client_socket, remote_socket, PrettyFrame.new).run
    end
  ensure
    listen_socket&.close
  end

  def self.listen_uri(listen_host, listen_port)
    RABBITMQ_URL.dup.tap do |uri|
      uri.host = listen_host
      uri.port = listen_port
    end
  end

  def initialize(client_socket, remote_socket, pretty_frame)
    @client_socket = client_socket
    @remote_socket = remote_socket
    @pretty_frame = pretty_frame
    @terminated = false
  end

  def run
    until @terminated
      r = IO.select([@client_socket, @remote_socket], nil, nil)[0]
      handle_client_recv if r.include?(@client_socket)
      break if @terminated

      handle_remote_recv if r.include?(@remote_socket)
    end
  ensure
    @client_socket.close
    @remote_socket.close
    puts("#{Tput.connection}connection closed#{Tput.clean}\n")
  end

  private

  def handle_client_recv
    return unless socket_writable?(@remote_socket)

    data = @client_socket.recv(1024)
    if data.empty?
      @terminated = true
      return
    end
    @pretty_frame.call(data, false)
    @remote_socket.write(data)
  end

  def handle_remote_recv
    return unless socket_writable?(@client_socket)

    data = @remote_socket.recv(1024)
    @pretty_frame.call(data, true)
    @client_socket.write(data)
  end

  def socket_writable?(socket)
    IO.select(nil, [socket], nil, 0)[1] == [socket]
  end
end

def main
  Proxy.run(
    OPTIONS.listen_host,
    OPTIONS.listen_port,
    OPTIONS.remote_host,
    OPTIONS.remote_port
  )
end

main if $PROGRAM_NAME == __FILE__
