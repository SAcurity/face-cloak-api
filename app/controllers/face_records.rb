# frozen_string_literal: true

require 'roda'
require_relative 'app'

module FaceCloak
  # Web controller for FaceCloak API
  class Api < Roda
    route('face_records') do |routing|
      @resource_route = "#{@api_root}/face_records"

      routing.on String do |id|
        routing.is 'assignment' do
          # POST /api/v1/face_records/:id/assignment
          routing.post do
            requester_id = require_authenticated_account(routing)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')
            image = face_record.image

            # RBAC: Only image owner can assign
            raise ForbiddenRequest, 'You do not own the parent image' unless requester_id.to_i == image.owner_id

            new_data = HttpRequest.new(routing).body_data
            AssignFaceRecord.call(
              face_record_id: id,
              assigned_user_id: new_data[:assigned_user_id],
              actor_id: requester_id.to_i
            )

            response.status = 201
            { message: 'User assigned to face record', data: face_record.to_h }.to_json
          end

          # DELETE /api/v1/face_records/:id/assignment
          routing.on method: :delete do
            requester_id = require_authenticated_account(routing)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')
            image = face_record.image

            # RBAC: Only image owner can unassign
            raise ForbiddenRequest, 'You do not own the parent image' unless requester_id.to_i == image.owner_id

            face_record.update(assigned_user_id: nil, assigned_at: nil)
            face_record.add_action_log(action: 'unassign', actor_id: requester_id.to_i)

            { message: 'User unassigned from face record' }.to_json
          end
        end

        routing.is 'respond' do
          # POST /api/v1/face_records/:id/respond
          routing.post do
            requester_id = require_authenticated_account(routing)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

            # RBAC: Only assigned user can respond (Zero-Trust)
            unless requester_id.to_i == face_record.assigned_user_id
              raise ForbiddenRequest, 'You are not assigned to this face record'
            end

            new_data = HttpRequest.new(routing).body_data
            RespondToFaceRecord.call(
              face_record_id: id,
              cloak_type: new_data[:cloak_type],
              actor_id: requester_id.to_i
            )

            response.status = 201
            { message: 'Face record updated', data: face_record.to_h }.to_json
          end
        end

        routing.is 'logs' do
          routing.get do
            requester_id = require_authenticated_account(routing)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

            # RBAC: Only owner or assigned user can see logs for a face
            is_owner = requester_id.to_i == face_record.image.owner_id
            is_assignee = requester_id.to_i == face_record.assigned_user_id
            raise Sequel::NoMatchingRow, 'Face record not found' unless is_owner || is_assignee

            output = { data: face_record.action_logs.map(&:to_h) }
            JSON.pretty_generate(output)
          end
        end

        # GET /api/v1/face_records/:id
        routing.get do
          requester_id = require_authenticated_account(routing)
          face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')
          is_owner = requester_id.to_i == face_record.image.owner_id
          is_assignee = requester_id.to_i == face_record.assigned_user_id
          raise Sequel::NoMatchingRow, 'Face record not found' unless is_owner || is_assignee

          JSON.pretty_generate(face_record.to_h)
        end
      end
    end
  end
end
