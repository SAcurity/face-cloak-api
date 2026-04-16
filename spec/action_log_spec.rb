# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Test ActionLog Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
    @img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))
    @face = FaceCloak::FaceRecord.create(image_id: @img.id)
  end

  it 'HAPPY: should be able to get action logs for a face record' do
    @face.add_action_log(action: 'create', actor_id: 'admin')
    @face.add_action_log(action: 'assign', actor_id: 'admin')

    get "api/v1/face_records/#{@face.id}/logs"
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_equal 2
  end

  it 'HAPPY: should be able to get action logs for an image' do
    second_face = FaceCloak::FaceRecord.create(image_id: @img.id)
    @face.add_action_log(action: 'create', actor_id: 'admin')
    second_face.add_action_log(action: 'assign', actor_id: 'admin')

    get "api/v1/images/#{@img.id}/logs"
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_equal 2
  end

  it 'SAD: should return error if unknown image logs requested' do
    get '/api/v1/images/99999/logs'

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
