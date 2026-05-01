# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Image Model Unit Logic' do
  before do
    wipe_database
    @account = create_account('alice', 'alice@example.com', 'password123')
  end

  it 'HAPPY: should save and read file data correctly (Model Unit Test)' do
    img = FaceCloak::UploadImage.call(
      image_data: {
        'owner_id' => @account.id,
        'file_name' => 't.jpg',
        'file_data' => Base64.strict_encode64('placeholder')
      }
    )
    _(FaceCloak::GetImageRawFile.call(image_id: img.id)).must_equal 'placeholder'
    _(img.file_data.end_with?('.jpg')).must_equal true
    _(File.exist?(File.join(FaceCloak::Image::STORAGE_DIR, img.file_data))).must_equal true
  end

  it 'HAPPY: should persist seeded base64 data to local storage on create' do
    img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][1]).merge('owner_id' => @account.id))

    _(img.file_data.end_with?('.png')).must_equal true
    _(File.exist?(File.join(FaceCloak::Image::STORAGE_DIR, img.file_data))).must_equal true
  end

  it 'SAD: should not allow mass assigning restricted columns (Security)' do
    # Verify whitelist protection - created_at is restricted
    _(proc { FaceCloak::Image.new(created_at: Time.now) }).must_raise Sequel::MassAssignmentRestriction
  end
end
