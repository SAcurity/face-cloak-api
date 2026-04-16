# frozen_string_literal: true

require 'json'
require 'sequel'

module FaceCloak
  # Represents one detected face and its masking lifecycle.
  class FaceRecord < Sequel::Model
    many_to_one :image
    one_to_many :action_logs
    plugin :association_dependencies, action_logs: :destroy

    plugin :timestamps, update_on_create: true

    def validate
      super
      self.cloak_type = CloakType.normalize(cloak_type)
    end

    def assign_to(user_id, at: self.class.timestamp)
      self.assigned_user_id = user_id
      self.assigned_at = at
      self
    end

    def assigned?
      !assigned_user_id.nil? && !assigned_user_id.empty?
    end

    def unassign
      raise 'Face record is not assigned' unless assigned?

      self.assigned_user_id = nil
      self.assigned_at = nil
      self.responded_at = nil
      self.cloak_type = CloakType::DEFAULT
      self
    end

    def respond_with(cloak_type, at: self.class.timestamp)
      self.responded_at ||= at
      self.cloak_type = CloakType.normalize(cloak_type)
      self
    end

    def effective_cloak_type
      responded_at.nil? ? CloakType::DEFAULT : cloak_type
    end

    def self.timestamp
      # use taiwan time
      Time.now.getlocal('+08:00').iso8601
    end

    # rubocop:disable Metrics/MethodLength
    def to_h
      {
        type: 'face_record',
        attributes: {
          id:,
          image_id:,
          assigned_user_id:,
          assigned_at:,
          responded_at:,
          cloak_type:,
          updated_at:
        }
      }
    end
    # rubocop:enable Metrics/MethodLength

    def to_json(options = {})
      JSON({ data: to_h }, options)
    end
  end
end
