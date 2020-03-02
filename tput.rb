module Tput
  MAP = {
    red: 'setaf 1',
    green: 'setaf 2',
    yellow: 'setaf 3',
    blue: 'setaf 4',
    cyan: 'setaf 6'
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
    "#{cyan}#{bold}"
  end

  def self.method_name
    blue
  end

  def self.from_rabbitmq
    "#{red}#{bold}"
  end

  def self.from_client
    "#{green}#{bold}"
  end
end
