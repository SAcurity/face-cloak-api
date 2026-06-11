# frozen_string_literal: true

module FaceCloak
  # Deletes an account after authorization and removes owned image files.
  class DeleteAccount
    class ForbiddenError < StandardError; end

    def self.call(viewer:, target:, auth_scope:)
      policy = AccountPolicy.new(viewer, target, auth_scope:)
      raise ForbiddenError, 'Forbidden' unless policy.can_delete?

      storage_keys = target.owned_images.map(&:file_data)
      target.destroy
      storage_keys.each { |key| ImageStorage.delete(key.to_s) }
      true
    end
  end
end
