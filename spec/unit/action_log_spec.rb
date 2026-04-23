# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test ActionLog Model Unit Logic' do
  before do
    wipe_database
    @img = FaceCloak::Image.create(seed_attributes(DATA[:images][0]))
    @face = @img.face_records.first
  end

  it 'HAPPY: should validate allowed actions (Model Unit Test)' do
    log = FaceCloak::ActionLog.new(face_record_id: @face.id, actor_id: 'a', action: 'create')
    _(log.valid?).must_equal true
  end

  it 'SAD: should reject invalid actions (Model Unit Test)' do
    log = FaceCloak::ActionLog.new(face_record_id: @face.id, actor_id: 'a', action: 'hack')
    _(log.valid?).must_equal false
  end
end
