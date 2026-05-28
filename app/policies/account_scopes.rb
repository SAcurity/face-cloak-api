# frozen_string_literal: true

module FaceCloak
  class AccountPolicy
    # Filters accounts based on viewer permissions
    class AccountScope
      def initialize(viewer)
        @viewer = viewer
      end

      def viewable
        return [] unless @viewer

        if @viewer.admin?
          Account.all
        else
          [@viewer]
        end
      end
    end
  end
end
