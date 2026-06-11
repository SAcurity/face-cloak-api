# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FaceRecord API Integration' do
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
  end

  it 'HAPPY: should be able to get list of all face records for an image' do
    FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id, cloak_type: 'blur', x_min: 0.1 },
                                     actor_id: @owner.id)
    FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id, cloak_type: 'comics', x_min: 0.2 },
                                     actor_id: @owner.id)

    get "api/v1/images/#{@img.id}/face_records", nil, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_be :>=, 2
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
    new_face = { cloak_type: 'pixelate', x_min: 0.5, y_min: 0.5, x_max: 0.6, y_max: 0.6 }

    post "api/v1/images/#{@img.id}/face_records", new_face.to_json, @req_header
    _(last_response.status).must_equal 201

    result = JSON.parse(last_response.body)
    _(result['data']['type']).must_equal 'face_record'
    _(result['data']['attributes']['cloak_type']).must_equal 'pixelate'
  end

  it 'SAD: should NOT be able to create a face record if not owner' do
    new_face = { cloak_type: 'blur', x_min: 0.5 }

    post "api/v1/images/#{@img.id}/face_records", new_face.to_json, auth_request_header(@stranger)
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to assign a face record as owner' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)

    post "api/v1/face_records/#{face.id}/assignment", { assigned_user_id: @assignee.id }.to_json, @req_header
    _(last_response.status).must_equal 201

    face.refresh
    _(face.assigned_user_id).must_equal @assignee.id
  end

  it 'SAD: should reject assignment without assigned user id' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)

    post "api/v1/face_records/#{face.id}/assignment", {}, @req_header
    _(last_response.status).must_equal 400
    _(JSON.parse(last_response.body)['message']).must_include 'is missing'
  end

  it 'SAD: should return 404 when assigning to unknown account' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)

    post "api/v1/face_records/#{face.id}/assignment", { assigned_user_id: 99_999 }.to_json, @req_header

    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should include assigned user summary in face record responses' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    get "api/v1/images/#{@img.id}/face_records", nil, @req_header

    result = JSON.parse(last_response.body)
    assigned_face = result['data'].find { |record| record['attributes']['id'] == face.id }
    _(assigned_face['attributes']['assigned_user']).must_equal(
      'id' => @assignee.id,
      'username' => @assignee.username
    )
  end

  it 'SAD: should NOT be able to assign a face record if not owner' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)

    post "api/v1/face_records/#{face.id}/assignment", { assigned_user_id: @assignee.id }.to_json,
         auth_request_header(@stranger)
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to unassign a face record as owner' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    delete "api/v1/face_records/#{face.id}/assignment", nil, @req_header
    _(last_response.status).must_equal 200
  end

  it 'SAD: should NOT unassign a face record after assignee responded' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)
    FaceCloak::RespondToFaceRecord.call(face_record_id: face.id, cloak_type: 'mask', actor_id: @assignee.id)

    delete "api/v1/face_records/#{face.id}/assignment", nil, @req_header

    _(last_response.status).must_equal 409
    face.refresh
    _(face.assigned_user_id).must_equal @assignee.id
  end

  it 'SAD: should NOT be able to unassign a face record if not owner' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    delete "api/v1/face_records/#{face.id}/assignment", nil, auth_request_header(@stranger)

    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to respond to a face record as assignee' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    post "api/v1/face_records/#{face.id}/respond", { cloak_type: 'mask' }.to_json,
         auth_request_header(@assignee)
    _(last_response.status).must_equal 201

    face.refresh
    _(face.cloak_type).must_equal 'mask'

    cached_files = Dir.glob(File.join(FaceCloak::CloakImage::CACHE_DIR, "full_#{@img.id}_*.png"))
    _(cached_files).wont_be_empty
  end

  it 'SAD: should NOT allow image owner to respond if NOT assigned (Zero-Trust)' do
    face = @img.face_records.first
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    post "api/v1/face_records/#{face.id}/respond", { cloak_type: 'mask' }.to_json, @req_header
    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should allow assignee to decline a face assignment' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)
    FaceCloak::RespondToFaceRecord.call(
      face_record_id: face.id,
      cloak_type: 'mask',
      actor_id: @assignee.id,
      skip_render: true
    )

    post "api/v1/face_records/#{face.id}/decline", nil, auth_request_header(@assignee)
    _(last_response.status).must_equal 200

    face.refresh
    _(face.assigned_user_id).must_be_nil
    _(face.assigned_at).must_be_nil
    _(face.responded_at).must_be_nil
    _(face.cloak_type).must_equal 'blur'
    _(face.action_logs.map(&:action)).must_include 'decline'
  end

  it 'SAD: should NOT allow owner to decline an assignment for the assignee' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    post "api/v1/face_records/#{face.id}/decline", nil, @req_header

    _(last_response.status).must_equal 403
  end

  it 'SAD: should NOT allow stranger to decline an assignment' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @owner.id)
    FaceCloak::AssignFaceRecord.call(face_record_id: face.id, assigned_user_id: @assignee.id, actor_id: @owner.id)

    post "api/v1/face_records/#{face.id}/decline", nil, auth_request_header(@stranger)

    _(last_response.status).must_equal 403
  end

  it 'HAPPY: should be able to assign different faces in one image to different users' do
    # Ensure we have at least 2 faces
    if @img.face_records.count < 2
      FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id, x_min: 0.1 }, actor_id: @owner.id)
      @img.refresh
    end

    face1 = @img.face_records[0]
    face2 = @img.face_records[1]

    post "api/v1/face_records/#{face1.id}/assignment", { assigned_user_id: @assignee.id }.to_json, @req_header
    _(last_response.status).must_equal 201

    post "api/v1/face_records/#{face2.id}/assignment", { assigned_user_id: @stranger.id }.to_json, @req_header
    _(last_response.status).must_equal 201

    face1.refresh
    face2.refresh
    _(face1.assigned_user_id).must_equal @assignee.id
    _(face2.assigned_user_id).must_equal @stranger.id
  end

  it 'SAD: should NOT allow assigning the same user to two different faces in the same image' do
    # Ensure we have at least 2 faces
    if @img.face_records.count < 2
      FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id, x_min: 0.1 }, actor_id: @owner.id)
      @img.refresh
    end

    face1 = @img.face_records[0]
    face2 = @img.face_records[1]

    # First assignment
    post "api/v1/face_records/#{face1.id}/assignment", { assigned_user_id: @assignee.id }.to_json, @req_header
    _(last_response.status).must_equal 201

    # Second assignment to the same user in the same image (Constraint violation)
    post "api/v1/face_records/#{face2.id}/assignment", { assigned_user_id: @assignee.id }.to_json, @req_header
    _(last_response.status).must_equal 403
    result = JSON.parse(last_response.body)
    _(result['message']).must_include 'already assigned'
  end
end
