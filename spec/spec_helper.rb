# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'fileutils'
require 'minitest/autorun'
require 'minitest/rg'
require 'yaml'

require_relative 'test_load_all'

def wipe_database
  app.DB[:action_logs].delete
  app.DB[:face_records].delete
  app.DB[:images].delete
  FileUtils.rm_rf(Dir.glob("#{FaceCloak::Image::STORAGE_DIR}/*"))
end

DATA = {} # rubocop:disable Style/MutableConstant
DATA[:images] = YAML.safe_load_file('db/seeds/image_seeds.yml')
DATA[:face_records] = YAML.safe_load_file('db/seeds/face_record_seeds.yml')
DATA[:action_logs] = YAML.safe_load_file('db/seeds/action_log_seeds.yml')

def seed_attributes(record)
  record.except('id')
end
