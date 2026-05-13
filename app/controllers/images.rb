# frozen_string_literal: true

require 'roda'
require_relative 'app'

module FaceCloak
  # Web controller for FaceCloak API
  class Api < Roda
    route('images') do |routing|
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
        { message: 'Image uploaded', data: new_image.to_h }.to_json
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

        routing.is 'face_records' do
          image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

          routing.get do
            output = { data: image.ordered_face_records.map(&:to_h) }
            JSON.pretty_generate(output)
          end

          routing.post do
            # RBAC: Only owner can create face records for their image
            requester_id = routing.env['HTTP_X_ACTOR_ID']
            raise ForbiddenRequest, 'You do not own this image' unless requester_id.to_i == image.owner_id

            new_data = HttpRequest.new(routing).body_data
            new_face = CreateFaceRecord.call(
              face_data: new_data.merge(image_id: image.id),
              actor_id: requester_id.to_i
            )

            response.status = 201
            { message: 'Face record created', data: new_face.to_h }.to_json
          end
        end

        routing.is do
          # GET /api/v1/images/:id (Display protected image by default)
          routing.get do
            image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')
            # Force refresh to get latest face_record settings (e.g., respond changes)
            image.refresh

            # Set binary content type based on extension
            ext = File.extname(image.file_name).delete('.')
            response['Content-Type'] = "image/#{ext}"

            # Only return raw if ALL detected faces are unveiled
            # If no faces are detected, we still mark it as filtered for safety or just return raw.
            # Here we follow: if any face is blurred/cloaked, it is filtered.
            ordered_faces = image.ordered_face_records
            all_unveiled = ordered_faces.any? && ordered_faces.all? do |fr|
              fr.effective_cloak_type == 'unveil'
            end

            if all_unveiled
              GetImageRawFile.call(image_id: id)
            else
              response['X-Privacy-Filtered'] = 'true'
              CloakImage.call(image: image)
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
  end
end
