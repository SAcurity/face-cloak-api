# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test ActionLog API Integration' do
  include Rack::Test::Methods

  before do
    wipe_database
    @owner = create_account('alice', 'alice@example.com', 'password123')
    @assignee = create_account('bob', 'bob@example.com', 'password123')
    @stranger = create_account('charlie', 'charlie@example.com', 'password123')
    @img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge('owner_id' => @owner.id))
    @face = @img.face_records.first
  end

  it 'HAPPY: should be able to get action logs for a face record as owner or assignee' do
    header 'X-Actor-Id', @owner.id
    get "api/v1/face_records/#{@face.id}/logs"
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_be :>=, 1
  end

  it 'SAD: should NOT allow strangers to see face record logs' do
    header 'X-Actor-Id', @stranger.id
    get "api/v1/face_records/#{@face.id}/logs"
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to get action logs for an image as owner' do
    header 'X-Actor-Id', @owner.id
    get "api/v1/images/#{@img.id}/logs"
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    # 2 faces * 1 create log each
    _(result['data'].count).must_equal 2
  end

  it 'SAD: should NOT allow non-owners to see image logs' do
    header 'X-Actor-Id', @stranger.id
    get "api/v1/images/#{@img.id}/logs"
    _(last_response.status).must_equal 403
  end

  it 'SAD: should return error if unknown image logs requested' do
    header 'X-Actor-Id', @owner.id
    get 'api/v1/images/missing-image/logs'
    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should create an unassign log through the API' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    header 'X-Actor-Id', @owner.id
    delete "api/v1/face_records/#{face.id}/assignment"
    _(last_response.status).must_equal 200

    get "api/v1/face_records/#{face.id}/logs"
    result = JSON.parse(last_response.body)
    actions = result['data'].map { |l| l['attributes']['action'] }
    _(actions).must_include 'unassign'
  end

  it 'SECURITY: should prevent SQL injection in image logs lookup' do
    evil_id = CGI.escape("' OR 1=1 --")
    header 'X-Actor-Id', @owner.id
    get "api/v1/images/#{evil_id}/logs"
    _(last_response.status).must_equal 404
  end
end
