# frozen_string_literal: true

require 'roda'
require 'json'

require_relative 'http_request'

module FaceCloak
  # Main Roda API application exposing the v1 face record endpoints.
  class Api < Roda
    class ForbiddenRequest < StandardError; end

    plugin :halt
    plugin :multi_route
    plugin :error_handler

    error do |e|
      case e
      when Sequel::MassAssignmentRestriction
        Api.logger.warn "MASS-ASSIGNMENT: #{e.message}"
        response.status = 400
        { message: 'Illegal Attributes' }.to_json
      when Sequel::NoMatchingRow
        Api.logger.warn "NOT FOUND: #{e.message}"
        response.status = 404
        { message: e.message }.to_json
      when Sequel::ValidationFailed, Sequel::ForeignKeyConstraintViolation
        Api.logger.warn "VALIDATION/FK ERROR: #{e.message}"
        response.status = 400
        { message: e.message }.to_json
      when ForbiddenRequest, AssignFaceRecord::ForbiddenError
        response.status = 403
        { message: e.message }.to_json
      when JSON::ParserError, RuntimeError
        Api.logger.warn "LOGIC ERROR (#{e.class}): #{e.message}"
        response.status = 400
        { message: e.message }.to_json
      when KeyError, ArgumentError
        Api.logger.warn "INPUT ERROR: #{e.class}: #{e.message}\n#{e.backtrace[0..5].join("\n")}"
        response.status = 400
        { message: e.message }.to_json
      else
        Api.logger.error "UNKNOWN ERROR (#{e.class}): #{e.inspect}\n#{e.backtrace[0..5].join("\n")}"
        response.status = 500
        { message: "Unknown server error: #{e.class}" }.to_json
      end
    end

    route do |routing|
      response['Content-Type'] = 'application/json'

      # Enforce TLS/SSL Required
      HttpRequest.new(routing).secure? ||
        routing.halt(403, { message: 'TLS/SSL Required' }.to_json)

      routing.root do
        {
          app: 'face-cloak-api',
          version: 'v1',
          resources: %w[accounts images face_records auth]
        }.to_json
      end

      routing.on 'api' do
        routing.on 'v1' do
          @api_root = 'api/v1'
          routing.multi_route
        end
      end
    end

    private

    def parse_image_upload(routing) # rubocop:disable Metrics/MethodLength
      uploaded_file = routing.params['file']
      raise ArgumentError, 'file upload is required' unless uploaded_file

      # Use X-Actor-Id header as the source of truth for ownership
      owner_id = routing.env['HTTP_X_ACTOR_ID']
      raise ArgumentError, 'X-Actor-Id header is required for upload' if owner_id.to_s.empty?

      # Verify account exists
      account = Account[owner_id.to_i]
      raise ArgumentError, 'Account not found' unless account

      # Safely get the tempfile path
      temp_file = upload_tempfile(uploaded_file)
      # Ensure the file is flushed and accessible
      temp_file.rewind

      {
        'owner_id' => account.id,
        'file_name' => upload_filename(uploaded_file),
        'file_data' => temp_file.path # This path must be persistent during the Service call
      }
    end

    def upload_filename(uploaded_file)
      filename = uploaded_file[:filename]
      raise ArgumentError, 'uploaded file is invalid' unless filename

      filename
    end

    def upload_tempfile(uploaded_file)
      tempfile = uploaded_file[:tempfile]
      raise ArgumentError, 'uploaded file is invalid' unless tempfile

      tempfile
    end
  end
end
