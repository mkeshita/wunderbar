require 'minitest/autorun' 

begin
  require 'action_controller'
  require 'wunderbar/rails'
  require 'wunderbar'

  # Workaround for http://stackoverflow.com/questions/20361428/rails-i18n-validation-deprecation-warning
  I18n.enforce_available_locales = true if I18n.respond_to? :enforce_available_locales=
  
  class RailsTestController < ActionController::Base
    append_view_path File.expand_path(File.join File.dirname(__FILE__), 'views')

    def index
      @products = [Struct.new(:title,:quantity).new('Wunderbar',1_000)]
      render :index, :layout => 'application'
    end
  end

  WunderbarTestRoutes = ActionDispatch::Routing::RouteSet.new

  WunderbarTestRoutes.draw do
    resources :products
    get :index, controller: 'rails_test'
  end

  # http://stackoverflow.com/questions/3546107/testing-view-helpers#answer-3802286
  require 'ostruct'
  module ActionController::UrlFor
    def _routes
      helpers = OpenStruct.new
      helpers.url_helpers = Module.new
      helpers
    end
  end

  if ActiveSupport::TestCase.respond_to? :test_order
    ActiveSupport::TestCase.test_order = :sorted
  end

rescue LoadError =>  exception
  ActionController = Module.new do
    const_set :TestCase, Class.new(Minitest::Test) {
      define_method(:default_test) {}
      define_method(:skip_reason) do
        exception.inspect
      end
    }
  end
end

class WunderbarOnRailsTest < ActionController::TestCase

  def setup
    return unless defined? Rails
    @request = ActionDispatch::TestRequest.create
    @response = ActionDispatch::TestResponse.create
    @controller = RailsTestController.new
    @routes = WunderbarTestRoutes
  end

  def skip_html_success # FIXME skip as meta tag is escaped
    get :index
    assert_response :success
    assert_select 'title', 'From Layout'
    assert_select 'meta[content="authenticity_token"]'
    assert_select 'meta[name="csrf-token"]'
    assert_select 'td', 'Wunderbar'
    assert_select 'td', '1 Thousand'
  end

  def test_json_success
    get :index, :format => 'json'
    assert_response :success
    response = JSON.parse(@response.body)
    assert_equal 'Wunderbar', response['products'][0]['title']
    assert_equal 1_000, response['products'][0]['quantity']
  end

  if superclass.superclass == Minitest::Test
    remove_method :setup
    attr_accessor :default_test
    public_instance_methods.grep(/^test_/).each do |method|
      remove_method method
    end
    unless instance_methods.grep(/^skip$/).empty?
      define_method(:test_rails) { skip skip_reason }
    end
  end
end
