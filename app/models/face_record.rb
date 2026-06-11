# frozen_string_literal: true

require 'json'
require 'sequel'

module FaceCloak
  # Represents one detected face and its masking lifecycle.
  class FaceRecord < Sequel::Model
    unrestrict_primary_key
    many_to_one :image
    many_to_one :assigned_user, class: :'FaceCloak::Account'
    one_to_many :action_logs
    plugin :association_dependencies, action_logs: :destroy

    plugin :timestamps, update_on_create: true
    plugin :whitelist_security
    set_allowed_columns :image_id, :assigned_user_id, :assigned_at, :responded_at, :cloak_type,
                        :x_min, :y_min, :x_max, :y_max, :landmarks

    def before_create
      self.id ||= SecureRandom.uuid
      super
    end

    def validate
      super
      return unless cloak_type && !CloakType.valid?(cloak_type)

      errors.add(:cloak_type, "must be one of #{CloakType::OPTIONS.join(', ')}")
    end

    def assigned?
      !assigned_user_id.nil?
    end

    def add_audit_log(action:, actor_id:)
      add_action_log(
        action:,
        actor_id:,
        assigned_user_id:,
        cloak_type: effective_cloak_type
      )
    end

    def effective_cloak_type
      # Direct access to DB column, fallback to 'blur'
      self[:cloak_type].nil? || self[:cloak_type].empty? ? 'blur' : self[:cloak_type]
    end

    def landmarks_map
      JSON.parse(landmarks || '{}', symbolize_names: true)
    end

    def to_h # rubocop:disable Metrics/MethodLength
      {
        type: 'face_record',
        attributes: {
          id:,
          image_id:,
          assigned_user_id:,
          assigned_user: assigned_user_summary,
          assigned_at:,
          responded_at:,
          cloak_type:,
          x_min:,
          y_min:,
          x_max:,
          y_max:,
          updated_at:
        }
      }
    end

    def assigned_user_summary
      return nil unless assigned_user

      {
        id: assigned_user.id,
        username: assigned_user.username
      }
    end

    def to_json(options = {})
      JSON(to_h, options)
    end
  end
end
