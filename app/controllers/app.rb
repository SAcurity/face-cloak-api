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
            routing.get do
              face_records = FaceRecord.all
              response.status = 200
              JSON.pretty_generate(face_records.map(&:to_h))
            end

            # POST /api/v1/face_records
            routing.post do
              new_data = JSON.parse(routing.body.read)
              new_face = FaceRecord.new(new_data)

              if new_face.save
                response.status = 201
                { message: 'Face record saved', id: new_face.id }.to_json
              else
                routing.halt 400, { message: 'Could not save face record' }.to_json
              end
            end

            routing.on String do |id|
              # GET /api/v1/face_records/:id
              routing.get true do
                face_record = FaceRecord.find(id)
                routing.halt 404, { message: 'Face record not found' }.to_json unless face_record

                response.status = 200
                JSON.pretty_generate(face_record.to_h)
              end

              # POST /api/v1/face_records/:id/assign
              routing.post 'assign' do
                face_record = FaceRecord.find(id)
                routing.halt 404, { message: 'Face record not found' }.to_json unless face_record

                assign_data = JSON.parse(routing.body.read)
                assigned_user_id = assign_data.fetch('assigned_user_id')
                face_record.assign_to(assigned_user_id)

                if face_record.save
                  response.status = 201
                  { message: 'Face record assigned', assigned_user_id: assigned_user_id }.to_json
                else
                  routing.halt 400, { message: 'Could not assign face record' }.to_json
                end
              end

              # POST /api/v1/face_records/:id/respond
              routing.post 'respond' do
                face_record = FaceRecord.find(id)
                routing.halt 404, { message: 'Face record not found' }.to_json unless face_record

                response_data = JSON.parse(routing.body.read)
                cloak_type = response_data.fetch('cloak_type')
                face_record.respond_with(cloak_type)

                if face_record.save
                  response.status = 201
                  { message: 'Face record updated', cloak_type: cloak_type }.to_json
                else
                  routing.halt 400, { message: 'Could not update face record' }.to_json
                end
              end
            end
          end
        end
      end
    end
    # rubocop:enable Metrics/BlockLength
  end
end
