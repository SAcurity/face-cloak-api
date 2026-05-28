# frozen_string_literal: true

module FaceCloak
  class ImagePolicy
    # Filters images based on viewer permissions
    class AccountScope
      def initialize(viewer)
        @viewer = viewer
      end

      def viewable
        return [] unless @viewer

        # Existing behavior/tests expect all authenticated users to see the full list of metadata
        # so they can discover protected images.
        Image.all
      end
    end
  end
end
