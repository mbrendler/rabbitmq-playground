require 'sneakers'

Sneakers.configure
Sneakers.logger.level = Logger::INFO

class Processor
  include Sneakers::Worker
  from_queue :logs

  def work(msg)
    logger.info msg
  end
end
