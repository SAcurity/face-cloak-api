# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Test FaceRecord Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
    @img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))
  end

  it 'HAPPY: should be able to get list of all face records' do
    FaceCloak::FaceRecord.create(image_id: @img.id, cloak_type: 'blur')
    FaceCloak::FaceRecord.create(image_id: @img.id, cloak_type: 'comic')

    get 'api/v1/face_records'
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_equal 2
  end

  it 'HAPPY: should be able to get details of a single face record' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    get "api/v1/face_records/#{face.id}"
    _(last_response.status).must_equal 200
  end

  it 'SAD: should return error if unknown face record requested' do
    get '/api/v1/face_records/99999'

    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should be able to create a new face record as owner' do
    new_face = { image_id: @img.id, cloak_type: 'pixelate' }

    header 'X-Actor-Id', @img.owner_id
    post 'api/v1/face_records', new_face.to_json
    _(last_response.status).must_equal 201
  end

  it 'SAD: should NOT be able to create a face record if not owner' do
    new_face = { image_id: @img.id, cloak_type: 'blur' }

    header 'X-Actor-Id', 'stranger'
    post 'api/v1/face_records', new_face.to_json
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to assign a face record as owner' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    assign_data = { assigned_user_id: 'new_user' }

    header 'X-Actor-Id', @img.owner_id
    post "api/v1/face_records/#{face.id}/assignment", assign_data.to_json
    _(last_response.status).must_equal 201
  end

  it 'SAD: should NOT be able to assign a face record if not owner' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    assign_data = { assigned_user_id: 'new_user' }

    header 'X-Actor-Id', 'stranger'
    post "api/v1/face_records/#{face.id}/assignment", assign_data.to_json
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to unassign a face record as owner' do
    face = FaceCloak::FaceRecord.create(
      image_id: @img.id,
      assigned_user_id: 'new_user',
      assigned_at: FaceCloak::FaceRecord.timestamp,
      responded_at: FaceCloak::FaceRecord.timestamp,
      cloak_type: 'comic'
    )

    header 'X-Actor-Id', @img.owner_id
    delete "api/v1/face_records/#{face.id}/assignment"
    _(last_response.status).must_equal 200

    face.refresh
    _(face.assigned_user_id).must_be_nil
    _(face.assigned_at).must_be_nil
    _(face.responded_at).must_be_nil
    _(face.cloak_type).must_equal 'blur'
  end

  it 'SAD: should NOT be able to unassign a face record if not owner' do
    face = FaceCloak::FaceRecord.create(
      image_id: @img.id,
      assigned_user_id: 'new_user',
      assigned_at: FaceCloak::FaceRecord.timestamp
    )

    header 'X-Actor-Id', 'stranger'
    delete "api/v1/face_records/#{face.id}/assignment"
    _(last_response.status).must_equal 403
  end

  it 'SAD: should NOT be able to unassign a face record that is not assigned' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)

    header 'X-Actor-Id', @img.owner_id
    delete "api/v1/face_records/#{face.id}/assignment"
    _(last_response.status).must_equal 400

    result = JSON.parse(last_response.body)
    _(result['message']).must_equal 'Face record is not assigned'
  end

  it 'SAD: should NOT be able to unassign the same face record twice' do
    face = FaceCloak::FaceRecord.create(
      image_id: @img.id,
      assigned_user_id: 'new_user',
      assigned_at: FaceCloak::FaceRecord.timestamp
    )

    header 'X-Actor-Id', @img.owner_id
    delete "api/v1/face_records/#{face.id}/assignment"
    _(last_response.status).must_equal 200

    header 'X-Actor-Id', @img.owner_id
    delete "api/v1/face_records/#{face.id}/assignment"
    _(last_response.status).must_equal 400

    result = JSON.parse(last_response.body)
    _(result['message']).must_equal 'Face record is not assigned'
  end

  it 'HAPPY: should be able to respond to a face record as assignee' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id, assigned_user_id: 'user_123')
    respond_data = { cloak_type: 'sunglasses' }

    header 'X-Actor-Id', 'user_123'
    post "api/v1/face_records/#{face.id}/respond", respond_data.to_json
    _(last_response.status).must_equal 201
  end

  it 'SAD: should NOT be able to respond to a face record if not assignee' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id, assigned_user_id: 'user_123')
    respond_data = { cloak_type: 'sunglasses' }

    header 'X-Actor-Id', 'stranger'
    post "api/v1/face_records/#{face.id}/respond", respond_data.to_json
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should correctly normalize cloak types (Model Unit Test)' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    _(face.cloak_type).must_equal 'blur'
  end

  it 'SAD: should reject invalid cloak types on create' do
    new_face = { image_id: @img.id, cloak_type: 'invalid' }

    header 'X-Actor-Id', @img.owner_id
    post 'api/v1/face_records', new_face.to_json
    _(last_response.status).must_equal 400
  end

  it 'SAD: should reject invalid cloak types on respond' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id, assigned_user_id: 'user_123')
    respond_data = { cloak_type: 'comics' }

    header 'X-Actor-Id', 'user_123'
    post "api/v1/face_records/#{face.id}/respond", respond_data.to_json
    _(last_response.status).must_equal 400
  end

  it 'HAPPY: should track assignment and responses (Model Unit Test)' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    face.assign_to('user_1')
    face.respond_with('comic')

    _(face.assigned_user_id).must_equal 'user_1'
    _(face.cloak_type).must_equal 'comic'
    _(face.responded_at).wont_be_nil
  end

  it 'HAPPY: should clear assignment fields when unassigned (Model Unit Test)' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    face.assign_to('user_1')
    face.respond_with('comic')
    face.unassign

    _(face.assigned_user_id).must_be_nil
    _(face.assigned_at).must_be_nil
    _(face.responded_at).must_be_nil
    _(face.cloak_type).must_equal 'blur'
  end
end
