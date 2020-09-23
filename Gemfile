source "https://rubygems.org"

branch = ENV.fetch("SOLIDUS_BRANCH", "master")
gem "solidus", git: "https://github.com/solidusio/solidus", branch: branch

if branch == "master" || branch >= "v2.0"
  gem "rails-controller-testing", group: :test
end

# hacks to speed up bundler resolution
if branch == "master" || branch >= "v2.3"
  gem "rails", "~> 6.0"
elsif branch >= "v2.0"
  gem "rails", "~> 5.0.7"
else
  gem "rails", "~> 4.2.10"
end

if ENV["DB"] == "mysql"
  gem "mysql2", "~> 0.4.10"
else
  gem "pg", "> 0.21"
end

gem "chromedriver-helper" if ENV["CI"]

group :development, :test do
  gem "byebug"
  gem "capybara"
  gem "ffaker"
  gem "pry-rails"
  gem "puma", "~> 4.3"
  gem "rspec-rails"
  gem "rubocop"
  gem "solidus_dev_support", git: "https://github.com/solidusio/solidus_dev_support", branch: "master"
  gem "webdrivers"

  gem "factory_bot"
end

gemspec
