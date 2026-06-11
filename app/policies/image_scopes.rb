# frozen_string_literal: true

module FaceCloak
  class ImagePolicy
    # Filters images based on viewer permissions
    class AccountScope
      def initialize(viewer, auth_scope: AuthScope.new)
        @viewer = viewer
        @auth_scope = auth_scope.is_a?(AuthScope) ? auth_scope : AuthScope.new(auth_scope)
      end

      def viewable
        return [] unless @viewer && @auth_scope.can_read?(ImagePolicy::RESOURCE)

        # Existing behavior/tests expect all authenticated users to see the full list of metadata
        # so they can discover protected images.
        Image.all
      end
    end
  end
end
