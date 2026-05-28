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
        auth_account_id = require_authenticated_account(routing)
        viewer = Account.first(id: auth_account_id)

        viewable_images = ImagePolicy::AccountScope.new(viewer).viewable
        images_data = viewable_images.map do |image|
          output = image.to_h
          output[:policies] = ImagePolicy.new(viewer, image).index_summary
          output
        end

        JSON.pretty_generate(data: images_data)
      end

      # POST /api/v1/images
      routing.post true do
        requester_id = require_authenticated_account(routing)
        # NOTE: Multipart upload doesn't fit standard dry-validation schema easily,
        # but we could validate additional metadata here if needed.
        new_data = parse_image_upload(routing, owner_id: requester_id)
        new_image = UploadImage.call(image_data: new_data)

        response.status = 201
        response['Location'] = "#{@image_route}/#{new_image.id}"
        { message: 'Image uploaded', data: new_image.to_h }.to_json
      end

      routing.on String do |id|
        routing.is 'raw' do
          routing.get do
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)
            image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

            policy = ImagePolicy.new(viewer, image)
            routing.halt 404, { message: 'Image not found' }.to_json unless policy.can_view_raw?

            ext = File.extname(image.file_name).delete('.')
            response['Content-Type'] = "image/#{ext}"
            GetImageRawFile.call(image_id: id)
          end
        end

        routing.is 'logs' do
          routing.get do
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)
            image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

            policy = ImagePolicy.new(viewer, image)
            routing.halt 404, { message: 'Image not found' }.to_json unless policy.can_view_logs?

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
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)

            policy = ImagePolicy.new(viewer, image)
            routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_view?

            faces_data = image.ordered_face_records.map do |fr|
              output = fr.to_h
              output[:policies] = FaceRecordPolicy.new(viewer, fr).index_summary
              output
            end

            JSON.pretty_generate(data: faces_data)
          end

          routing.post do
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)

            policy = ImagePolicy.new(viewer, image)
            routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_manage_faces?

            new_data = HttpRequest.new(routing).body_data
            # In a real app, we might want a FaceRecordForm here.
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
            auth_account_id = require_authenticated_account(routing)
            viewer = Account.first(id: auth_account_id)
            image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

            policy = ImagePolicy.new(viewer, image)
            routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_view?

            # Force refresh to get latest face_record settings (e.g., respond changes)
            image.refresh

            # Set binary content type based on extension
            ext = File.extname(image.file_name).delete('.')
            response['Content-Type'] = "image/#{ext}"
            response['X-Policy-Summary'] = ImagePolicy.new(viewer, image).summary.to_json

            # Only return raw if ALL detected faces are unveiled
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
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)
            image = Image[id] || raise(Sequel::NoMatchingRow, 'Image not found')

            policy = ImagePolicy.new(viewer, image)
            routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_delete?

            DeleteImage.call(image_id: id)

            { message: 'Image deleted' }.to_json
          end
        end
      end
    end
  end
end
