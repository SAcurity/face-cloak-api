# frozen_string_literal: true

module FaceCloak
  # Authorization rules for Image resources
  class ImagePolicy
    RESOURCE = 'images'

    def initialize(viewer, image, auth_scope: AuthScope.new)
      @viewer = viewer
      @image = image
      @auth_scope = auth_scope.is_a?(AuthScope) ? auth_scope : AuthScope.new(auth_scope)
    end

    def can_view?
      # Allow all authenticated users to view (filtered) images to support discovery.
      can_read? && !@viewer.nil?
    end

    def can_view_logs?
      can_read? && (viewer_is_owner? || admin?)
    end

    def can_delete?
      can_write? && (viewer_is_owner? || admin?)
    end

    def can_manage_faces?
      can_write? && (viewer_is_owner? || admin?)
    end

    def summary
      {
        can_view: can_view?,
        can_view_logs: can_view_logs?,
        can_delete: can_delete?,
        can_manage_faces: can_manage_faces?
      }
    end

    def index_summary
      {
        can_view: can_view?,
        can_delete: can_delete?,
        can_manage_faces: can_manage_faces?
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
      @viewer && @image && @viewer.id == @image.owner_id
    end

    def viewer_is_assignee?
      return false unless @viewer && @image

      @image.face_records_dataset.where(assigned_user_id: @viewer.id).any?
    end
  end
end
