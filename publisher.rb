#! /usr/bin/env ruby
# frozen_string_literal: true

require 'time'
require 'bunny'

def main
  connection = Bunny.new
  connection.start
  channel = connection.create_channel
  # durable ... the queue servives a restart of RabbitMQ
  queue = channel.queue('a_test_queue', durable: true)
  messages = ARGV.empty? ? [Time.now.iso8601] : ARGV
  messages.each do |message|
    puts "publish: #{message}"
    # :default_exchange is a direct exchange with no name (''):
    channel.default_exchange.publish(message, routing_key: queue.name)
  end
end

main if $PROGRAM_NAME == __FILE__
