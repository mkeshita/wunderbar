require 'wunderbar'
require 'ruby2js'

# convert script blocks to JavaScript.  If binding_of_caller is available,
# full access to all variables defined in the callers scope may be made
# by execute strings (`` or %x()).

module Wunderbar
  class ScriptNode
    attr_accessor :block, :binding
    def serialize(options, result, indent)
      @block ||= nil
      if @block and @children.empty? and not @text
        width = options[:width]
        width -= indent.to_s.length if width
        opts = {binding: @binding, width: width}
        opts = {**@attrs.delete(:options), **opts} if @attrs[:options]
        @text = Ruby2JS.convert(@block, opts).to_s
      end
      super
    end
  end

  class HtmlMarkup
    def _script(*args, &block)
      if block
        node = super(*args, &nil).node?
        node.block = block
        if binding.respond_to? :of_caller
          # provided by require 'binding_of_caller'
          node.binding = binding.of_caller(1)
        else
          node.binding = binding
        end
        node
      else
        super
      end
    end
  end
end

module Wunderbar
  module API
    def _js(*args, &block)
      Wunderbar.ruby2js(*args, &block)
    end
  end

  def self.ruby2js(*args, &block)
    callback = Proc.new do |scope, callback_args, callback_block| 
      ruby2js(scope, *callback_args, &callback_block)
    end
    @queue << [callback, args, block]
  end
  
  class CGI
    def ruby2js(scope, *args, &block)
      headers = { 'type' => 'application/javascript', 'charset' => 'UTF-8' }

      begin
        output = Ruby2JS.convert(block) + "\n"
      rescue Parser::SyntaxError => exception
        headers['status'] = Wunderbar::ServerError.text
        location = exception.diagnostic.location
        output = "// Syntax Error: line #{location.line}, " +
          "column: #{location.column}\n#{exception}\n"
      rescue ::Exception => exception
        headers['status'] = Wunderbar::ServerError.text
        output = "// Internal Server Error: #{exception}\n"
        exception.backtrace.each do |frame| 
          next if CALLERS_TO_IGNORE.any? {|re| frame =~ re}
          output += "  #{frame}\n"
        end
      end

      out?(scope, headers) { output }
    end
  end

  module Template
    module Js
      def self.ext; ['js.rb', :_js]; end
      def self.mime; 'application/javascript'; end

      def evaluate(scope, locals, &block)
        scope.content_type self.class.default_mime_type, charset: 'utf-8'
        begin
          Ruby2JS.convert(block ? block : data, ivars: locals, file: file).to_s
        rescue Parser::SyntaxError => exception
          scope.response.status = Wunderbar::ServerError.status
          location = exception.diagnostic.location
          "Syntax Error: line #{location.line}, column: #{location.column}" +
            "\n#{exception}\n"
        rescue Exception => exception
          scope.response.status = Wunderbar::ServerError.status
          output = "Internal Server Error: #{exception}\n"
          exception.backtrace.each do |frame| 
            next if CALLERS_TO_IGNORE.any? {|re| frame =~ re}
            output += "  #{frame}\n"
          end
          output
        end
      end
    end

    register Js if respond_to? :register
  end
end

