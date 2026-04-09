# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'minitest/rg'
require 'rack/test'
require 'yaml'

require_relative '../app/controllers/app'
require_relative '../app/models/face_record'

def app
  FaceCloak::Api
end

DATA = YAML.safe_load_file('db/seeds/face_record_seeds.yml')

# rubocop:disable Metrics/BlockLength
describe 'Test FaceCloak Web API' do
  include Rack::Test::Methods

  before do
    FileUtils.rm_rf(FaceCloak::FaceRecord::STORE_PATH)
    FaceCloak::FaceRecord.setup
    DATA.each { |attributes| FaceCloak::FaceRecord.new(attributes).save }
  end

  it 'should find the root route' do
    get '/'
    _(last_response.status).must_equal 200
  end

  describe 'Handle face records' do
    it 'HAPPY: should create a default blur face record' do
      face_record = FaceCloak::FaceRecord.all.detect do |record|
        record.image_id == 'image_1' &&
          record.assigned_user_id.nil? &&
          record.responded_at.nil?
      end

      _(face_record).wont_be_nil
      _(face_record.cloak_type).must_equal 'blur'
      _(face_record.updated_at).must_be_nil
      _(face_record.effective_cloak_type).must_equal 'blur'
    end

    it 'HAPPY: should track assignment and response values from seeds' do
      face_record = FaceCloak::FaceRecord.all.detect do |record|
        record.image_id == 'image_1' &&
          record.assigned_user_id == 'user_123'
      end

      _(face_record).wont_be_nil
      _(face_record.assigned_at).must_equal '2026-04-09T10:30:00+08:00'
      _(face_record.responded_at).must_equal '2026-04-09T11:00:00+08:00'
      _(face_record.cloak_type).must_equal 'comic'
      _(face_record.effective_cloak_type).must_equal 'comic'
      _(face_record.updated_at).must_equal '2026-04-09T11:00:00+08:00'
    end

    it 'HAPPY: should allow unveil as a cloak type' do
      face_record = FaceCloak::FaceRecord.all.detect do |record|
        record.image_id == 'image_2' &&
          record.assigned_user_id == 'user_456'
      end

      _(face_record).wont_be_nil
      _(face_record.cloak_type).must_equal 'unveil'
      _(face_record.effective_cloak_type).must_equal 'unveil'
    end

    it 'HAPPY: should be able to get list of all face records' do
      get '/api/v1/face_records'
      result = JSON.parse(last_response.body)

      _(last_response.status).must_equal 200
      _(result.count).must_equal DATA.count
    end

    it 'HAPPY: should be able to get details of a single face record' do
      id = Dir.glob("#{FaceCloak::FaceRecord::STORE_PATH}/*.txt").first.split(%r{[/.]})[-2]

      get "/api/v1/face_records/#{id}"
      result = JSON.parse(last_response.body)

      _(last_response.status).must_equal 200
      _(result['id']).must_equal id
    end

    it 'SAD: should return error if unknown face record requested' do
      get '/api/v1/face_records/foobar'

      _(last_response.status).must_equal 404
    end
  end
end
# rubocop:enable Metrics/BlockLength
