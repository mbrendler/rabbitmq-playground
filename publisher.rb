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
  queue_name = 'a_test_queue'
  queue_options = { durable: true }
  message_properties = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] MESSAGE..."
    opts.separator('')

    opts.on('--queue QUEUE', 'Use queue') { |value| queue_name = value }
    opts.on('--queue-no-durable', 'disable durable') do
      queue_options[:durable] = false
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
  [queue_name, queue_options, message_properties]
end

def main
  queue_name, queue_options, message_properties = parse_options
  connection = Bunny.new
  connection.start
  channel = connection.create_channel
  queue = channel.queue(queue_name, queue_options)
  messages = ARGV.empty? ? [Time.now.iso8601] : ARGV
  messages.each do |message|
    puts "publish: #{message}"
    # :default_exchange is a direct exchange with no name (''):
    channel.default_exchange.publish(
      message,
      routing_key: queue.name,
      **message_properties
    )
  end
end

main if $PROGRAM_NAME == __FILE__
