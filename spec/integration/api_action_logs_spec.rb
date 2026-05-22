# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test ActionLog API Integration' do
  include Rack::Test::Methods

  before do
    wipe_database
    @owner = create_account('alice', 'alice@example.com', 'password123')
    @assignee = create_account('bob', 'bob@example.com', 'password123')
    @stranger = create_account('charlie', 'charlie@example.com', 'password123')
    @req_header = auth_request_header(@owner)
    @img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge('owner_id' => @owner.id))
    # Ensure at least one face record for tests
    if @img.face_records.empty?
      FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
      @img.refresh
    end
    @face = @img.face_records.first
  end

  it 'HAPPY: should be able to get action logs for a face record as owner or assignee' do
    get "api/v1/face_records/#{@face.id}/logs", nil, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_be :>=, 1
  end

  it 'HAPPY: should be able to get action logs for an image as owner' do
    get "api/v1/images/#{@img.id}/logs", nil, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    # At least the create logs for existing faces
    _(result['data'].count).must_be :>=, 1
  end

  it 'HAPPY: should create an unassign log through the API' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    delete "api/v1/face_records/#{face.id}/assignment", nil, @req_header
    _(last_response.status).must_equal 200

    get "api/v1/face_records/#{face.id}/logs", nil, @req_header
    result = JSON.parse(last_response.body)
    actions = result['data'].map { |l| l['attributes']['action'] }
    _(actions).must_include 'unassign'
  end
end
