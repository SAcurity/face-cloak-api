# frozen_string_literal: true

module FaceCloak
  class AccountPolicy
    # Filters accounts based on viewer permissions
    class AccountScope
      def initialize(viewer, auth_scope: AuthScope.new)
        @viewer = viewer
        @auth_scope = auth_scope.is_a?(AuthScope) ? auth_scope : AuthScope.new(auth_scope)
      end

      def viewable
        return [] unless @viewer && @auth_scope.can_read?(AccountPolicy::RESOURCE)

        if @viewer.admin?
          Account.all
        else
          [@viewer]
        end
      end
    end
  end
end
