# frozen_string_literal: true

require './require_app'
require 'rake/testtask'
require 'sequel'
require 'fileutils'

require_app :config

task default: :spec

# spec tasks
desc 'Tests API specs only'
task :api_spec do
  sh 'ruby spec/integration/api_spec.rb'
end

desc 'Run all specs'
Rake::TestTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.warning = false
end

# style
desc 'Run rubocop on tested code'
task :style do
  sh 'rubocop .'
end

# security
desc 'Update vulnerabilities list and audit gems'
task :audit do
  sh 'bundle audit check --update'
end

desc 'Checks for release'
task release_check: %i[spec style audit] do
  puts "\nReady for release!"
end

# utility tasks
task :print_env do # rubocop:disable Rake/Desc
  puts "Environment: #{ENV['RACK_ENV'] || 'development'}"
end

desc 'Run application console (pry)'
task console: :print_env do
  sh 'pry -r ./spec/test_load_all'
end

# run server
desc 'Run puma server'
task :puma do
  port = ENV.fetch('PORT', '3000')
  sh "bundle exec puma -p #{port}"
end

desc 'Run puma with automatic restart on file changes'
task :rerun do
  port = ENV.fetch('PORT', '3000')
  sh "bundle exec rerun --no-notify --background -- puma -p #{port}"
end

# database
namespace :db do
  task :load do # rubocop:disable Rake/Desc
    require_app(nil) # load nothing by default
    require 'sequel'

    Sequel.extension :migration
    @app = FaceCloak::Api
  end

  task :load_models do # rubocop:disable Rake/Desc
    require_app(%w[models services])
  end

  desc 'Run migrations'
  task migrate: %i[load print_env] do
    puts 'Migrating database to latest'
    Sequel::Migrator.run(@app.DB, 'db/migrations')
  end

  task reset_seeds: :load_models do # rubocop:disable Rake/Desc
    db = FaceCloak::Api.DB
    db[:schema_seeds].delete if db.tables.include?(:schema_seeds)
    FaceCloak::Account.dataset.destroy
  end

  desc 'Run database seeds'
  task seed: %i[load load_models] do
    puts 'Seeding database'
    require 'sequel/extensions/seed'
    Sequel::Seed.setup(@app.environment)
    Sequel.extension :seed
    Sequel::Seeder.apply(@app.DB, 'db/seeds')
  end

  desc 'Destroy data in database; maintain tables'
  task delete: :load_models do
    FaceCloak::ActionLog.dataset.delete
    FaceCloak::FaceRecord.dataset.delete
    FaceCloak::Image.dataset.delete
    puts 'Deleted all data in database'
  end

  desc 'Delete dev or test database file'
  task drop: :load do
    if @app.environment == :production
      puts 'Cannot wipe production database!'
      return
    end

    db_filename = @app.DB.opts[:database]
    @app.DB.disconnect
    FileUtils.rm_f(db_filename)

    # Clear all files in storage and cache
    FileUtils.rm_rf(Dir.glob('db/local/storage/*'))
    puts 'Cleared db/local/storage/'
  end

  desc 'Bootstrap an admin role for an existing account: ADMIN_USERNAME=<username>'
  task bootstrap_admin: :load_models do
    username = ENV.fetch('ADMIN_USERNAME', nil).to_s.strip
    abort 'ADMIN_USERNAME=<username> required' if username.empty?

    ensure_role = lambda do |name|
      FaceCloak::Role.first(name:) || FaceCloak::Role.create(name:)
    rescue Sequel::UniqueConstraintViolation
      FaceCloak::Role.first(name:)
    end

    role_names = %w[admin member]
    role_names.each { |name| ensure_role.call(name) }
    puts "Roles ensured: #{role_names.join(', ')}"

    account = FaceCloak::Account.first(username:)
    abort "Account not found: #{username}" unless account

    admin_role = FaceCloak::Role.first(name: 'admin')
    if account.system_roles_dataset.where(name: 'admin').any?
      puts "- Account #{username} already has 'admin'"
    else
      account.add_system_role(admin_role)
      puts "+ Granted 'admin' to #{username}"
    end
  end

  desc 'Recreate a brand-new empty dev/test database'
  task reset: :load do
    if @app.environment == :production
      puts 'Cannot reset production database!'
      return
    end

    db_filename = @app.DB.opts[:database]
    @app.DB.disconnect
    FileUtils.rm_f(db_filename)
    FileUtils.rm_rf(Dir.glob('db/local/storage/*'))
    puts "Deleted #{db_filename}"
    puts 'Cleared db/local/storage'

    Sequel::Migrator.run(@app.DB, 'db/migrations')
    puts 'Migrated database to latest'
  end
end

desc 'Delete all data and reseed'
task reseed: %i[db:reset_seeds db:seed]

namespace :newkey do
  desc 'Create sample cryptographic key for database'
  task :db do
    require './app/lib/secure_db'
    puts "DB_KEY: #{FaceCloak::SecureDB.generate_key}"
  end

  desc 'Create sample cryptographic key for HMAC lookup hashing'
  task :hash do
    require './app/lib/secure_db'
    puts "HASH_KEY: #{FaceCloak::SecureDB.generate_key}"
  end
end
