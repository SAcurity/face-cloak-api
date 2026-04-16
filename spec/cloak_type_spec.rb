# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Test CloakType Module' do
  it 'HAPPY: should recognize valid cloak types' do
    _(FaceCloak::CloakType.valid?('blur')).must_equal true
    _(FaceCloak::CloakType.valid?('unveil')).must_equal true
  end

  it 'SAD: should identify invalid cloak types' do
    _(FaceCloak::CloakType.valid?('invisible')).must_equal false
  end

  it 'HAPPY: should normalize values' do
    _(FaceCloak::CloakType.normalize('pixelate')).must_equal 'pixelate'
    _(FaceCloak::CloakType.normalize(nil)).must_equal 'blur'
  end

  it 'SAD: should reject invalid cloak types' do
    _ { FaceCloak::CloakType.normalize('invalid') }.must_raise RuntimeError
  end
end
