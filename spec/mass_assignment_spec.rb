# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Test Mass Assignment Protection' do
  include Rack::Test::Methods

  before do
    wipe_database
  end

  it 'SAD: should not allow mass assigning restricted columns in Image' do
    # Let's test the model directly for mass assignment
    _(proc { FaceCloak::Image.new(id: 'evil') }).must_raise Sequel::MassAssignmentRestriction
  end

  it 'SAD: should not allow mass assigning restricted columns in FaceRecord' do
    # Use valid base64 for file_data to avoid decoding error during creation
    img = FaceCloak::Image.create(
      owner_id: 'o',
      file_name: 'f.jpg',
      file_data: Base64.strict_encode64('data')
    )
    new_data = {
      'image_id' => img.id,
      'assigned_user_id' => 'user1',
      'id' => 'evil_id'
    }

    _(proc { FaceCloak::FaceRecord.new(new_data) }).must_raise Sequel::MassAssignmentRestriction
  end
end
