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
desc 'Run puma with automatic restart on file changes'
task :rerun do
  sh 'bundle exec rerun --no-notify --background -- puma'
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
    require_app('models')
  end

  desc 'Run migrations'
  task migrate: %i[load print_env] do
    puts 'Migrating database to latest'
    Sequel::Migrator.run(@app.DB, 'db/migrations')
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
    puts "Deleted #{db_filename}"
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
