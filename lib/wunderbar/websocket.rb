#!/usr/bin/ruby
require 'wunderbar/job-control'
require 'open3'
require 'socket'

require 'em-websocket'

module Wunderbar
  class Channel < BuilderBase
    attr_reader :port, :connected, :complete

    def initialize(port, limit, locals=nil)
      # verify that the port is available
      TCPServer.new('0.0.0.0', port).close 

      super()
      @port = port
      @connected = @complete = false
      @onopen = @onmessage = @onerror = @onclose = Proc.new {}
      @_scope = Struct.new(:params).new({})
      @channel1 = EM::Channel.new
      @channel2 = EM::Channel.new
      @memory = []
      @memory_channel = @channel1.subscribe do |msg| 
        @memory << msg.chomp unless Symbol === msg
        @memory.shift while @connected and limit and @memory.length > limit
      end

      if locals
        @_scope = locals['_scope'] || @_scope
        set_variables_from_params(locals)
        _ :type => 'stdout', :line => locals['_scope'].methods.inspect
      end

      websocket.run
    end

    def websocket
      return @websocket if @websocket
      ready = false
      @websocket = Thread.new do
        EM.epoll
        EM.run do
          connection = EventMachine::WebSocket::Connection
          EM.start_server('0.0.0.0', @port, connection, {}) do |ws|
            ws.onopen do
              @onopen.call(ws)
              @memory.each {|msg| ws.send msg }
              @connected = true
              ws.close_websocket if complete
            end
        
            sid = @channel1.subscribe do |msg| 
              if msg == :shutdown
                ws.close_websocket
              else
                ws.send msg
              end
            end
        
            ws.onmessage {|msg| @onmessage.call(msg); @channel2.push msg}

            ws.onerror {|e| @onerror.call(e)}

            ws.onclose {@onclose.call(ws); @channel1.unsubscribe sid}
          end
          EM.add_timer(0.1) {ready = true}
        end
      end
      sleep 0.2 until ready
      @websocket
    end

    def subscribe(*args, &block)
      @channel2.subscribe(*args, &block)
    end

    def unsubscribe(*args, &block)
      @channel2.unsubscribe(*args, &block)
    end

    def push(*args)
      @channel1.push(*args)
    end

    def send(*args)
      @channel1.push(*args)
    end

    def pop(*args)
      @channel2.pop(*args)
    end

    def recv(*args)
      @channel2.pop(*args)
    end

    def onopen(&block)
      @onopen = block
    end

    def onmessage(&block)
      @onmessage = block
    end

    def onerror(&block)
      @onerror = block
    end

    def onclose(&block)
      @onclose = block
    end

    def method_missing(method, *args, &block)
      if @_scope and @_scope.respond_to? :method
        @_scope.__send__ method, *args, &block
      else
        super
      end
    end

    def _(*args, &block)
      if block or args.length > 1 
        begin
          builder = Wunderbar::JsonBuilder.new(Struct.new(:params).new({}))
          builder._! self
          builder._(*args, &block)
        rescue Exception => e
          self << {:type=>'stderr', :line=>e.inspect}
        end
      elsif args.length == 1
        @channel1.push(args.first.to_json)
      else
        self
      end
    end

    def <<(value)
      @channel1.push(value.to_json)
    end

    def system(command)
      Open3.popen3(command) do |pin, pout, perr|
        _ :type=>:stdin, :line=>command
        [
          Thread.new do
            pout.sync=true
            _ :type=>:stdout, :line=>pout.readline.chomp until pout.eof?
          end,
          Thread.new do
            perr.sync=true
            _ :type=>:stderr, :line=>perr.readline.chomp until perr.eof?
          end,
          Thread.new { pin.close }
        ].each {|thread| thread.join}
      end
    end

    def complete=(value)
      @channel1.push :shutdown if value
      @complete = value
    end

    def close
      @channel1.unsubscribe @memory_channel if @memory_channel
      EM::WebSocket.stop
      websocket.join    
    end
  end

  def self.websocket(opts={}, &block)
    opts = {:port => opts} if Fixnum === opts
    port = opts[:port]
    buffer = opts.fetch(:buffer,1)

    if not port
      socket = TCPServer.new(0)
      port = Socket.unpack_sockaddr_in(socket.getsockname).first
      socket.close
    end

    sock1 = nil

    proc = Proc.new do
      begin
        channel = Wunderbar::Channel.new(port, buffer, opts[:locals])
        if sock1
          sock1.send('x',0)
          sock1.close
        end
        channel.instance_eval(&block)
      rescue Exception => exception
        channel._ :type=>:stderr, :line=>exception.inspect
        exception.backtrace.each do |frame| 
          next if Wunderbar::CALLERS_TO_IGNORE.any? {|re| frame =~ re}
          channel._ :type=>:stderr, :line=>"  #{frame}"
        end
      ensure
        if channel
          channel.complete = true
          sleep 5
          sleep 60 unless channel.connected or opts[:sync]
          channel.close
        end
      end
    end

    if opts[:sync]
      instance_eval &proc
    else
      sock1, sock2 = UNIXSocket.pair
      submit(&proc)
      sleep 0.3 while sock2.recv(1) != 'x'
      sock2.close
    end

    port
  end
end
