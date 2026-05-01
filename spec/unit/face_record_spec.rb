# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FaceRecord Model Unit Logic' do
  before do
    wipe_database
    @account = create_account('alice', 'alice@example.com', 'password123')
    @img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge(owner_id: @account.id))
  end

  it 'HAPPY: should correctly normalize cloak types (Model Unit Test)' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @account.id)
    _(face.cloak_type).must_equal 'blur'
  end

  it 'HAPPY: should track assignment and responses (Model Unit Test)' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @account.id)
    FaceCloak::AssignFaceRecord.call(
      face_record_id: face.id,
      assigned_user_id: @account.id,
      actor_id: @account.id
    )
    FaceCloak::RespondToFaceRecord.call(
      face_record_id: face.id,
      cloak_type: 'comic',
      actor_id: @account.id
    )
    face.refresh

    _(face.assigned_user_id).must_equal @account.id
    _(face.cloak_type).must_equal 'comic'
    _(face.responded_at).wont_be_nil
  end

  it 'HAPPY: should clear assignment fields when unassigned (Model Unit Test)' do
    face = FaceCloak::CreateFaceRecord.call(face_data: { image_id: @img.id }, actor_id: @account.id)
    FaceCloak::AssignFaceRecord.call(
      face_record_id: face.id,
      assigned_user_id: @account.id,
      actor_id: @account.id
    )
    face.update(
      assigned_user_id: nil,
      assigned_at: nil,
      responded_at: nil,
      cloak_type: 'blur'
    )

    _(face.assigned_user_id).must_be_nil
    _(face.assigned_at).must_be_nil
    _(face.responded_at).must_be_nil
    _(face.cloak_type).must_equal 'blur'
  end

  it 'SAD: should not allow mass assigning restricted columns (Security)' do
    # updated_at is restricted
    _(proc { FaceCloak::FaceRecord.new(updated_at: Time.now) }).must_raise Sequel::MassAssignmentRestriction
  end
end
