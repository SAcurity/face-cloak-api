# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'rack/test'

require_relative '../app/controllers/app'

# rubocop:disable Metrics/BlockLength
describe FaceCloak::Api do
  include Rack::Test::Methods

  def app
    FaceCloak::Api.freeze.app
  end

  before do
    FileUtils.rm_rf(File.join(__dir__, '../db/local'))
    FaceCloak::FaceRecord.setup
  end

  it 'creates a face record with blur as the default cloak type' do
    face_record = FaceCloak::FaceRecord.create('image_id' => 'image_1')

    _(face_record.image_id).must_equal 'image_1'
    _(face_record.cloak_type).must_equal 'blur'
    _(face_record.responded_at).must_be_nil
    _(face_record.updated_at).must_be_nil
    _(face_record.effective_cloak_type).must_equal 'blur'
  end

  it 'tracks assignment, response, and updated time per face record' do
    face_record = FaceCloak::FaceRecord.create('image_id' => 'image_1')

    assigned_face = face_record.assign_to('user_123', at: '2026-04-09T10:00:00+08:00')
    assigned_face.save

    _(assigned_face.assigned_user_id).must_equal 'user_123'
    _(assigned_face.assigned_at).must_equal '2026-04-09T10:00:00+08:00'
    _(assigned_face.updated_at).must_be_nil

    responded_face = face_record.respond_with('comic', at: '2026-04-09T11:00:00+08:00')
    responded_face.save
    stored_face = FaceCloak::FaceRecord.find(face_record.id)

    _(responded_face.responded_at).must_equal '2026-04-09T11:00:00+08:00'
    _(responded_face.cloak_type).must_equal 'comic'
    _(stored_face.cloak_type).must_equal 'comic'
    _(stored_face.effective_cloak_type).must_equal 'comic'
    _(stored_face.updated_at).must_equal '2026-04-09T11:00:00+08:00'
  end

  it 'allows assigned users to remove masking with unveil' do
    face_record = FaceCloak::FaceRecord.create('image_id' => 'image_1')

    face_record.assign_to('user_123', at: '2026-04-09T10:00:00+08:00').save
    face = face_record.respond_with('unveil', at: '2026-04-09T12:00:00+08:00')
    face.save

    _(face.cloak_type).must_equal 'unveil'
    _(face.effective_cloak_type).must_equal 'unveil'
    _(face.updated_at).must_equal '2026-04-09T12:00:00+08:00'
  end

  it 'keeps updated_at as nil when the record has never been updated' do
    face_record = FaceCloak::FaceRecord.new(
      'image_id' => 'image_1',
      'assigned_user_id' => nil,
      'assigned_at' => nil,
      'responded_at' => nil,
      'cloak_type' => 'blur',
      'updated_at' => nil
    )

    _(face_record.updated_at).must_be_nil
  end

  it 'keeps the first responded_at when the cloak type changes again' do
    face_record = FaceCloak::FaceRecord.create('image_id' => 'image_1')

    face_record.respond_with('comic', at: '2026-04-09T11:00:00+08:00').save
    face_record.respond_with('unveil', at: '2026-04-09T12:00:00+08:00').save

    _(face_record.responded_at).must_equal '2026-04-09T11:00:00+08:00'
    _(face_record.updated_at).must_equal '2026-04-09T12:00:00+08:00'
    _(face_record.cloak_type).must_equal 'unveil'
  end
end
# rubocop:enable Metrics/BlockLength
