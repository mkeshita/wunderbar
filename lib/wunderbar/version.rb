module Wunderbar
  module VERSION #:nodoc:
    MAJOR = 1
    MINOR = 5
    TINY  = 0

    STRING = [MAJOR, MINOR, TINY].join('.')
  end
end unless defined?(Wunderbar::VERSION)
