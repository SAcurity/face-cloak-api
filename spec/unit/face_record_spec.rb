# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FaceRecord Model Unit Logic' do
  before do
    wipe_database
    @img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))
  end

  it 'HAPPY: should correctly normalize cloak types (Model Unit Test)' do
    face = FaceCloak::FaceRecord.create(image_id: @img.id)
    _(face.cloak_type).must_equal 'blur'
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
    face.clear_assignment

    _(face.assigned_user_id).must_be_nil
    _(face.assigned_at).must_be_nil
    _(face.responded_at).must_be_nil
    _(face.cloak_type).must_equal 'blur'
  end

  it 'SAD: should not allow mass assigning restricted columns (Security)' do
    new_data = { 'image_id' => @img.id, 'id' => 'evil-id' }
    _(proc { FaceCloak::FaceRecord.new(new_data) }).must_raise Sequel::MassAssignmentRestriction
  end
end
