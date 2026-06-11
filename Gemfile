# frozen_string_literal: true

source 'https://rubygems.org'

ruby File.read('.ruby-version').strip

# Web API
gem 'aws-sdk-s3', '~> 1.0'
gem 'base64'
gem 'figaro'
gem 'google-genai'
gem 'json'
gem 'jwt', '~> 3.2'
gem 'logger', '~> 1.0'
gem 'mime-types'
gem 'puma', '~> 7.2', '>= 7.2.1'
gem 'rake'
gem 'rest-client', '~> 2.1'
gem 'roda', '~> 3.0'
gem 'sequel'

# Security
gem 'rbnacl', '~> 7.1'

# Database
group :development, :test do
  gem 'hirb'
  gem 'rack-test'
  gem 'sequel-seed'
  gem 'sqlite3', '~> 2.0'
end

group :production do
  gem 'pg', '~> 1.5'
end

# Testing
group :test do
  gem 'minitest'
  gem 'minitest-rg'
  gem 'webmock'
end

# Development
group :development do
  gem 'bundler-audit'
  gem 'pry'
  gem 'rerun'
  gem 'rubocop'
  gem 'rubocop-minitest'
  gem 'rubocop-performance'
  gem 'rubocop-rake'
  gem 'rubocop-sequel'
end
