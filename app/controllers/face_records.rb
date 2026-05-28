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
            viewer = Account.first(id: requester_id)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

            policy = FaceRecordPolicy.new(viewer, face_record)
            routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_assign?

            new_data = HttpRequest.new(routing).body_data

            # Direct model operations, Tyto-style
            unless new_data['assigned_user_id'] || new_data[:assigned_user_id]
              raise ArgumentError, 'assigned_user_id is missing'
            end

            AssignFaceRecord.call(
              face_record_id: id,
              assigned_user_id: new_data['assigned_user_id'] || new_data[:assigned_user_id],
              actor_id: requester_id.to_i
            )

            response.status = 201
            { message: 'User assigned to face record', data: face_record.to_h }.to_json
          end

          # DELETE /api/v1/face_records/:id/assignment
          routing.on method: :delete do
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

            policy = FaceRecordPolicy.new(viewer, face_record)
            routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_assign?

            face_record.update(assigned_user_id: nil, assigned_at: nil)
            face_record.add_action_log(action: 'unassign', actor_id: requester_id.to_i)

            { message: 'User unassigned from face record' }.to_json
          end
        end

        routing.is 'respond' do
          # POST /api/v1/face_records/:id/respond
          routing.post do
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

            policy = FaceRecordPolicy.new(viewer, face_record)
            routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_respond?

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

        routing.is 'decline' do
          # POST /api/v1/face_records/:id/decline
          routing.post do
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

            policy = FaceRecordPolicy.new(viewer, face_record)
            routing.halt 403, { message: 'Forbidden' }.to_json unless policy.can_decline?

            face_record = DeclineFaceRecord.call(
              face_record_id: id,
              actor_id: requester_id.to_i
            )

            { message: 'Face assignment declined', data: face_record.to_h }.to_json
          end
        end

        routing.is 'logs' do
          routing.get do
            requester_id = require_authenticated_account(routing)
            viewer = Account.first(id: requester_id)
            face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

            policy = FaceRecordPolicy.new(viewer, face_record)
            routing.halt 404, { message: 'Face record not found' }.to_json unless policy.can_view_logs?

            output = { data: face_record.action_logs.map(&:to_h) }
            JSON.pretty_generate(output)
          end
        end

        # GET /api/v1/face_records/:id
        routing.get do
          requester_id = require_authenticated_account(routing)
          viewer = Account.first(id: requester_id)
          face_record = FaceRecord[id] || raise(Sequel::NoMatchingRow, 'Face record not found')

          policy = FaceRecordPolicy.new(viewer, face_record)
          routing.halt 404, { message: 'Face record not found' }.to_json unless policy.can_view?

          output = face_record.to_h
          output[:policies] = policy.summary
          JSON.pretty_generate(output)
        end
      end
    end
  end
end
