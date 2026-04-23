# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Test ActionType Module' do
  it 'HAPPY: should recognize valid actions' do
    _(FaceCloak::ActionType.valid?('create')).must_equal true
    _(FaceCloak::ActionType.valid?('assign')).must_equal true
  end

  it 'SAD: should identify invalid actions' do
    _(FaceCloak::ActionType.valid?('delete')).must_equal false
    _(FaceCloak::ActionType.valid?('')).must_equal false
  end

  it 'HAPPY: should normalize valid actions' do
    _(FaceCloak::ActionType.normalize('respond')).must_equal 'respond'
  end
end
