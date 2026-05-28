# frozen_string_literal: true

module FaceCloak
  # Authorization rules for Image resources
  class ImagePolicy
    def initialize(viewer, image)
      @viewer = viewer
      @image = image
    end

    def can_view?
      # Allow all authenticated users to view (filtered) images to support discovery.
      @viewer != nil
    end

    def can_view_raw?
      viewer_is_owner? || admin?
    end

    def can_view_logs?
      viewer_is_owner? || admin?
    end

    def can_delete?
      viewer_is_owner? || admin?
    end

    def can_manage_faces?
      viewer_is_owner? || admin?
    end

    def summary
      {
        can_view: can_view?,
        can_view_raw: can_view_raw?,
        can_view_logs: can_view_logs?,
        can_delete: can_delete?,
        can_manage_faces: can_manage_faces?
      }
    end

    def index_summary
      {
        can_view: can_view?,
        can_delete: can_delete?
      }
    end

    private

    def admin?
      @viewer&.admin? || false
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
