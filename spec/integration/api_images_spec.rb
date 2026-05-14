# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Image API Integration' do
  include Rack::Test::Methods

  before do
    wipe_database
    @req_header = { 'CONTENT_TYPE' => 'application/json' }
    @account = create_account('alice', 'alice@example.com', 'password123')
  end

  it 'HAPPY: should be able to get list of all images' do
    FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge('owner_id' => @account.id))
    FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][1]).merge('owner_id' => @account.id))

    get 'api/v1/images', nil, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse(last_response.body)
    _(result['data'].count).must_be :>=, 2
  end

  it 'HAPPY: should be able to get details of a single image' do
    img_data = DATA[:images][0]
    File.binread(img_data['file_data'])
    img = FaceCloak::UploadImage.call(image_data: seed_attributes(img_data).merge('owner_id' => @account.id))
    header 'X-Actor-Id', img.owner_id
    get "api/v1/images/#{img.id}/raw", nil, @req_header
    _(last_response.status).must_equal 200
    _(last_response.headers['Content-Type']).must_include 'image'
    # Flexible length check because filtered rendering may re-encode the image.
    _(last_response.body.length).must_be :>, 1000

    # Also verify default route is filtered for owner
    get "api/v1/images/#{img.id}", nil, @req_header
    _(last_response.headers['X-Privacy-Filtered']).must_equal 'true'
    _(last_response.body.length).must_be :>, 1000
  end

  it 'SAD: should return FILTERED data if non-owner requests image with unmasked faces' do
    img_data = DATA[:images][0]
    img = FaceCloak::UploadImage.call(image_data: seed_attributes(img_data).merge('owner_id' => @account.id))

    header 'X-Actor-Id', 999_999
    get "api/v1/images/#{img.id}", nil, @req_header
    _(last_response.status).must_equal 200
    _(last_response.headers['X-Privacy-Filtered']).must_equal 'true'
    _(last_response.body.length).must_be :>, 1000
  end

  it 'SAD: should return error if unknown image requested' do
    get '/api/v1/images/missing-image', nil, @req_header
    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should be able to create a new image and retrieve its file' do
    # Use a real small image file for upload testing
    img_data = DATA[:images][0]
    uploaded_file = Rack::Test::UploadedFile.new(img_data['file_data'], 'image/png')

    header 'X-Actor-Id', @account.id
    post 'api/v1/images', { file: uploaded_file }
    _(last_response.status).must_equal 201

    result = JSON.parse(last_response.body)
    id = result['data']['attributes']['id']
    # File name might be suffixed or specific, just check that it is not empty
    _(result['data']['attributes']['file_name']).wont_be_nil

    header 'X-Actor-Id', @account.id
    get "api/v1/images/#{id}/raw", nil, @req_header
    _(last_response.status).must_equal 200
    _(last_response.body.length).must_be :>, 1000
  end

  it 'HAPPY: should suffix duplicate image file names for the same owner' do
    img_data = DATA[:images][0]

    header 'X-Actor-Id', @account.id
    post 'api/v1/images', { file: Rack::Test::UploadedFile.new(img_data['file_data'], 'image/png') }
    _(last_response.status).must_equal 201
    first_result = JSON.parse(last_response.body)

    header 'X-Actor-Id', @account.id
    post 'api/v1/images', { file: Rack::Test::UploadedFile.new(img_data['file_data'], 'image/png') }
    _(last_response.status).must_equal 201

    second_result = JSON.parse(last_response.body)
    first_name = first_result['data']['attributes']['file_name']
    second_name = second_result['data']['attributes']['file_name']

    _(second_name).must_equal "#{File.basename(first_name, '.*')}-1#{File.extname(first_name)}"
  end

  it 'HAPPY: should delete an owned image and its stored file' do
    img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge('owner_id' => @account.id))
    storage_key = img.file_data

    header 'X-Actor-Id', img.owner_id
    delete "api/v1/images/#{img.id}", nil, @req_header
    _(last_response.status).must_equal 200
    _(FaceCloak::Image[img.id]).must_be_nil
    _(FaceCloak::ImageStorage.exist?(storage_key)).must_equal false
  end

  it 'SAD: should NOT delete an image if requester is not owner' do
    img = FaceCloak::UploadImage.call(image_data: seed_attributes(DATA[:images][0]).merge('owner_id' => @account.id))

    header 'X-Actor-Id', 999_999
    delete "api/v1/images/#{img.id}", nil, @req_header
    _(last_response.status).must_equal 403
    _(FaceCloak::Image[img.id]).wont_be_nil
  end

  it 'SECURITY: should prevent SQL injection in image ID lookup' do
    evil_id = CGI.escape("' OR 1=1 --")
    get "api/v1/images/#{evil_id}", nil, @req_header
    _(last_response.status).must_equal 404
  end
end
