# frozen_string_literal: true

source 'https://rubygems.org'

ruby '4.0.1'

# Web API
gem 'base64'
gem 'figaro'
gem 'json'
gem 'logger', '~> 1.0'
gem 'puma', '~> 7.0'
gem 'rake'
gem 'roda', '~> 3.0'
gem 'sequel'

# Security
gem 'rbnacl', '~> 7.1'

# Database
group :development, :test do
  gem 'bundler-audit'
  gem 'hirb'
  gem 'rubocop'
  gem 'rubocop-minitest'
  gem 'rubocop-performance'
  gem 'rubocop-rake'
  gem 'rubocop-sequel'
  gem 'sqlite3', '~> 2.0'
end

# Testing
group :test do
  gem 'minitest'
  gem 'minitest-rg'
  gem 'rack-test'
end

# Development
group :development do
  gem 'pry'
  gem 'rerun'
end
