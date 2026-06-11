# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test AuthScope Library' do
  it 'HAPPY: defaults to full write scope' do
    scope = FaceCloak::AuthScope.new

    _(scope.can_read?('images')).must_equal true
    _(scope.can_write?('images')).must_equal true
    _(scope.to_s).must_equal FaceCloak::AuthScope::FULL
  end

  it 'HAPPY: read-only wildcard reads but does not write' do
    scope = FaceCloak::AuthScope.new(FaceCloak::AuthScope::READ_ONLY)

    _(scope.can_read?('accounts')).must_equal true
    _(scope.can_write?('accounts')).must_equal false
  end

  it 'HAPPY: write implies read for the same resource' do
    scope = FaceCloak::AuthScope.new('face_records:write')

    _(scope.can_read?('face_records')).must_equal true
    _(scope.can_write?('face_records')).must_equal true
    _(scope.can_read?('images')).must_equal false
  end

  it 'HAPPY: supports multiple resource scopes' do
    scope = FaceCloak::AuthScope.new('images:read face_records:write')

    _(scope.can_read?('images')).must_equal true
    _(scope.can_write?('images')).must_equal false
    _(scope.can_write?('face_records')).must_equal true
  end

  it 'SECURITY: rejects malformed scopes' do
    _ { FaceCloak::AuthScope.new('images') }.must_raise FaceCloak::AuthScope::InvalidScopeError
    _ { FaceCloak::AuthScope.new('images:admin') }.must_raise FaceCloak::AuthScope::InvalidScopeError
    _ { FaceCloak::AuthScope.new('') }.must_raise FaceCloak::AuthScope::InvalidScopeError
  end
end
