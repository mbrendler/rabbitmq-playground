#! /usr/bin/env ruby
# frozen_string_literal: true

require 'time'
require 'bunny'
require 'optparse'

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

def parse_options
  exchange_name = 'playground.a-exchange'
  message_properties = { routing_key: 'playground.a-routing-key' }
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] MESSAGE..."
    opts.separator('')
    opts.on('--exchange NAME', 'Use exchange') { |v| exchange_name = v }
    opts.on('--routing-key KEY', 'Set routing key') do |v|
      message_properties[:routing_key] = v
    end

    opts.separator('')
    opts.separator('Message Properties:')
    PROPERTIES.each do |name, type|
      option = "--#{name.to_s.gsub('_', '-')} #{name.to_s.upcase}"
      opts.on(option, "Set #{name} property (#{type})") do |value|
        message_properties[name] = parse_property_option(type, value)
      end
    end
  end.parse!
  [exchange_name, message_properties]
end

def main
  exchange_name, message_properties = parse_options
  connection = Bunny.new
  connection.start
  channel = connection.create_channel
  exchange = channel.topic(exchange_name)
  messages = ARGV.empty? ? [Time.now.iso8601] : ARGV
  messages.each do |message|
    puts "publish: #{message}"
    exchange.publish(message, message_properties)
  end
end

main if $PROGRAM_NAME == __FILE__
