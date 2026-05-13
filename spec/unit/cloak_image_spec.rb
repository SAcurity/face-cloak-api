# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test CloakImage Unit Logic' do
  it 'HAPPY: keeps local filter coordinates tight around the detected face' do
    face = face_record_box(0.4, 0.3, 0.6, 0.7)

    left, top, width, height = FaceCloak::CloakImage.get_pixel_coords(face, 100, 100)

    _(left).must_equal 38
    _(top).must_equal 25
    _(width).must_equal 23
    _(height).must_equal 49
  end

  it 'HAPPY: keeps renderer targeting on bounding boxes even when landmarks are available' do
    landmarks = {
      left_eye: [0.40, 0.46],
      right_eye: [0.40, 0.54],
      nose: [0.50, 0.50],
      mouth: [0.62, 0.50]
    }
    face = face_record_box(0.1, 0.1, 0.2, 0.2, landmarks)

    left, top, width, height = FaceCloak::CloakImage.get_pixel_coords(face, 100, 100)

    _(left).must_equal 9
    _(top).must_equal 8
    _(width).must_equal 11
    _(height).must_equal 13
  end

  it 'HAPPY: can derive a landmark face box without enabling it for rendering' do
    landmarks = {
      left_eye: [400, 460],
      right_eye: [400, 540],
      nose: [500, 500],
      mouth: [620, 500]
    }
    face = face_record_box(0.1, 0.1, 0.2, 0.2, landmarks)

    left, top, width, height = FaceCloak::CloakImage.landmark_face_box(face, 100, 100)

    _(left).must_equal 39
    _(top).must_equal 26
    _(width).must_equal 21
    _(height).must_equal 51
  end

  it 'HAPPY: keeps most of the blur mask opaque and only feathers the outer edge' do
    _(FaceCloak::CloakImage.soft_mask_alpha(0.80)).must_equal 1.0
    _(FaceCloak::CloakImage.soft_mask_alpha(0.91)).must_be :>, 0.4
    _(FaceCloak::CloakImage.soft_mask_alpha(1.0)).must_equal 0.0
  end

  it 'HAPPY: normalizes oversized AI patches before composing onto the source image' do
    canvas = ChunkyPNG::Image.new(20, 20, ChunkyPNG::Color::WHITE)
    oversized_patch = ChunkyPNG::Image.new(12, 18, ChunkyPNG::Color::BLACK)

    patch = FaceCloak::CloakImage.normalize_ai_patch(oversized_patch, 10, 10)
    canvas.compose!(patch, 10, 10)

    _(patch.width).must_equal 10
    _(patch.height).must_equal 10
  end

  it 'HAPPY: applies AI patches only inside the target face mask' do
    canvas = ChunkyPNG::Image.new(20, 10, ChunkyPNG::Color::WHITE)
    patch = ChunkyPNG::Image.new(20, 10, ChunkyPNG::Color::BLACK)

    FaceCloak::CloakImage.apply_ai_patch(canvas, patch, 0, 0, 2, 2, 4, 4)

    _(canvas.get_pixel(4, 4)).must_equal ChunkyPNG::Color::BLACK
    _(canvas.get_pixel(15, 4)).must_equal ChunkyPNG::Color::WHITE
  end

  it 'HAPPY: draws sunglasses locally for deterministic visual feedback' do
    canvas = ChunkyPNG::Image.new(100, 100, ChunkyPNG::Color::WHITE)

    FaceCloak::CloakImage.apply_sunglasses(canvas, 20, 20, 60, 60)

    _(canvas.get_pixel(38, 41)).wont_equal ChunkyPNG::Color::WHITE
    _(canvas.get_pixel(62, 41)).wont_equal ChunkyPNG::Color::WHITE
  end

  def face_record_box(x_min, y_min, x_max, y_max, landmarks = {})
    Struct.new(:x_min, :y_min, :x_max, :y_max, :landmarks_map).new(x_min, y_min, x_max, y_max, landmarks)
  end
end
