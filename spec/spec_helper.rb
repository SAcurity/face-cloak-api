# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'fileutils'
require 'minitest/autorun'
require 'minitest/rg'
require 'yaml'

require_relative 'test_load_all'

def wipe_database # rubocop:disable Metrics/AbcSize
  app.DB[:action_logs].delete
  app.DB[:face_records].delete
  app.DB[:accounts_images].delete
  app.DB[:images].delete
  app.DB[:accounts_roles].delete
  app.DB[:accounts].delete
  app.DB[:roles].delete
  FileUtils.rm_rf(Dir.glob("#{FaceCloak::Image::STORAGE_DIR}/*"))
end

def create_account(username, email, password)
  FaceCloak::CreateAccount.call(account_data: { username:, email:, password: })
end

DATA = {} # rubocop:disable Style/MutableConstant
DATA[:images] = YAML.safe_load_file('db/seeds/image_seeds.yml')
DATA[:face_records] = YAML.safe_load_file('db/seeds/face_record_seeds.yml')
DATA[:action_logs] = YAML.safe_load_file('db/seeds/action_log_seeds.yml')

def seed_attributes(record)
  record.dup.tap do |h|
    %w[id created_at updated_at assigned_at responded_at].each { |k| h.delete(k) }
  end
end
