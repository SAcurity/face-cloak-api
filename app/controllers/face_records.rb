# frozen_string_literal: true

require 'roda'
require_relative 'app'

module FaceCloak
  # Web controller for FaceCloak API
  class Api < Roda
    route('face_records') do |routing|
      @resource_route = "#{@api_root}/face_records"

      # GET /api/v1/face_records
      routing.get true do
        output = { data: FaceRecord.all.map(&:to_h) }
        JSON.pretty_generate(output)
      end

      # POST /api/v1/face_records
      routing.post true do
        new_data = HttpRequest.new(routing).body_data
        image = Image[new_data[:image_id]] || raise(Sequel::NoMatchingRow, 'Image not found')

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

            assign_data = HttpRequest.new(routing).body_data
            assigned_user_id = assign_data[:assigned_user_id]

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

            response_data = HttpRequest.new(routing).body_data
            cloak_type = response_data[:cloak_type]

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
