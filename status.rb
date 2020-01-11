#! /usr/bin/env ruby
# frozen_string_literal: true

require 'pp'
require 'bunny'

def main
  connection = Bunny.new
  connection.start
  channel = connection.channel
  queue = channel.queue(ARGV[0] || 'a_test_queue', durable: true, passive: true)
  %i[name durable? auto_delete? exclusive? arguments status].each do |key|
    puts("#{key}: #{queue.send(key)}")
  end
end

main if $PROGRAM_NAME == __FILE__
