# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Image Model Unit Logic' do
  before do
    wipe_database
  end

  it 'HAPPY: should save and read file data correctly (Model Unit Test)' do
    img = FaceCloak::Image.create(
      owner_id: 'o',
      file_name: 't.jpg',
      file_data: Base64.strict_encode64('placeholder')
    )
    test_binary = 'binary'
    img.save_file(test_binary)

    _(img.read_file).must_equal test_binary
    _(img.file_data.end_with?('.jpg')).must_equal true
    _(File.exist?(File.join(FaceCloak::Image::STORAGE_DIR, img.file_data))).must_equal true
  end

  it 'HAPPY: should persist seeded base64 data to local storage on create' do
    img = FaceCloak::Image.create(seed_attributes(DATA[:images][1]))

    _(img.file_data.end_with?('.png')).must_equal true
    _(img.file_data).wont_equal DATA[:images][1]['file_data']
    _(File.exist?(File.join(FaceCloak::Image::STORAGE_DIR, img.file_data))).must_equal true
  end

  it 'SAD: should not allow mass assigning restricted columns (Security)' do
    # Verify whitelist protection
    _(proc { FaceCloak::Image.new(id: 'evil-id') }).must_raise Sequel::MassAssignmentRestriction
  end
end
