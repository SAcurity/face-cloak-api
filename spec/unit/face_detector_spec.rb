# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FaceDetector Unit Logic' do
  it 'HAPPY: normalizes Vision face detections into detector coordinates' do
    faces = FaceCloak::FaceDetector.normalize([
                                                {
                                                  box: [100, 200, 300, 400]
                                                }
                                              ])

    _(faces).must_equal [
      {
        y_min: 100.0,
        x_min: 200.0,
        y_max: 300.0,
        x_max: 400.0
      }
    ]
  end

  it 'SAD: ignores malformed Vision detections' do
    faces = FaceCloak::FaceDetector.normalize([
                                                { box: [100, 200] },
                                                { box: ['bad', 200, 300, 400] },
                                                { no_box: true }
                                              ])

    _(faces).must_equal []
  end

  it 'HAPPY: detects faces locally when OpenCV runtime is available' do
    skip 'OpenCV face detector runtime is not available' unless FaceCloak::FaceDetector.available?

    faces = FaceCloak::FaceDetector.call(image_path: 'db/seeds/files/3-people.png')

    _(faces.length).must_equal 3
  end
end
