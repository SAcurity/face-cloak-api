# frozen_string_literal: true

module FaceCloak
  # Authorization rules for FaceRecord resources
  class FaceRecordPolicy
    RESOURCE = 'face_records'

    def initialize(viewer, face_record, auth_scope: AuthScope.new)
      @viewer = viewer
      @face_record = face_record
      @auth_scope = auth_scope.is_a?(AuthScope) ? auth_scope : AuthScope.new(auth_scope)
    end

    def can_view?
      can_read? && (viewer_is_owner? || viewer_is_assignee? || admin?)
    end

    def can_view_logs?
      can_read? && (viewer_is_owner? || viewer_is_assignee? || admin?)
    end

    def can_assign?
      can_write? && (viewer_is_owner? || admin?)
    end

    def can_respond?
      # Zero-Trust exception: Admin cannot respond for others
      can_write? && viewer_is_assignee?
    end

    def can_decline?
      can_write? && viewer_is_assignee?
    end

    def summary
      {
        can_view: can_view?,
        can_view_logs: can_view_logs?,
        can_assign: can_assign?,
        can_respond: can_respond?,
        can_decline: can_decline?
      }
    end

    def index_summary
      {
        can_view: can_view?
      }
    end

    private

    def admin?
      @viewer&.admin? || false
    end

    def can_read?
      @auth_scope.can_read?(RESOURCE)
    end

    def can_write?
      @auth_scope.can_write?(RESOURCE)
    end

    def viewer_is_owner?
      @viewer && @face_record && @viewer.id == @face_record.image.owner_id
    end

    def viewer_is_assignee?
      @viewer && @face_record && @viewer.id == @face_record.assigned_user_id
    end
  end
end
