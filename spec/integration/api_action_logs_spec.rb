# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test ActionLog API Integration' do
  include Rack::Test::Methods

  before do
    wipe_database
    @img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))
    @face = @img.face_records.first
  end

  it 'HAPPY: should be able to get action logs for a face record as owner or assignee' do
    header 'X-Actor-Id', @img.owner_id
    get "api/v1/face_records/#{@face.id}/logs"
    _(last_response.status).must_equal 200

    @face.assign_to('reviewer_mina')
    @face.save_changes
    header 'X-Actor-Id', 'reviewer_mina'
    get "api/v1/face_records/#{@face.id}/logs"
    _(last_response.status).must_equal 200
  end

  it 'SAD: should NOT allow strangers to see face record logs' do
    header 'X-Actor-Id', 'stranger'
    get "api/v1/face_records/#{@face.id}/logs"
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to get action logs for an image as owner' do
    header 'X-Actor-Id', @img.owner_id
    get "api/v1/images/#{@img.id}/logs"
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_equal 2 # 2 auto logs from upload
  end

  it 'SAD: should NOT allow non-owners to see image logs' do
    header 'X-Actor-Id', 'stranger'
    get "api/v1/images/#{@img.id}/logs"
    _(last_response.status).must_equal 403
  end

  it 'SAD: should return error if unknown image logs requested' do
    header 'X-Actor-Id', @img.owner_id
    get '/api/v1/images/missing-image/logs'
    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should create an unassign log through the API' do
    @face.assign_to('user_1')
    @face.save_changes

    header 'X-Actor-Id', @img.owner_id
    delete "api/v1/face_records/#{@face.id}/assignment"
    _(last_response.status).must_equal 200

    _(FaceCloak::ActionLog.where(face_record_id: @face.id, action: 'unassign').count).must_equal 1
  end
end
