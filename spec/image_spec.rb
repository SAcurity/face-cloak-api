# frozen_string_literal: true

require_relative 'spec_helper'
require 'tmpdir'
require 'tempfile'

describe 'Test Image Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
  end

  it 'HAPPY: should be able to get list of all images' do
    FaceCloak::Image.create(seed_attributes(DATA[:images][0]))
    FaceCloak::Image.create(seed_attributes(DATA[:images][1]))

    get 'api/v1/images'
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_equal 2
  end

  it 'HAPPY: should be able to get details of a single image' do
    img_data = DATA[:images][0]
    seed_binary = Base64.decode64(img_data['file_data'])
    img = FaceCloak::Image.create(seed_attributes(img_data))

    header 'X-Actor-Id', img.owner_id
    get "api/v1/images/#{img.id}/raw"
    _(last_response.status).must_equal 200
    _(last_response.headers['Content-Type']).must_include 'image'
    _(last_response.body).must_equal seed_binary

    # Also verify default route is filtered for owner
    get "api/v1/images/#{img.id}"
    _(last_response.body).must_include 'PRIVACY_FILTERED_DATA'
  end

  it 'SAD: should return FILTERED data if non-owner requests image with unmasked faces' do
    img_data = DATA[:images][0]
    img = FaceCloak::Image.create(seed_attributes(img_data))

    header 'X-Actor-Id', 'not-the-owner'
    get "api/v1/images/#{img.id}"
    _(last_response.status).must_equal 200
    _(last_response.body).must_include 'PRIVACY_FILTERED_DATA'
  end

  it 'SAD: should return error if unknown image requested' do
    get '/api/v1/images/missing-image'

    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should be able to create a new image and retrieve its file' do
    test_data = 'test binary content'
    upload = Tempfile.new(['upload', '.png'])
    upload.binmode
    upload.write(test_data)
    upload.rewind
    uploaded_file = Rack::Test::UploadedFile.new(upload.path, 'image/png')
    expected_name = File.basename(upload.path)

    post 'api/v1/images', { owner_id: 'o1', file: uploaded_file }
    _(last_response.status).must_equal 201

    result = JSON.parse(last_response.body)
    id = result['data']['attributes']['id']
    _(result['data']['attributes']['file_name']).must_equal expected_name
    _(result['data']['attributes']['file_data'].end_with?('.png')).must_equal true

    header 'X-Actor-Id', 'o1'
    get "api/v1/images/#{id}/raw"
    _(last_response.status).must_equal 200
    _(last_response.body).must_equal test_data
  ensure
    upload.close!
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

  it 'HAPPY: should suffix duplicate file names for the same owner' do
    Dir.mktmpdir do |dir1|
      Dir.mktmpdir do |dir2|
        path1 = File.join(dir1, 'repeat.png')
        path2 = File.join(dir2, 'repeat.png')
        File.binwrite(path1, 'first image')
        File.binwrite(path2, 'second image')

        upload1 = Rack::Test::UploadedFile.new(path1, 'image/png')
        upload2 = Rack::Test::UploadedFile.new(path2, 'image/png')

        post 'api/v1/images', { owner_id: 'photographer_alina', file: upload1 }
        _(last_response.status).must_equal 201
        first_result = JSON.parse(last_response.body)

        post 'api/v1/images', { owner_id: 'photographer_alina', file: upload2 }
        _(last_response.status).must_equal 201
        second_result = JSON.parse(last_response.body)

        _(first_result['data']['attributes']['file_name']).must_equal 'repeat.png'
        _(second_result['data']['attributes']['file_name']).must_equal 'repeat-1.png'
      end
    end
  end

  it 'HAPPY: should allow different owners to keep the same file name' do
    Dir.mktmpdir do |dir1|
      Dir.mktmpdir do |dir2|
        path1 = File.join(dir1, 'shared.png')
        path2 = File.join(dir2, 'shared.png')
        File.binwrite(path1, 'owner a image')
        File.binwrite(path2, 'owner b image')

        upload1 = Rack::Test::UploadedFile.new(path1, 'image/png')
        upload2 = Rack::Test::UploadedFile.new(path2, 'image/png')

        post 'api/v1/images', { owner_id: 'photographer_alina', file: upload1 }
        _(last_response.status).must_equal 201
        first_result = JSON.parse(last_response.body)

        post 'api/v1/images', { owner_id: 'photographer_bruno', file: upload2 }
        _(last_response.status).must_equal 201
        second_result = JSON.parse(last_response.body)

        _(first_result['data']['attributes']['file_name']).must_equal 'shared.png'
        _(second_result['data']['attributes']['file_name']).must_equal 'shared.png'
      end
    end
  end

  it 'HAPPY: should delete an owned image and its stored file' do
    img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))
    stored_path = File.join(FaceCloak::Image::STORAGE_DIR, img.file_data)

    header 'X-Actor-Id', img.owner_id
    delete "api/v1/images/#{img.id}"
    _(last_response.status).must_equal 200
    _(FaceCloak::Image[img.id]).must_be_nil
    _(File.exist?(stored_path)).must_equal false
  end

  it 'SAD: should NOT delete an image if requester is not owner' do
    img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))

    header 'X-Actor-Id', 'stranger'
    delete "api/v1/images/#{img.id}"
    _(last_response.status).must_equal 403
    _(FaceCloak::Image[img.id]).wont_be_nil
  end

  it 'SAD: should return not found when deleting an unknown image' do
    header 'X-Actor-Id', 'photographer_alina'
    delete 'api/v1/images/missing-image'
    _(last_response.status).must_equal 404

    result = JSON.parse(last_response.body)
    _(result['message']).must_equal 'Image not found'
  end

  it 'SAD: should NOT be able to delete the same image twice' do
    img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))

    header 'X-Actor-Id', img.owner_id
    delete "api/v1/images/#{img.id}"
    _(last_response.status).must_equal 200

    header 'X-Actor-Id', img.owner_id
    delete "api/v1/images/#{img.id}"
    _(last_response.status).must_equal 404

    result = JSON.parse(last_response.body)
    _(result['message']).must_equal 'Image not found'
  end
end
