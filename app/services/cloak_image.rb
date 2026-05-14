# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'securerandom'

module FaceCloak
  # Service object to apply privacy filters through OpenCV.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
  class CloakImage
    CACHE_DIR = 'db/local/storage/cache'
    SCRIPT_PATH = 'app/lib/opencv_cloak_image.py'
    AI_CLOAK_TYPES = %w[sunglasses mask comic].freeze
    LOCAL_FILTER_X_PADDING = 0.08
    LOCAL_FILTER_Y_PADDING = 0.12
    SOFT_MASK_SOLID_RADIUS = 0.82
    LANDMARK_WIDTH_FACTOR = 2.6
    LANDMARK_HEIGHT_FACTOR = 2.3

    def self.call(image:)
      FileUtils.mkdir_p(CACHE_DIR)
      image.refresh

      full_cache_path = File.join(CACHE_DIR, "full_#{image.id}_#{image.privacy_hash}.png")
      return File.binread(full_cache_path) if File.exist?(full_cache_path)

      source_path = ImageStorage.local_path(image.file_data)
      local_faces, working_path, temp_paths = prepare_cloak_inputs(source_path, image.ordered_face_records)
      render_with_opencv(
        input_path: working_path,
        output_path: full_cache_path,
        faces: local_faces
      )
      File.binread(full_cache_path)
    ensure
      temp_paths&.each { |path| FileUtils.rm_f(path) }
    end

    def self.prepare_cloak_inputs(source_path, faces)
      temp_paths = []
      local_faces = []
      ai_patches = []

      faces.each do |face|
        payload = face_payload(face)
        if ai_cloak?(payload[:cloak_type])
          begin
            ai_patches << build_ai_patch(source_path, face, temp_paths)
          rescue GeminiApi::NoApiKeyError
            # Skip AI rendering without Gemini key; preserve the intended style as a fallback
            Api.logger.warn "AI Inpainting skipped (#{payload[:cloak_type]}): Gemini not configured"
            local_faces << ai_fallback_payload(payload)
          rescue StandardError => e
            # Other Gemini errors: retry once, then fallback
            Api.logger.warn "AI Inpainting failed (#{payload[:cloak_type]}): #{e.class}: #{e.message}"
            local_faces << ai_fallback_payload(payload)
          end
        else
          local_faces << payload
        end
      end

      working_path = compose_ai_patches(source_path, ai_patches, temp_paths)
      [local_faces, working_path, temp_paths]
    end

    def self.render_with_opencv(input_path:, output_path:, faces:)
      payload = JSON.generate(faces:)
      stdout, stderr, status = Open3.capture3(FaceDetector.python_bin, SCRIPT_PATH, input_path, output_path,
                                              stdin_data: payload)
      return if status.success? && File.exist?(output_path)

      message = stderr.to_s.empty? ? stdout.to_s : stderr.to_s
      raise "OpenCV cloak rendering failed: #{message.strip}"
    end

    def self.build_ai_patch(source_path, face, temp_paths)
      context_path = temp_file_path('context')
      mask_path = temp_file_path('mask')
      patch_key = ai_patch_cache_key(face)
      patch_path = ai_patch_local_path(face)
      temp_paths.push(context_path, mask_path)

      metadata = prepare_ai_context(input_path: source_path, context_path:, mask_path:, face: face_payload(face))
      if ImageStorage.exist?(patch_key)
        patch_path = ImageStorage.local_path(patch_key)
      else
        patch_blob = GeminiApi.inpaint_image(File.binread(context_path), File.binread(mask_path),
                                             ai_prompt(face.effective_cloak_type))
        FileUtils.mkdir_p(File.dirname(patch_path))
        File.binwrite(patch_path, patch_blob)
        ImageStorage.put_file(patch_key, patch_path, content_type: 'image/png')
      end
      { patch_path:, metadata: }
    end

    def self.compose_ai_patches(source_path, ai_patches, temp_paths)
      return source_path if ai_patches.empty?

      working_path = source_path
      ai_patches.each do |patch|
        output_path = temp_file_path('ai')
        temp_paths << output_path
        apply_ai_patch(input_path: working_path, patch_path: patch[:patch_path], output_path:,
                       metadata: patch[:metadata])
        working_path = output_path
      end
      working_path
    end

    def self.prepare_ai_context(input_path:, context_path:, mask_path:, face:)
      payload = JSON.generate(face:)
      stdout, stderr, status = Open3.capture3(FaceDetector.python_bin, SCRIPT_PATH, 'prepare-ai', input_path,
                                              context_path, mask_path, stdin_data: payload)
      raise "OpenCV AI context preparation failed: #{stderr.strip}" unless status.success?

      JSON.parse(stdout, symbolize_names: true)
    end

    def self.apply_ai_patch(input_path:, patch_path:, output_path:, metadata:)
      stdout, stderr, status = Open3.capture3(FaceDetector.python_bin, SCRIPT_PATH, 'apply-ai-patch', input_path,
                                              patch_path, output_path, stdin_data: JSON.generate(metadata:))
      return if status.success? && File.exist?(output_path)

      message = stderr.to_s.empty? ? stdout.to_s : stderr.to_s
      raise "OpenCV AI patch composition failed: #{message.strip}"
    end

    def self.ai_prompt(type)
      prompts = {
        'sunglasses' => 'CRITICAL TASK: Apply realistic dark sunglasses to this face. ' \
                        'Front-facing: Draw TWO symmetric dark lenses covering both eyes with a thin bridge. ' \
                        'Profile/side-facing: Apply sunglasses to the visible eye, fitting the face angle. ' \
                        'Do not add a medical mask, mouth covering, dark block, or shadow below the sunglasses. ' \
                        'MUST INCLUDE: Realistic reflections, correct shading, gradient effects on lenses. ' \
                        'The result must be photorealistic and seamlessly blended with the existing lighting.',
        'mask' => 'CRITICAL TASK: Apply a medical mask to this face. ' \
                  'Only edit the nose and mouth region selected by the mask. ' \
                  'The mask MUST cover the nose and mouth area. ' \
                  'Do not alter the eyes, hair, background, clothing, or face position. ' \
                  'Match the fabric color and texture to common medical masks (blue, white, or similar). ' \
                  'Include proper shading and wrinkles to look realistic. ' \
                  'Ensure the mask edges blend naturally with the face. ' \
                  'This is a privacy protection task—the mask must be clearly visible.',
        'comic' => 'CRITICAL TASK: Transform this face into pop-art comic book style. ' \
                   'MUST APPLY: Bold black outlines around facial features. ' \
                   'Reduce the color palette to 3-5 bright colors. ' \
                   'Add halftone dots or comic book texture. ' \
                   'The result must be obviously stylized and visually distinct from the original. ' \
                   'This is an artistic transformation—the face must be unrecognizable.'
      }
      prompts[type] || 'Inpaint this face naturally maintaining its appearance'
    end

    def self.ai_cloak?(type)
      AI_CLOAK_TYPES.include?(type)
    end

    def self.ai_fallback_payload(payload)
      payload.merge(cloak_type: payload[:cloak_type] == 'sunglasses' ? 'sunglasses' : 'blur')
    end

    def self.temp_file_path(prefix)
      File.join(CACHE_DIR, "#{prefix}_#{SecureRandom.hex}.png")
    end

    def self.ai_patch_cache_key(face)
      File.join('cache/patches', face.id.to_s, "#{face.effective_cloak_type}.png")
    end

    def self.ai_patch_local_path(face)
      File.join(CACHE_DIR, "patch_#{face.id}_#{face.effective_cloak_type}.png")
    end

    def self.face_payload(face)
      {
        id: face.id,
        cloak_type: face.effective_cloak_type,
        x_min: face.x_min,
        y_min: face.y_min,
        x_max: face.x_max,
        y_max: face.y_max,
        landmarks: face.respond_to?(:landmarks_map) ? face.landmarks_map : {}
      }
    end

    def self.get_pixel_coords(face, width, height)
      bbox_pixel_coords(face, width, height)
    end

    def self.bbox_pixel_coords(face, width, height)
      x_min = face.x_min || 0.0
      x_max = face.x_max || 1.0
      y_min = face.y_min || 0.0
      y_max = face.y_max || 1.0

      pw = (x_max - x_min) * LOCAL_FILTER_X_PADDING
      ph = (y_max - y_min) * LOCAL_FILTER_Y_PADDING
      l = ((x_min - pw) * width).to_i
      t = ((y_min - ph) * height).to_i
      r = ((x_max + pw) * width).to_i
      b = ((y_max + ph) * height).to_i
      l = l.clamp(0, width - 2)
      t = t.clamp(0, height - 2)
      r = r.clamp(l + 2, width - 1)
      b = b.clamp(t + 2, height - 1)
      [l, t, r - l, b - t]
    end

    def self.landmark_face_box(face, width, height)
      points = landmark_pixel_points(face, width, height)
      return nil unless points[:left_eye] && points[:right_eye]

      eye_mid_x = (points[:left_eye][0] + points[:right_eye][0]) / 2.0
      eye_mid_y = (points[:left_eye][1] + points[:right_eye][1]) / 2.0
      eye_distance = distance(points[:left_eye], points[:right_eye])
      return nil if eye_distance < 2.0

      center_x = points.dig(:nose, 0) || eye_mid_x
      center_y = landmark_center_y(points, eye_mid_y, eye_distance)
      box_w = eye_distance * LANDMARK_WIDTH_FACTOR
      box_h = landmark_box_height(points, eye_mid_y, eye_distance, box_w)
      clamp_box(center_x - (box_w / 2.0), center_y - (box_h / 2.0), box_w, box_h, width, height)
    end

    def self.landmark_center_y(points, eye_mid_y, eye_distance)
      return eye_mid_y + ((points[:mouth][1] - eye_mid_y) * 0.55) if points[:mouth]
      return eye_mid_y + ((points[:nose][1] - eye_mid_y) * 0.9) if points[:nose]

      eye_mid_y + (eye_distance * 0.75)
    end

    def self.landmark_box_height(points, eye_mid_y, eye_distance, box_w)
      if points[:mouth]
        [((points[:mouth][1] - eye_mid_y).abs * LANDMARK_HEIGHT_FACTOR), box_w * 1.15].max
      else
        [eye_distance * 3.0, box_w * 1.15].max
      end
    end

    def self.landmark_pixel_points(face, width, height)
      landmarks = face.respond_to?(:landmarks_map) ? face.landmarks_map : {}
      landmarks.each_with_object({}) do |(key, point), output|
        pixel_point = landmark_pixel_point(point, width, height)
        output[key.to_sym] = pixel_point if pixel_point
      end
    rescue JSON::ParserError, TypeError
      {}
    end

    def self.landmark_pixel_point(point, width, height)
      return nil unless point.is_a?(Array) && point.length == 2

      y = normalized_coordinate(point[0])
      x = normalized_coordinate(point[1])
      return nil unless x && y

      [(x * width).to_f, (y * height).to_f]
    end

    def self.normalized_coordinate(value)
      coordinate = Float(value)
      coordinate /= 1000.0 if coordinate > 1.0
      coordinate.clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      nil
    end

    def self.distance(point_a, point_b)
      Math.sqrt(((point_a[0] - point_b[0])**2) + ((point_a[1] - point_b[1])**2))
    end

    def self.clamp_box(left, top, box_w, box_h, width, height)
      l = left.to_i.clamp(0, width - 2)
      t = top.to_i.clamp(0, height - 2)
      r = (left + box_w).to_i.clamp(l + 2, width - 1)
      b = (top + box_h).to_i.clamp(t + 2, height - 1)
      [l, t, r - l, b - t]
    end

    def self.soft_mask_alpha(distance)
      return 1.0 if distance <= SOFT_MASK_SOLID_RADIUS

      (1.0 - distance) / (1.0 - SOFT_MASK_SOLID_RADIUS)
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
end
