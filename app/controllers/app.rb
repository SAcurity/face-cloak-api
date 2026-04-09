# frozen_string_literal: true

require 'json'
require 'roda'

require_relative '../models/cloak_type'
require_relative '../models/face_record'

module FaceCloak
  # Main Roda API application exposing the v1 face record endpoints.
  class Api < Roda
    # rubocop:disable Metrics/BlockLength
    route do |routing|
      FaceCloak::FaceRecord.setup
      response['Content-Type'] = 'application/json'

      routing.root do
        response.status = 200
        {
          app: 'face-cloak-api',
          version: 'v1',
          resources: %w[face_records]
        }.to_json
      end

      routing.on 'api' do
        routing.on 'v1' do
          routing.on 'face_records' do
            # GET /api/v1/face_records
            routing.get true do
              face_records = FaceRecord.all
              response.status = 200
              face_records.map(&:to_h).to_json
            end

            # POST /api/v1/face_records
            routing.post true do
              new_data = JSON.parse(routing.body.read)
              new_face = FaceRecord.create(new_data)
              response.status = 201
              { message: 'Face record saved', id: new_face.id }.to_json
            rescue StandardError
              routing.halt 400, { message: 'Could not save face record' }.to_json
            end

            routing.on String do |id|
              # GET /api/v1/face_records/:id
              routing.get true do
                face_record = FaceRecord.find(id)
                next not_found_message('Face record not found') unless face_record

                response.status = 200
                face_record.to_json
              end

              # POST /api/v1/face_records/:id/assign
              routing.post 'assign' do
                face_record = FaceRecord.find(id)
                next not_found_message('Face record not found') unless face_record

                assign_data = JSON.parse(routing.body.read)
                assigned_user_id = assign_data.fetch('assigned_user_id')
                face_record.assign_to(assigned_user_id)

                if face_record.save
                  response.status = 201
                  { message: 'Face record assigned', assigned_user_id: assigned_user_id }.to_json
                else
                  bad_request_message('Could not assign face record')
                end
              end

              # POST /api/v1/face_records/:id/respond
              routing.post 'respond' do
                face_record = FaceRecord.find(id)
                next not_found_message('Face record not found') unless face_record

                response_data = JSON.parse(routing.body.read)
                cloak_type = response_data.fetch('cloak_type')
                face_record.respond_with(cloak_type)

                if face_record.save
                  response.status = 201
                  { message: 'Face record updated', cloak_type: cloak_type }.to_json
                else
                  bad_request_message('Could not update face record')
                end
              end
            end
          end
        end
      end
    end
    # rubocop:enable Metrics/BlockLength

    private

    def not_found_message(message)
      response.status = 404
      { message: message }.to_json
    end

    def bad_request_message(message)
      response.status = 400
      { message: message }.to_json
    end
  end
end
