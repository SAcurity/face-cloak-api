# frozen_string_literal: true

module FaceCloak
  # Authorization rules for Account resources
  class AccountPolicy
    def initialize(viewer, target = viewer)
      @viewer = viewer
      @target = target
    end

    def can_view?
      viewer_is_self? || admin?
    end

    def can_edit?
      viewer_is_self? || admin?
    end

    def can_delete?
      admin? && !viewer_is_self?
    end

    def can_view_all?
      admin?
    end

    def summary
      {
        can_view: can_view?,
        can_edit: can_edit?,
        can_delete: can_delete?
      }
    end

    def index_summary
      {
        can_view: can_view?,
        can_edit: can_edit?
      }
    end

    def capabilities
      {
        is_admin: admin?,
        can_view_all: can_view_all?
      }
    end

    private

    def admin?
      @viewer&.admin? || false
    end

    def viewer_is_self?
      @viewer && @target && @viewer.id == @target.id
    end
  end
end
