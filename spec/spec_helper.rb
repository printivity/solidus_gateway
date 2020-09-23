require "simplecov"
SimpleCov.start("rails")

require "capybara/rspec"

ENV["RAILS_ENV"] ||= "test"

require File.expand_path("../dummy/config/environment.rb",  __FILE__)


require "spree/testing_support/preferences"

require "solidus_dev_support/rspec/feature_helper"
require "solidus_dev_support/testing_support/preferences"


Webdrivers::Chromedriver.update

Capybara.register_driver(:selenium_chrome_headless) do |app|
  browser_options = ::Selenium::WebDriver::Chrome::Options.new
  browser_options.args << "--window-size=1024,768"
  browser_options.args << "--enable-features=NetworkService,NetworkServiceInProcess"
  browser_options.args << "--no-sandbox"
  browser_options.args << "--disable-dev-shm-usage"

  browser_options.args << "--headless"
  browser_options.args << "--disable-gpu"

  client = Selenium::WebDriver::Remote::Http::Default.new
  client.read_timeout = 90

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    http_client: client,
    options: browser_options
  )
end

Capybara.javascript_driver = :selenium_chrome_headless

require "braintree"

Dir[File.join(File.dirname(__FILE__), "support/**/*.rb")].each { |f| require f }

require "rspec/rails"
RSpec.configure do |config|
  config.infer_spec_type_from_file_location!

  config.before :suite do
    # Don't log Braintree to STDOUT.
    Braintree::Configuration.logger = Logger.new("spec/dummy/tmp/log")
  end

  FactoryBot.find_definitions
end
