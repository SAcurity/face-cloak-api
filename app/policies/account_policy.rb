# frozen_string_literal: true

module FaceCloak
  # Authorization rules for Account resources
  class AccountPolicy
    RESOURCE = 'accounts'

    def initialize(viewer, target = viewer, auth_scope: AuthScope.new)
      @viewer = viewer
      @target = target
      @auth_scope = auth_scope.is_a?(AuthScope) ? auth_scope : AuthScope.new(auth_scope)
    end

    def can_view?
      can_read? && (viewer_is_self? || admin?)
    end

    def can_edit?
      can_write? && (viewer_is_self? || admin?)
    end

    def can_delete?
      can_write? && (viewer_is_self? || (admin? && !viewer_is_self?))
    end

    def can_view_all?
      can_read? && admin?
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
        can_edit: can_edit?,
        can_delete: can_delete?
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

    def can_read?
      @auth_scope.can_read?(RESOURCE)
    end

    def can_write?
      @auth_scope.can_write?(RESOURCE)
    end

    def viewer_is_self?
      @viewer && @target && @viewer.id == @target.id
    end
  end
end
