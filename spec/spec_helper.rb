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
  app.DB[:roles].delete
  app.DB[:accounts].delete
  # Clear physical storage
  FileUtils.rm_rf(Dir.glob("#{FaceCloak::Image::STORAGE_DIR}/*"))
end

def create_account(username, email, password)
  FaceCloak::CreateAccount.call(account_data: { username:, email:, password: })
end

DATA = {} # rubocop:disable Style/MutableConstant
DIR = 'db/seeds'
DATA[:images]       = YAML.load_file("#{DIR}/image_seeds.yml")
DATA[:face_records] = YAML.load_file("#{DIR}/face_record_seeds.yml")
DATA[:assignments]  = YAML.load_file("#{DIR}/assignments_seed.yml")
DATA[:responses]    = YAML.load_file("#{DIR}/responses_seed.yml")

def seed_attributes(record)
  return {} unless record

  # Keep only the keys that are not system-managed
  excluded_keys = %w[id created_at updated_at assigned_at responded_at owner_username image_file_name username]
  record.except(*excluded_keys)
end
