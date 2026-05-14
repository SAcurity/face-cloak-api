# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Image Model Unit Logic' do
  before do
    wipe_database
    @account = create_account('alice', 'alice@example.com', 'password123')
  end

  it 'HAPPY: should save and read file data correctly (Model Unit Test)' do
    img_data = DATA[:images][0]
    img = FaceCloak::UploadImage.call(
      image_data: {
        'owner_id' => @account.id,
        'file_name' => 't.png',
        'file_data' => img_data['file_data']
      }
    )
    # The output might not match exactly if AI modified it or sips converted it
    _(FaceCloak::GetImageRawFile.call(image_id: img.id).length).must_be :>, 1000
    _(img.file_data.end_with?('.png')).must_equal true
    _(FaceCloak::ImageStorage.exist?(img.file_data)).must_equal true
  end

  it 'HAPPY: should persist seeded data to local storage on create' do
    # Use real image from seeds (which is now a file path)
    img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge('owner_id' => @account.id))

    _(img.file_name).must_equal DATA[:images][0]['file_name']
    _(FaceCloak::ImageStorage.exist?(img.file_data)).must_equal true
  end

  it 'HAPPY: should expose face records in stable spatial order' do
    img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge('owner_id' => @account.id))

    face_a = FaceCloak::CreateFaceRecord.call(
      face_data: { image_id: img.id, x_min: 0.6, y_min: 0.2 },
      actor_id: @account.id
    )
    face_b = FaceCloak::CreateFaceRecord.call(
      face_data: { image_id: img.id, x_min: 0.2, y_min: 0.8 },
      actor_id: @account.id
    )

    ordered_ids = img.ordered_face_records.map(&:id)
    manual_ids = ordered_ids.select { |id| [face_a.id, face_b.id].include?(id) }

    _(manual_ids).must_equal [face_b.id, face_a.id]
    _(img.to_h[:attributes][:face_ids].index(face_b.id)).must_be :<, img.to_h[:attributes][:face_ids].index(face_a.id)
  end

  it 'SAD: should not allow mass assigning restricted columns (Security)' do
    # Verify whitelist protection - created_at is restricted
    _(proc { FaceCloak::Image.new(created_at: Time.now) }).must_raise Sequel::MassAssignmentRestriction
  end
end
