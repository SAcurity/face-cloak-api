# frozen_string_literal: true

require 'roda'
require 'json'

module FaceCloak
  # Main Roda API application exposing the v1 face record endpoints.
  class Api < Roda
    class ForbiddenRequest < StandardError; end

    plugin :halt

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
          rescue StandardError
            routing.halt 404, not_found('Could not find images')
          end

          # POST /api/v1/images
          routing.post true do
            new_data = parse_image_upload(routing)
            new_image = Image.new(new_data)
            raise('Could not save image record') unless new_image.save_changes

            response.status = 201
            response['Location'] = "#{@image_route}/#{new_image.id}"
            { message: 'Image saved', data: new_image.to_h }.to_json
          rescue StandardError => e
            routing.halt 400, bad_request(e.message)
          end

          routing.on String do |id|
            routing.is 'logs' do
              routing.get do
                image = Image[id.to_i]
                raise('Image not found') unless image

                logs = image.face_records
                            .flat_map(&:action_logs)
                            .sort_by(&:id)

                output = { data: logs.map(&:to_h) }
                JSON.pretty_generate(output)
              rescue StandardError => e
                routing.halt 404, not_found(e.message)
              end
            end

            routing.is do
              # GET /api/v1/images/:id (Display specified image - PUBLIC)
              routing.get do
                image = Image[id.to_i]
                raise('Image not found') unless image

                # Set binary content type based on extension
                ext = File.extname(image.file_name).delete('.')
                response['Content-Type'] = "image/#{ext}"
                image.read_file
              rescue StandardError => e
                routing.halt 404, not_found(e.message)
              end

              # DELETE /api/v1/images/:id
              if routing.delete?
                begin
                  image = Image[id.to_i]
                  raise('Image not found') unless image

                  requester_id = routing.env['HTTP_X_ACTOR_ID']
                  raise ForbiddenRequest, 'You do not own this image' unless requester_id == image.owner_id

                  raise('Could not delete image') unless image.destroy

                  { message: 'Image deleted' }.to_json
                rescue ForbiddenRequest => e
                  routing.halt 403, forbidden(e.message)
                rescue RuntimeError => e
                  routing.halt 404, not_found(e.message) if e.message == 'Image not found'
                  routing.halt 400, bad_request(e.message)
                rescue StandardError => e
                  routing.halt 400, bad_request(e.message)
                end
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
          rescue StandardError
            routing.halt 404, not_found('Could not find face records')
          end

          # POST /api/v1/face_records
          routing.post true do
            new_data = parse_request(routing)
            image = Image[new_data['image_id'].to_i]
            raise('Image not found') unless image

            # RBAC: Only owner can create face records for their image
            requester_id = routing.env['HTTP_X_ACTOR_ID']
            raise ForbiddenRequest, 'You do not own this image' unless requester_id == image.owner_id

            new_face = FaceRecord.new(new_data)
            raise('Could not save face record') unless new_face.save_changes

            # Log creation
            new_face.add_action_log(
              action: 'create',
              actor_id: requester_id
            )

            response.status = 201
            response['Location'] = "#{@resource_route}/#{new_face.id}"
            { message: 'Face record saved', data: new_face.to_h }.to_json
          rescue ForbiddenRequest => e
            routing.halt 403, forbidden(e.message)
          rescue StandardError => e
            routing.halt 400, bad_request(e.message)
          end

          routing.on String do |id|
            # GET /api/v1/face_records/:id/logs
            routing.is 'logs' do
              routing.get do
                face_record = FaceRecord[id.to_i]
                raise('Face record not found') unless face_record

                output = { data: face_record.action_logs.map(&:to_h) }
                JSON.pretty_generate(output)
              rescue StandardError => e
                routing.halt 404, not_found(e.message)
              end
            end

            # GET /api/v1/face_records/:id
            routing.is do
              routing.get do
                face_record = FaceRecord[id.to_i]
                face_record ? face_record.to_json : raise('Face record not found')
              rescue StandardError => e
                routing.halt 404, not_found(e.message)
              end
            end

            # POST /api/v1/face_records/:id/assignment
            # DELETE /api/v1/face_records/:id/assignment
            routing.is 'assignment' do
              routing.post do
                face_record = FaceRecord[id.to_i]
                raise('Face record not found') unless face_record

                # RBAC: Only image owner can edit/assign face records
                requester_id = routing.env['HTTP_X_ACTOR_ID']
                raise ForbiddenRequest, 'You do not own this image' unless requester_id == face_record.image.owner_id

                assign_data = parse_request(routing)
                face_record.assign_to(assign_data.fetch('assigned_user_id'))

                if face_record.save_changes
                  face_record.add_action_log(action: 'assign', actor_id: requester_id)
                  response.status = 201
                  { message: 'Face record assigned', data: face_record.to_h }.to_json
                else
                  routing.halt 400, bad_request('Could not assign face record')
                end
              rescue ForbiddenRequest => e
                routing.halt 403, forbidden(e.message)
              rescue StandardError => e
                routing.halt 400, bad_request(e.message)
              end

              if routing.delete?
                begin
                  face_record = FaceRecord[id.to_i]
                  raise('Face record not found') unless face_record

                  requester_id = routing.env['HTTP_X_ACTOR_ID']
                  raise ForbiddenRequest, 'You do not own this image' unless requester_id == face_record.image.owner_id

                  face_record.unassign

                  if face_record.save_changes
                    face_record.add_action_log(action: 'unassign', actor_id: requester_id)
                    { message: 'Face record unassigned', data: face_record.to_h }.to_json
                  else
                    routing.halt 400, bad_request('Could not unassign face record')
                  end
                rescue ForbiddenRequest => e
                  routing.halt 403, forbidden(e.message)
                rescue StandardError => e
                  routing.halt 400, bad_request(e.message)
                end
              end
            end

            # POST /api/v1/face_records/:id/respond
            routing.is 'respond' do
              routing.post do
                face_record = FaceRecord[id.to_i]
                raise('Face record not found') unless face_record

                # RBAC: Only the assigned user can respond
                requester_id = routing.env['HTTP_X_ACTOR_ID']
                unless requester_id == face_record.assigned_user_id
                  raise ForbiddenRequest, 'You are not assigned to this record'
                end

                response_data = parse_request(routing)
                cloak_type = response_data.fetch('cloak_type')
                face_record.respond_with(cloak_type)

                if face_record.save_changes
                  face_record.add_action_log(action: 'respond', actor_id: requester_id)
                  response.status = 201
                  { message: 'Face record updated', data: face_record.to_h }.to_json
                else
                  routing.halt 400, bad_request('Could not update face record')
                end
              rescue ForbiddenRequest => e
                routing.halt 403, forbidden(e.message)
              rescue StandardError => e
                routing.halt 400, bad_request(e.message)
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
      raise 'file upload is required' unless uploaded_file

      owner_id = routing.params['owner_id'].to_s
      raise 'owner_id is required' if owner_id.empty?

      {
        'owner_id' => owner_id,
        'file_name' => upload_filename(uploaded_file),
        'file_data' => upload_tempfile(uploaded_file).path
      }
    end

    def upload_filename(uploaded_file)
      filename = uploaded_file[:filename]
      raise 'uploaded file is invalid' unless filename

      filename
    end

    def upload_tempfile(uploaded_file)
      tempfile = uploaded_file[:tempfile]
      raise 'uploaded file is invalid' unless tempfile

      tempfile
    end
  end
end
