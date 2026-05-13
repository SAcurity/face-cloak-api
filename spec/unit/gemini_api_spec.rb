# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Gemini API response handling' do
  it 'HAPPY: parses fenced face detection JSON returned by Gemini' do
    response = <<~JSON
      ```json
      [
        {
          "box": [120, 230, 360, 470],
          "landmarks": {
            "left_eye": [185, 290],
            "right_eye": [188, 405],
            "nose": [250, 350],
            "mouth": [315, 345]
          }
        }
      ]
      ```
    JSON

    faces = with_stubbed_call_api(response) do
      FaceCloak::GeminiApi.detect_faces('image-data', 'image/png')
    end

    _(faces.length).must_equal 1
    _(faces.first[:y_min]).must_equal 120.0
    _(faces.first[:x_min]).must_equal 230.0
    _(faces.first[:landmarks][:left_eye]).must_equal [185.0, 290.0]
  end

  it 'HAPPY: retries once when face detection JSON is truncated' do
    calls = 0
    responses = [
      '[{"box": [120, 230, 360, 470], "landmarks": {"left_eye": [185, 290]}',
      '[{"box": [120, 230, 360, 470], "landmarks": {"left_eye": [185, 290]}}]'
    ]

    call_api = lambda do |*|
      calls += 1
      responses[calls - 1]
    end

    faces = with_stubbed_call_api(call_api) do
      FaceCloak::GeminiApi.detect_faces('image-data', 'image/png')
    end

    _(calls).must_equal 2
    _(faces.length).must_equal 1
    _(faces.first[:x_max]).must_equal 470.0
  end

  it 'SAD: returns no faces after retrying malformed face detection JSON' do
    calls = 0

    call_api = lambda do |*|
      calls += 1
      '[{"box": [120, 230]'
    end

    faces = with_stubbed_call_api(call_api) do
      FaceCloak::GeminiApi.detect_faces('image-data', 'image/png')
    end

    _(calls).must_equal 2
    _(faces).must_equal []
  end

  it 'HAPPY: extracts generated image data from camelCase Gemini image responses' do
    response = {
      'candidates' => [{
        'content' => {
          'parts' => [{ 'inlineData' => { 'data' => Base64.strict_encode64('image-data') } }]
        }
      }]
    }

    image_data = FaceCloak::GeminiApi.extract_inline_image(response)

    _(Base64.decode64(image_data)).must_equal 'image-data'
  end

  it 'HAPPY: inpaints through generateContent image editing response' do
    response = {
      'candidates' => [{
        'content' => {
          'parts' => [{ 'inline_data' => { 'data' => Base64.strict_encode64('edited-image') } }]
        }
      }]
    }

    image = with_gemini_api_key('test-key') do
      with_stubbed_singleton_method(:generate_image_edit, response) do
        FaceCloak::GeminiApi.inpaint_image('base-image', 'mask-image', 'add sunglasses')
      end
    end

    _(image).must_equal 'edited-image'
  end

  def with_stubbed_call_api(response, &)
    with_stubbed_singleton_method(:call_api, response, &)
  end

  def with_stubbed_singleton_method(method_name, response)
    original = FaceCloak::GeminiApi.method(method_name)
    FaceCloak::GeminiApi.define_singleton_method(method_name) do |*args|
      response.respond_to?(:call) ? response.call(*args) : response
    end

    yield
  ensure
    FaceCloak::GeminiApi.define_singleton_method(method_name, original)
  end

  def with_gemini_api_key(api_key)
    original = FaceCloak::GeminiApi.instance_variable_get(:@api_key)
    FaceCloak::GeminiApi.instance_variable_set(:@api_key, api_key)

    yield
  ensure
    FaceCloak::GeminiApi.instance_variable_set(:@api_key, original)
  end
end
