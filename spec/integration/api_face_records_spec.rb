# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FaceRecord API Integration' do
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
    _(result['data'].count).must_equal 4 # 2 from seeds + 2 auto-generated per image
  end

  it 'HAPPY: should be able to get details of a single face record' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    get "api/v1/face_records/#{face.id}"
    _(last_response.status).must_equal 200
  end

  it 'SAD: should return error if unknown face record requested' do
    get '/api/v1/face_records/missing-face'

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

  it 'SAD: should NOT allow owner to assign more than ONE face to themselves' do
    # Image has 2 auto-generated faces
    faces = @img.face_records

    # First self-assignment: OK
    header 'X-Actor-Id', @img.owner_id
    post "api/v1/face_records/#{faces[0].id}/assignment", { assigned_user_id: @img.owner_id }.to_json
    _(last_response.status).must_equal 201

    # Second self-assignment: Forbidden
    post "api/v1/face_records/#{faces[1].id}/assignment", { assigned_user_id: @img.owner_id }.to_json
    _(last_response.status).must_equal 403
    _(JSON.parse(last_response.body)['message']).must_include 'only assign one face to yourself'
  end

  it 'HAPPY: should be able to unassign a face record as owner' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    face.assign_to('new_user')
    face.respond_with('comic')
    face.save_changes

    header 'X-Actor-Id', @img.owner_id
    delete "api/v1/face_records/#{face.id}/assignment"
    _(last_response.status).must_equal 200
  end

  it 'SAD: should NOT be able to unassign a face record if not owner' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    face.assign_to('new_user')
    face.save_changes

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

  it 'HAPPY: should be able to respond to a face record as assignee' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    face.assign_to('reviewer_mina')
    face.save_changes

    respond_data = { cloak_type: 'sunglasses' }

    header 'X-Actor-Id', 'reviewer_mina'
    post "api/v1/face_records/#{face.id}/respond", respond_data.to_json
    _(last_response.status).must_equal 201
  end

  it 'SAD: should NOT be able to respond to a face record if not assignee' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    face.assign_to('reviewer_mina')
    face.save_changes

    respond_data = { cloak_type: 'sunglasses' }

    header 'X-Actor-Id', 'stranger'
    post "api/v1/face_records/#{face.id}/respond", respond_data.to_json
    _(last_response.status).must_equal 403
  end

  it 'SAD: should NOT allow image owner to respond if NOT assigned (Zero-Trust)' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    # Even though actor is the image owner, they are NOT the record assignee
    header 'X-Actor-ID', @img.owner_id
    post "/api/v1/face_records/#{face.id}/respond", { cloak_type: 'unveil' }.to_json
    _(last_response.status).must_equal 403
    _(JSON.parse(last_response.body)['message']).must_include 'not assigned'
  end

  it 'SAD: should reject invalid cloak types on create' do
    new_face = { image_id: @img.id, cloak_type: 'invalid' }

    header 'X-Actor-Id', @img.owner_id
    post 'api/v1/face_records', new_face.to_json
    _(last_response.status).must_equal 400
  end

  it 'SAD: should reject invalid cloak types on respond' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    face.assign_to('reviewer_mina')
    face.save_changes

    respond_data = { cloak_type: 'comics' }

    header 'X-Actor-Id', 'reviewer_mina'
    post "api/v1/face_records/#{face.id}/respond", respond_data.to_json
    _(last_response.status).must_equal 400
  end
end
