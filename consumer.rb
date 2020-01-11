#! /usr/bin/env ruby
# frozen_string_literal: true

require 'sneakers'
require 'sneakers/Runner'

Sneakers.configure(prefetch: 1)
Sneakers.logger.level = Logger::INFO

class Worker
  include Sneakers::Worker
  from_queue :a_test_queue

  def work(msg)
    puts msg
    ack! # Tell RabbitMQ that the message is successfully handled.
  end
end

Sneakers::Runner.new([Worker]).run
