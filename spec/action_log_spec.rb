# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Test ActionLog Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
    @img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))
    # After Image.create, 2 face records are automatically created with 'create' logs
    # We pick one existing face for testing
    @face = @img.face_records.first
  end

  it 'HAPPY: should be able to get action logs for a face record' do
    # @face already has 1 'create' log from auto-detection
    @face.add_action_log(action: 'assign', actor_id: 'admin')
    @face.add_action_log(action: 'respond', actor_id: 'admin')

    get "api/v1/face_records/#{@face.id}/logs"
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_equal 3 # 1 auto + 2 manual
  end

  it 'HAPPY: should be able to get action logs for an image' do
    # @img already has 2 face records with 2 logs
    # We add a 3rd face manually (which triggers NO auto-log because it's not through Image.create hook)
    third_face = FaceCloak::FaceRecord.create(image_id: @img.id)
    @face.add_action_log(action: 'assign', actor_id: 'admin')
    third_face.add_action_log(action: 'assign', actor_id: 'admin')

    get "api/v1/images/#{@img.id}/logs"
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_equal 4 # 2 auto logs + 2 manual logs
  end

  it 'SAD: should return error if unknown image logs requested' do
    get '/api/v1/images/missing-image/logs'

    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should validate allowed actions (Model Unit Test)' do
    log = FaceCloak::ActionLog.new(face_record_id: @face.id, actor_id: 'a', action: 'create')
    _(log.valid?).must_equal true
  end

  it 'HAPPY: should create an unassign log through the API' do
    @face.assign_to('user_1')
    @face.save_changes

    header 'X-Actor-Id', @img.owner_id
    delete "api/v1/face_records/#{@face.id}/assignment"
    _(last_response.status).must_equal 200

    _(FaceCloak::ActionLog.where(face_record_id: @face.id, action: 'unassign').count).must_equal 1
  end

  it 'SAD: should reject invalid actions (Model Unit Test)' do
    log = FaceCloak::ActionLog.new(face_record_id: @face.id, actor_id: 'a', action: 'hack')
    _(log.valid?).must_equal false
  end
end
