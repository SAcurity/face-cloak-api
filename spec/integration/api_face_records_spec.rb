# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FaceRecord API Integration' do
  include Rack::Test::Methods

  before do
    wipe_database
    @req_header = { 'CONTENT_TYPE' => 'application/json' }
    @owner = create_account('alice', 'alice@example.com', 'password123')
    @assignee = create_account('bob', 'bob@example.com', 'password123')
    @stranger = create_account('charlie', 'charlie@example.com', 'password123')
    @img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge('owner_id' => @owner.id))
  end

  it 'HAPPY: should be able to get list of all face records' do
    FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id, cloak_type: 'blur' }, actor_id: @owner.id)
    FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id, cloak_type: 'comic' }, actor_id: @owner.id)

    get 'api/v1/face_records', nil, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_equal 4 # 2 from upload + 2 manual
    _(result['data'][0]['type']).must_equal 'face_record'
  end

  it 'HAPPY: should be able to get details of a single face record' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id, cloak_type: 'pixelate' },
                                            actor_id: @owner.id)
    get "api/v1/face_records/#{face.id}", nil, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['type']).must_equal 'face_record'
    _(result['attributes']['id']).must_equal face.id
  end

  it 'SAD: should return error if unknown face record requested' do
    get '/api/v1/face_records/missing-face', nil, @req_header

    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should be able to create a new face record as owner' do
    new_face = { image_id: @img.id, cloak_type: 'pixelate' }

    header 'X-Actor-Id', @owner.id
    post 'api/v1/face_records', new_face.to_json, @req_header
    _(last_response.status).must_equal 201

    result = JSON.parse(last_response.body)
    _(result['data']['type']).must_equal 'face_record'
    _(result['data']['attributes']['cloak_type']).must_equal 'pixelate'
  end

  it 'SAD: should NOT be able to create a face record if not owner' do
    new_face = { image_id: @img.id, cloak_type: 'blur' }

    header 'X-Actor-Id', @stranger.id
    post 'api/v1/face_records', new_face.to_json, @req_header
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to assign a face record as owner' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)

    header 'X-Actor-Id', @owner.id
    post "api/v1/face_records/#{face.id}/assignment", { assigned_user_id: @assignee.id }.to_json, @req_header
    _(last_response.status).must_equal 201

    face.refresh
    _(face.assigned_user_id).must_equal @assignee.id
  end

  it 'SAD: should NOT be able to assign a face record if not owner' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)

    header 'X-Actor-Id', @stranger.id
    post "api/v1/face_records/#{face.id}/assignment", { assigned_user_id: @assignee.id }.to_json, @req_header
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to unassign a face record as owner' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    header 'X-Actor-Id', @owner.id
    delete "api/v1/face_records/#{face.id}/assignment", nil, @req_header
    _(last_response.status).must_equal 200
  end

  it 'HAPPY: should be able to respond to a face record as assignee' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    header 'X-Actor-Id', @assignee.id
    post "api/v1/face_records/#{face.id}/respond", { cloak_type: 'mask' }.to_json, @req_header
    _(last_response.status).must_equal 201

    face.refresh
    _(face.cloak_type).must_equal 'mask'
  end

  it 'SAD: should NOT allow image owner to respond if NOT assigned (Zero-Trust)' do
    face = @img.face_records.first
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    header 'X-Actor-Id', @owner.id
    post "api/v1/face_records/#{face.id}/respond", { cloak_type: 'mask' }.to_json, @req_header
    _(last_response.status).must_equal 403
  end

  it 'SAD: should reject invalid cloak types on respond' do
    face = @img.face_records.first
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    header 'X-Actor-Id', @assignee.id
    post "api/v1/face_records/#{face.id}/respond", { cloak_type: 'invisible' }.to_json, @req_header
    _(last_response.status).must_equal 400
  end
end
