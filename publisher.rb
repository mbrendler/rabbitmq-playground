#! /usr/bin/env ruby
# frozen_string_literal: true

require 'time'
require 'bunny'
require 'optparse'
require_relative 'config'

PROPERTIES = Hash[
  AMQ::Protocol::Basic::DECODE_PROPERTIES.map do |id, name|
    [name, AMQ::Protocol::Basic::DECODE_PROPERTIES_TYPE[id]]
  end
].freeze

def parse_property_option(type, value)
  case type
  when :octet then value.to_i
  when :shortstr then value
  when :table then value.split(',').map { |r| r.split('=') }
  when :timestamp then value
  end
end

OPTIONS =
  Struct
  .new(:exchange, :message_properties)
  .new(EXCHANGE, routing_key: ROUTING_KEY)

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options] MESSAGE..."
  opts.separator('')
  opts.on('--exchange NAME', 'Use exchange') { |v| OPTIONS.exchange = v }

  opts.separator('')
  opts.on('--routing-key KEY', 'Set routing key') do |v|
    OPTIONS.message_properties[:routing_key] = v
  end

  opts.separator('')
  opts.separator('Message Properties:')
  PROPERTIES.each do |name, type|
    option = "--#{name.to_s.gsub('_', '-')} #{name.to_s.upcase}"
    opts.on(option, "Set #{name} property (#{type})") do |value|
      OPTIONS.message_properties[name] = parse_property_option(type, value)
    end
  end
end.parse!

def main
  connection = Bunny.new
  connection.start
  channel = connection.create_channel
  exchange = channel.topic(OPTIONS.exchange)
  messages = ARGV.empty? ? [Time.now.iso8601] : ARGV
  messages.each do |message|
    puts "publish: #{message}"
    exchange.publish(message, OPTIONS.message_properties)
  end
end

main if $PROGRAM_NAME == __FILE__
