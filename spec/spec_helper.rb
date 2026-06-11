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
  FileUtils.rm_rf(Dir.glob("#{FaceCloak::ImageStorage.local_root}/*"))
  FileUtils.rm_rf(Dir.glob("#{FaceCloak::ImageStorage::DOWNLOAD_CACHE_DIR}/*"))
end

def create_account(username, email, password)
  FaceCloak::CreateAccount.call(account_data: { username:, email:, password: })
end

def grant_admin(account)
  role = FaceCloak::Role.first(name: 'admin') || FaceCloak::Role.create(name: 'admin')
  account.add_system_role(role) unless account.system_roles_dataset.where(id: role.id).any?
  account
end

def auth_header(account)
  auth_header_with_scope(account, FaceCloak::AuthScope::FULL)
end

def auth_header_with_scope(account, scope)
  envelope = JSON.parse(account.to_json)
  envelope['attributes'] = envelope['attributes'].merge('id' => account.id)
  token = FaceCloak::AuthToken.new(envelope, scope: FaceCloak::AuthScope.new(scope)).to_s
  { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
end

def auth_request_header(account)
  auth_header(account).merge('CONTENT_TYPE' => 'application/json')
end

def signed_json(data)
  FaceCloak::SignedRequest.sign(data).to_json
end

def setup_mailgun_env
  ENV['MAILGUN_API_KEY'] ||= 'test-mailgun-api-key'
  ENV['MAILGUN_API_BASE_URL'] ||= 'https://api.mailgun.test'
  ENV['MAILGUN_DOMAIN'] ||= 'mg.example.test'
  ENV['MAILGUN_FROM_EMAIL'] ||= 'postmaster@mg.example.test'
  ENV['MAILGUN_FROM_NAME'] ||= 'FaceCloak'
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
