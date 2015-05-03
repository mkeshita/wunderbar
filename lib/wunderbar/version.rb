module Wunderbar
  module VERSION #:nodoc:
    MAJOR = 1
    MINOR = 0
    TINY  = 4

    STRING = [MAJOR, MINOR, TINY].join('.')
  end
end unless defined?(Wunderbar::VERSION)
