# frozen_string_literal: true

require 'roda'
require 'json'

module FaceCloak
  # Main Roda API application exposing the v1 face record endpoints.
  class Api < Roda
    class ForbiddenRequest < StandardError; end

    plugin :halt
    plugin :error_handler

    error do |e|
      case e
      when Sequel::MassAssignmentRestriction
        Api.logger.warn "MASS-ASSIGNMENT: #{e.message}"
        response.status = 400
        { message: 'Illegal Attributes' }.to_json
      when Sequel::ValidationFailed, Sequel::NoMatchingRow
        Api.logger.warn "VALIDATION/NOT FOUND: #{e.message}"
        response.status = e.is_a?(Sequel::NoMatchingRow) ? 404 : 400
        { message: e.message }.to_json
      when ForbiddenRequest
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

      routing.root do
        {
          app: 'face-cloak-api',
          version: 'v1',
          resources: %w[images face_records action_logs]
        }.to_json
      end

      @api_root = 'api/v1'
      routing.on @api_root do
        routing.on 'images' do
          @image_route = "#{@api_root}/images"

          # GET /api/v1/images
          routing.get true do
            output = { data: Image.all.map(&:to_h) }
            JSON.pretty_generate(output)
          end

          # POST /api/v1/images
          routing.post true do
            new_data = parse_image_upload(routing)
            new_image = Image.new(new_data)
            raise('Could not save image record') unless new_image.save_changes

            response.status = 201
            response['Location'] = "#{@image_route}/#{new_image.id}"
            { message: 'Image saved', data: new_image.to_h }.to_json
          end

          routing.on String do |id|
            routing.is 'raw' do
              routing.get do
                image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

                # RBAC: ONLY Owner can access raw data
                requester_id = routing.env['HTTP_X_ACTOR_ID']
                raise ForbiddenRequest, 'You do not own this image' unless requester_id == image.owner_id

                ext = File.extname(image.file_name).delete('.')
                response['Content-Type'] = "image/#{ext}"
                image.read_file
              end
            end

            routing.is 'logs' do
              routing.get do
                image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

                logs = image.face_records
                            .flat_map(&:action_logs)
                            .sort_by(&:id)

                output = { data: logs.map(&:to_h) }
                JSON.pretty_generate(output)
              end
            end

            routing.is do
              # GET /api/v1/images/:id (Display protected image by default)
              routing.get do
                image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

                # Set binary content type based on extension
                ext = File.extname(image.file_name).delete('.')
                response['Content-Type'] = "image/#{ext}"

                # Force Privacy Filter for the default route
                # Only return raw if ALL faces are unveiled
                all_unveiled = image.face_records.any? && image.face_records.all? do |fr|
                  fr.effective_cloak_type == 'unveil'
                end

                if all_unveiled
                  image.read_file
                else
                  response['X-Privacy-Filtered'] = 'true'
                  "PRIVACY_FILTERED_DATA_FOR_#{image.id}"
                end
              end

              # DELETE /api/v1/images/:id
              routing.on method: :delete do
                image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

                requester_id = routing.env['HTTP_X_ACTOR_ID']
                raise ForbiddenRequest, 'You do not own this image' unless requester_id == image.owner_id

                raise('Could not delete image') unless image.destroy

                { message: 'Image deleted' }.to_json
              end
            end
          end
        end

        routing.on 'face_records' do
          @resource_route = "#{@api_root}/face_records"

          # GET /api/v1/face_records
          routing.get true do
            output = { data: FaceRecord.all.map(&:to_h) }
            JSON.pretty_generate(output)
          end

          # POST /api/v1/face_records
          routing.post true do
            new_data = parse_request(routing)
            image = Image[new_data['image_id']] || raise(Sequel::NoMatchingRow, 'Image not found')

            # RBAC: Only owner can create face records for their image
            requester_id = routing.env['HTTP_X_ACTOR_ID']
            raise ForbiddenRequest, 'You do not own this image' unless requester_id == image.owner_id

            new_face = FaceRecord.new(new_data)
            raise('Could not save face record') unless new_face.save_changes

            # Log creation
            new_face.add_action_log(action: 'create', actor_id: requester_id)

            response.status = 201
            response['Location'] = "#{@resource_route}/#{new_face.id}"
            { message: 'Face record saved', data: new_face.to_h }.to_json
          end

          routing.on String do |id|
            # GET /api/v1/face_records/:id/logs
            routing.is 'logs' do
              routing.get do
                face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

                output = { data: face_record.action_logs.map(&:to_h) }
                JSON.pretty_generate(output)
              end
            end

            # GET /api/v1/face_records/:id
            routing.is do
              routing.get do
                face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')
                face_record.to_json
              end
            end

            # POST /api/v1/face_records/:id/assignment
            # DELETE /api/v1/face_records/:id/assignment
            routing.is 'assignment' do
              routing.post do
                face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

                # RBAC: Only image owner can edit/assign face records
                requester_id = routing.env['HTTP_X_ACTOR_ID']
                raise ForbiddenRequest, 'You do not own this image' unless requester_id == face_record.image.owner_id

                assign_data = parse_request(routing)
                assigned_user_id = assign_data.fetch('assigned_user_id')

                # Constraint: Owner can only assign ONE face record to themselves per image
                if assigned_user_id == face_record.image.owner_id
                  already_assigned = face_record.image.face_records.any? do |fr|
                    fr.assigned_user_id == assigned_user_id && fr.id != face_record.id
                  end
                  raise ForbiddenRequest, 'You can only assign one face to yourself' if already_assigned
                end

                face_record.assign_to(assigned_user_id)
                raise 'Could not assign face record' unless face_record.save_changes

                face_record.add_action_log(action: 'assign', actor_id: requester_id)
                response.status = 201
                { message: 'Face record assigned', data: face_record.to_h }.to_json
              end

              routing.on method: :delete do
                face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

                requester_id = routing.env['HTTP_X_ACTOR_ID']
                raise ForbiddenRequest, 'You do not own this image' unless requester_id == face_record.image.owner_id

                face_record.clear_assignment
                raise 'Could not unassign face record' unless face_record.save_changes

                face_record.add_action_log(action: 'unassign', actor_id: requester_id)
                { message: 'Face record unassigned', data: face_record.to_h }.to_json
              end
            end

            # POST /api/v1/face_records/:id/respond
            routing.is 'respond' do
              routing.post do
                face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

                # Zero-Trust RBAC: ONLY the assigned user can respond/unveil.
                # Even the image owner cannot call this if they are not the assignee.
                requester_id = routing.env['HTTP_X_ACTOR_ID']
                unless face_record.assigned? && requester_id == face_record.assigned_user_id
                  raise ForbiddenRequest, 'You are not assigned to this record'
                end

                response_data = parse_request(routing)
                cloak_type = response_data.fetch('cloak_type')
                face_record.respond_with(cloak_type)
                raise 'Could not update face record' unless face_record.save_changes

                face_record.add_action_log(action: 'respond', actor_id: requester_id)
                response.status = 201
                { message: 'Face record updated', data: face_record.to_h }.to_json
              end
            end
          end
        end
      end
    end

    private

    def not_found(message) = { message: }.to_json
    def bad_request(message) = { message: }.to_json
    def forbidden(message) = { message: }.to_json
    def parse_request(routing) = JSON.parse(routing.body.read)

    def parse_image_upload(routing)
      uploaded_file = routing.params['file']
      raise ArgumentError, 'file upload is required' unless uploaded_file

      owner_id = routing.params['owner_id'].to_s
      raise ArgumentError, 'owner_id is required' if owner_id.empty?

      {
        'owner_id' => owner_id,
        'file_name' => upload_filename(uploaded_file),
        'file_data' => upload_tempfile(uploaded_file).path
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
