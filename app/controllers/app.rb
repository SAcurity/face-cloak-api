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
      when Sequel::NoMatchingRow
        Api.logger.warn "NOT FOUND: #{e.message}"
        response.status = 404
        { message: e.message }.to_json
      when Sequel::ValidationFailed, Sequel::ForeignKeyConstraintViolation
        Api.logger.warn "VALIDATION/FK ERROR: #{e.message}"
        response.status = 400
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
          resources: %w[images face_records]
        }.to_json
      end

      @api_root = 'api/v1'
      routing.on @api_root do
        routing.on 'accounts' do
          @account_route = "#{@api_root}/accounts"

          routing.on 'authenticate' do
            routing.post do
              credentials = parse_request(routing)
              account = AuthenticateAccount.call(
                username: credentials['username'],
                password: credentials['password']
              )
              { data: account.to_h }.to_json
            rescue AuthenticateAccount::UnauthorizedError => e
              routing.halt 401, { message: e.message }.to_json
            end
          end

          routing.is do
            routing.post do
              account_data = parse_request(routing)
              new_account = CreateAccount.call(account_data:)
              response.status = 201
              response['Location'] = "#{@account_route}/#{new_account.username}"
              { message: 'Account created', data: new_account.to_h }.to_json
            rescue StandardError => e
              routing.halt 400, { message: e.message }.to_json
            end
          end

          routing.post 'search' do
            search_data = parse_request(routing)
            email = search_data['email']
            account = Account.first(email_hash: SecureDB.hash(email))
            raise(Sequel::NoMatchingRow, 'Account not found') unless account

            account.to_json
          end

          routing.on String do |username|
            routing.get do
              account = Account.first(username:)
              raise(Sequel::NoMatchingRow, 'Account not found') unless account

              account.to_json
            end
          end
        end

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
            new_image = UploadImage.call(image_data: new_data)

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
                raise ForbiddenRequest, 'You do not own this image' unless requester_id.to_i == image.owner_id

                ext = File.extname(image.file_name).delete('.')
                response['Content-Type'] = "image/#{ext}"
                GetImageRawFile.call(image_id: id)
              end
            end

            routing.is 'logs' do
              routing.get do
                image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

                # RBAC: ONLY Owner can see all logs for an image
                requester_id = routing.env['HTTP_X_ACTOR_ID']
                raise ForbiddenRequest, 'You do not own this image' unless requester_id.to_i == image.owner_id

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
                  GetImageRawFile.call(image_id: id)
                else
                  response['X-Privacy-Filtered'] = 'true'
                  "PRIVACY_FILTERED_DATA_FOR_#{image.id}"
                end
              end

              # DELETE /api/v1/images/:id
              routing.on method: :delete do
                image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

                requester_id = routing.env['HTTP_X_ACTOR_ID']
                raise ForbiddenRequest, 'You do not own this image' unless requester_id.to_i == image.owner_id

                DeleteImage.call(image_id: id)

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
            raise ForbiddenRequest, 'You do not own this image' unless requester_id.to_i == image.owner_id

            new_face = CreateFaceRecord.call(face_data: new_data, actor_id: requester_id.to_i)

            response.status = 201
            response['Location'] = "#{@resource_route}/#{new_face.id}"
            { message: 'Face record saved', data: new_face.to_h }.to_json
          end

          routing.on String do |id|
            # GET /api/v1/face_records/:id/logs
            routing.is 'logs' do
              routing.get do
                face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

                # RBAC: Only Owner or the specific Assignee can see logs for this record
                requester_id = routing.env['HTTP_X_ACTOR_ID']
                is_owner = requester_id.to_i == face_record.image.owner_id
                is_assignee = requester_id.to_i == face_record.assigned_user_id
                raise ForbiddenRequest, 'Access denied' unless is_owner || is_assignee

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
                unless requester_id.to_i == face_record.image.owner_id
                  raise ForbiddenRequest,
                        'You do not own this image'
                end

                assign_data = parse_request(routing)
                assigned_user_id = assign_data.fetch('assigned_user_id')

                face_record = AssignFaceRecord.call(
                  face_record_id: id,
                  assigned_user_id:,
                  actor_id: requester_id.to_i
                )

                response.status = 201
                { message: 'Face record assigned and access granted', data: face_record.to_h }.to_json
              rescue AssignFaceRecord::ForbiddenError => e
                routing.halt 403, { message: e.message }.to_json
              end

              routing.on method: :delete do
                face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

                requester_id = routing.env['HTTP_X_ACTOR_ID']
                unless requester_id.to_i == face_record.image.owner_id
                  raise ForbiddenRequest,
                        'You do not own this image'
                end

                face_record.update(
                  assigned_user_id: nil,
                  assigned_at: nil,
                  responded_at: nil,
                  cloak_type: CloakType::DEFAULT
                )

                face_record.add_action_log(action: 'unassign', actor_id: requester_id.to_i)
                { message: 'Face record unassigned', data: face_record.to_h }.to_json
              end
            end

            # POST /api/v1/face_records/:id/respond
            routing.is 'respond' do
              routing.post do
                face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

                # Zero-Trust RBAC: ONLY the assigned user can respond/unveil.
                requester_id = routing.env['HTTP_X_ACTOR_ID']
                unless face_record.assigned? && requester_id.to_i == face_record.assigned_user_id
                  raise ForbiddenRequest, 'You are not assigned to this record'
                end

                response_data = parse_request(routing)
                cloak_type = response_data.fetch('cloak_type')

                face_record = RespondToFaceRecord.call(
                  face_record_id: id,
                  cloak_type:,
                  actor_id: requester_id.to_i
                )

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

    def parse_image_upload(routing) # rubocop:disable Metrics/MethodLength
      uploaded_file = routing.params['file']
      raise ArgumentError, 'file upload is required' unless uploaded_file

      owner_id = routing.params['owner_id']
      raise ArgumentError, 'owner_id is required' if owner_id.nil? || owner_id.to_s.empty?

      # Verify account exists (Account.id is now Integer)
      account = Account[owner_id.to_i]
      raise ArgumentError, 'Account not found' unless account

      {
        'owner_id' => account.id,
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
