# frozen_string_literal: true

require 'google/genai'
require 'base64'
require 'json'
require 'net/http'

module FaceCloak
  # Wrapper for Gemini API calls using official SDK
  class GeminiApi
    class NoApiKeyError < StandardError; end
    class ApiError < StandardError; end

    # Detection and cloak prompts intentionally share the same Gemini family.
    DETECT_MODEL = 'gemini-2.5-flash'
    CLOAK_MODEL = 'gemini-2.5-flash'
    IMAGE_EDIT_MODEL = 'gemini-2.5-flash-image'
    PROMPTS_DIR = 'app/lib/prompts'
    DETECT_MAX_TOKENS = 4000

    def self.setup(api_key)
      raise NoApiKeyError unless api_key

      configure_net_http_timeout
      @api_key = api_key
      @client = Google::Genai::Client.new(api_key:, http_options: { read_timeout: 300 })
    end

    def self.inpaint_image(base_image_data, _mask_image_data, prompt)
      raise NoApiKeyError unless @api_key

      response_json = generate_image_edit(prompt, base_image_data)
      image_base64 = extract_inline_image(response_json)
      raise ApiError, 'No image generated' unless image_base64

      Base64.decode64(image_base64)
    end

    def self.detect_faces(image_data, mime_type)
      normalize_faces(with_single_retry('detection', [JSON::ParserError, ApiError]) do
        parse_detection_response(image_data, mime_type)
      end)
    rescue JSON::ParserError, ApiError => e
      handle_detection_failure("malformed Gemini response: #{e.message}")
    rescue NoApiKeyError
      handle_detection_failure('Gemini API key is not configured')
    rescue StandardError => e
      FaceCloak::Api.logger.error("Detection Error: #{e.message}")
      []
    end

    def self.cloak_image(image_data, mime_type, style_name)
      prompt = styled_prompt('cloak_image.txt', style_name)
      result = with_single_retry('AI', [Net::ReadTimeout, JSON::ParserError, ApiError]) do
        response_text = call_api(CLOAK_MODEL, prompt, image_data, mime_type, 4000)
        parse_symbolized_json(response_text)
      end
      image_base64 = result[:image_base64]
      raise ApiError, 'Empty image data' if image_base64.nil? || image_base64.empty?

      Base64.decode64(image_base64)
    end

    def self.call_api(model, prompt, image_data, mime_type, max_tokens = 2000)
      raise NoApiKeyError unless @client

      text = gemini_text_response(model, prompt, image_data, mime_type, max_tokens)
      raise ApiError, 'Empty response from Gemini' if text.nil? || text.empty?

      text
    end

    def self.generate_image_edit(prompt, image_data)
      response = post_image_edit_request(prompt, image_data)
      parse_successful_json_response(response)
    end

    def self.image_edit_request_body(prompt, image_data)
      {
        contents: [{
          parts: [
            { text: prompt },
            { inline_data: { mime_type: 'image/png', data: Base64.strict_encode64(image_data) } }
          ]
        }]
      }
    end

    def self.configure_net_http_timeout
      return if Net::HTTP.const_defined?(:DEFAULT_READ_TIMEOUT) && Net::HTTP::DEFAULT_READ_TIMEOUT == 300

      Net::HTTP.send(:remove_const, :DEFAULT_READ_TIMEOUT) if Net::HTTP.const_defined?(:DEFAULT_READ_TIMEOUT)
      Net::HTTP.const_set(:DEFAULT_READ_TIMEOUT, 300)
    end

    def self.styled_prompt(template_name, instructions)
      template = File.read(File.join(PROMPTS_DIR, template_name))
      format(template, instructions:)
    end

    def self.gemini_text_response(model, prompt, image_data, mime_type, max_tokens)
      parts = [{ text: prompt }, { inline_data: { mime_type:, data: Base64.strict_encode64(image_data) } }]

      response = @client.models.generate_content(
        model:,
        contents: [{ role: 'user', parts: }],
        config: { max_output_tokens: max_tokens }
      )

      response.text&.strip
    end

    def self.post_image_edit_request(prompt, image_data)
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{IMAGE_EDIT_MODEL}:generateContent")
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['x-goog-api-key'] = @api_key
      request.body = image_edit_request_body(prompt, image_data).to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 300) do |http|
        http.request(request)
      end

      ensure_successful_image_edit_response(response)

      response
    end

    def self.ensure_successful_image_edit_response(response)
      return if response.is_a?(Net::HTTPSuccess)

      raise ApiError, "Gemini image edit failed: #{response.code} #{response.body}"
    end

    def self.parse_successful_json_response(response)
      JSON.parse(response.body)
    end

    def self.extract_inline_image(response_json)
      parts = response_json.dig('candidates', 0, 'content', 'parts') || []
      image_part = parts.find { |part| part.dig('inlineData', 'data') || part.dig('inline_data', 'data') }
      image_part&.dig('inlineData', 'data') || image_part&.dig('inline_data', 'data')
    end

    def self.parse_detection_response(image_data, mime_type)
      template = File.read(File.join(PROMPTS_DIR, 'detect_faces.txt'))
      response_text = call_api(DETECT_MODEL, template, image_data, mime_type, DETECT_MAX_TOKENS)
      faces = parse_symbolized_json(response_text)
      raise ApiError, 'Face detection response must be a JSON array' unless faces.is_a?(Array)

      faces
    end

    def self.parse_symbolized_json(response_text)
      payload = balanced_json_fragment(response_text) || response_text.to_s.strip
      JSON.parse(payload, symbolize_names: true)
    end

    # Gemini sometimes wraps JSON in markdown or extra narration.
    def self.balanced_json_fragment(text)
      source = text.to_s.strip
      start_index = source.index(/[\[{]/)
      return nil unless start_index

      end_index = balanced_json_fragment_end_index(source, start_index)
      end_index ? source[start_index..end_index] : nil
    end

    # Walk the text once so nested arrays/objects and quoted strings stay balanced.
    def self.balanced_json_fragment_end_index(source, start_index)
      opener = source[start_index]
      closing = closing_char_for(opener)
      state = { depth: 0, in_string: false, escaped: false }

      source.each_char.with_index do |char, index|
        next if index < start_index

        return index if handle_balanced_char(state, char, opener, closing)
      end

      nil
    end

    def self.update_string_state(state, char)
      if state[:escaped]
        state[:escaped] = false
      elsif char == '\\'
        state[:escaped] = true
      elsif char == '"'
        state[:in_string] = false
      end
    end

    def self.closing_char_for(opener)
      opener == '[' ? ']' : '}'
    end

    def self.balanced_char_end?(state, char, opener, closing)
      return handle_in_string_char(state, char) if state[:in_string]
      return start_string_char(state, char) if char == '"'
      return increment_depth(state) if char == opener
      return handle_closing_char(state) if char == closing

      false
    end

    # These are small imperative helpers; keep names clear rather than
    # forcing predicate-style names.
    # rubocop:disable Naming/PredicateMethod
    def self.handle_in_string_char(state, char)
      update_string_state(state, char)
      false
    end

    def self.start_string_char(state, _char)
      state[:in_string] = true
      false
    end

    def self.increment_depth(state)
      state[:depth] += 1
      false
    end

    def self.handle_closing_char(state)
      state[:depth] -= 1
      return true if state[:depth].zero?

      false
    end
    # rubocop:enable Naming/PredicateMethod

    def self.normalize_faces(faces)
      faces.filter_map { |face| normalize_face(face) }
    end

    def self.with_single_retry(operation_name, retryable_exceptions)
      attempts = 0
      begin
        yield
      rescue StandardError => e
        raise unless retryable_exceptions.any? { |klass| e.is_a?(klass) }

        attempts += 1
        retry if should_retry_attempt?(operation_name, e, attempts)
        raise
      end
    end

    def self.should_retry_attempt?(operation_name, error, attempt)
      return false unless attempt < 2

      FaceCloak::Api.logger.warn("RETRYING #{operation_name} due to #{error.class}: #{error.message}")
      true
    end

    def self.normalize_face(face)
      coordinates = normalized_box_coordinates(face[:box])
      return nil unless coordinates

      {
        y_min: coordinates[0],
        x_min: coordinates[1],
        y_max: coordinates[2],
        x_max: coordinates[3],
        landmarks: normalize_landmarks(face[:landmarks])
      }
    end

    def self.normalized_box_coordinates(box)
      return nil unless box.is_a?(Array) && box.length == 4

      coordinates = box.map { |coordinate| parse_number(coordinate) }
      coordinates.all? ? coordinates : nil
    end

    def self.normalize_landmarks(landmarks)
      return {} unless landmarks.is_a?(Hash)

      landmarks.each_with_object({}) do |(key, point), output|
        next unless point.is_a?(Array) && point.length == 2

        coordinates = point.map { |coordinate| parse_number(coordinate) }
        output[key] = coordinates if coordinates.all?
      end
    end

    def self.parse_number(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def self.handle_detection_failure(message)
      FaceCloak::Api.logger.warn("Detection skipped: #{message}")
      []
    end
  end
end
