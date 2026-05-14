# frozen_string_literal: true

require 'chunky_png'
require 'fileutils'
require 'base64'
require 'open3'
require 'securerandom'

module FaceCloak
  # Service object to apply professional privacy filters using Contextual AI Inpainting
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Naming/MethodParameterName
  class CloakImage
    CACHE_DIR = 'db/local/storage/cache'
    LOCAL_FILTER_X_PADDING = 0.08
    LOCAL_FILTER_Y_PADDING = 0.12
    SOFT_MASK_SOLID_RADIUS = 0.82
    LANDMARK_WIDTH_FACTOR = 2.6
    LANDMARK_HEIGHT_FACTOR = 2.3

    def self.call(image:) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      FileUtils.mkdir_p(CACHE_DIR)
      image.refresh
      latest_faces = image.ordered_face_records

      hash = image.privacy_hash
      full_cache_path = File.join(CACHE_DIR, "full_#{image.id}_#{hash}.png")

      # Use cache unless AI style is requested (for instant feedback during dev)
      has_ai = latest_faces.any? { |f| %w[sunglasses comic mask].include?(f.effective_cloak_type) }
      return File.binread(full_cache_path) if File.exist?(full_cache_path) && !has_ai

      original_path = ImageStorage.local_path(image.file_data)
      ws_png = File.join(CACHE_DIR, "ws_#{SecureRandom.hex}.png")
      prepare_working_png(original_path, ws_png)
      canvas = ChunkyPNG::Image.from_file(ws_png)
      width = canvas.width
      height = canvas.height

      latest_faces.each do |face|
        apply_face_cloak(canvas, face, width, height)
      end

      blob = canvas.to_blob
      File.binwrite(full_cache_path, blob)
      FileUtils.rm_f(ws_png)
      blob
    ensure
      FileUtils.rm_f(ws_png) if defined?(ws_png) && ws_png && File.exist?(ws_png)
    end

    def self.prepare_working_png(original_path, ws_png)
      FileUtils.mkdir_p(File.dirname(ws_png))

      _stdout, stderr, status = Open3.capture3(
        'sips', '-s', 'format', 'png', File.expand_path(original_path), '--out', File.expand_path(ws_png)
      )
      return if status.success? && File.exist?(ws_png)

      FaceCloak::Api.logger.warn("sips PNG conversion fallback for #{original_path}: #{stderr.strip}")
      FileUtils.cp(original_path, ws_png)
    rescue StandardError => e
      FaceCloak::Api.logger.warn("PNG preparation fallback for #{original_path}: #{e.message}")
      FileUtils.cp(original_path, ws_png)
    end

    def self.apply_face_cloak(canvas, face, width, height)
      type = face.effective_cloak_type
      return if type == 'unveil'

      case type
      when 'blur', 'pixelate'
        apply_local_cloak(canvas, face, type, width, height)
      when 'sunglasses', 'mask', 'comic'
        apply_ai_cloak(canvas, face, type, width, height)
      end
    end

    def self.apply_local_cloak(canvas, face, type, width, height)
      left, top, w, h = get_pixel_coords(face, width, height)
      return if w < 2 || h < 2

      case type
      when 'blur'
        apply_smooth_blur(canvas, left, top, w, h)
      when 'pixelate'
        apply_mosaic(canvas, left, top, w, h)
      when 'sunglasses'
        apply_sunglasses(canvas, left, top, w, h)
      end
    end

    def self.apply_ai_cloak(canvas, face, type, width, height)
      cx, cy, cw, ch, fx, fy, fw, fh = get_context_window(face, width, height)
      return if cw < 2 || ch < 2 || fw < 2 || fh < 2

      patch = get_ai_inpainted_patch(canvas, face, type, cx, cy, cw, ch, fx, fy, fw, fh)
      patch = normalize_ai_patch(patch, cw, ch)
      apply_ai_patch(canvas, patch, cx, cy, fx, fy, fw, fh)
    rescue StandardError => e
      FaceCloak::Api.logger.error "AI Inpainting Failed for #{type}: #{e.message}"
      apply_ai_fallback(canvas, face, type, width, height)
    end

    def self.apply_ai_fallback(canvas, face, type, width, height)
      left, top, w, h = get_pixel_coords(face, width, height)
      return if w < 2 || h < 2

      case type
      when 'sunglasses'
        apply_sunglasses(canvas, left, top, w, h)
      when 'mask', 'comic'
        apply_smooth_blur(canvas, left, top, w, h)
      end
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

    def self.get_context_window(face, width, height)
      l, t, fw, fh = bbox_pixel_coords(face, width, height)

      # Expand by ~1.5x in each direction to provide context for AI
      cl = [0, l - (fw * 1.5).to_i].max
      ct = [0, t - (fh * 1.5).to_i].max
      cr = [width - 1, l + fw + (fw * 1.5).to_i].min
      cb = [height - 1, t + fh + (fh * 1.5).to_i].min

      # Return context box, and face coordinates relative to the context box
      [cl, ct, cr - cl, cb - ct, l - cl, t - ct, fw, fh]
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

    def self.generate_mask(cw, ch, fx, fy, fw, fh)
      mask = ChunkyPNG::Image.new(cw, ch, ChunkyPNG::Color::BLACK)

      # Draw white ellipse over face, slightly larger to cover fully
      rx = (fw / 1.5)
      ry = (fh / 1.5)
      cx = fx + (fw / 2.0)
      cy = fy + (fh / 2.0)

      (0...cw).each do |dx|
        (0...ch).each do |dy|
          dist = ((((dx - cx)**2) / (rx**2)) + (((dy - cy)**2) / (ry**2)))
          mask.set_pixel(dx, dy, ChunkyPNG::Color::WHITE) if dist <= 1.0
        end
      end

      mask.to_blob
    end

    def self.get_ai_inpainted_patch(canvas, face, type, cx, cy, cw, ch, fx, fy, fw, fh)
      cache_path = File.join(CACHE_DIR, "patch_#{face.id}_#{type}.png")
      return ChunkyPNG::Image.from_file(cache_path) if File.exist?(cache_path)

      context_img = canvas.crop(cx, cy, cw, ch)
      mask_blob = generate_mask(cw, ch, fx, fy, fw, fh)

      prompts = {
        'sunglasses' => 'A highly realistic face wearing stylish dark sunglasses, ' \
                        'matching the lighting and blending seamlessly.',
        'mask' => 'A highly realistic face wearing a medical mask, matching the lighting and blending seamlessly.',
        'comic' => 'A pop-art comic book style face, blending into the surrounding image naturally.'
      }

      prompt = prompts[type] || 'Inpaint this face naturally'

      processed_blob = GeminiApi.inpaint_image(context_img.to_blob, mask_blob, prompt)
      File.binwrite(cache_path, processed_blob)
      ChunkyPNG::Image.from_file(cache_path)
    end

    def self.normalize_ai_patch(patch, width, height)
      return patch if patch.width == width && patch.height == height

      patch.resample_bilinear(width, height)
    end

    def self.apply_ai_patch(canvas, patch, cx, cy, fx, fy, fw, fh)
      (0...patch.width).each do |dx|
        (0...patch.height).each do |dy|
          alpha = ai_face_mask_alpha(dx, dy, fx, fy, fw, fh)
          next if alpha <= 0.0

          tx = cx + dx
          ty = cy + dy
          next if tx >= canvas.width || ty >= canvas.height

          src_pixel = patch.get_pixel(dx, dy)
          dst_pixel = canvas.get_pixel(tx, ty)
          blended = ChunkyPNG::Color.interpolate_quick(src_pixel, dst_pixel, (alpha * 255).to_i)
          canvas.set_pixel(tx, ty, blended)
        end
      end
    end

    def self.ai_face_mask_alpha(dx, dy, fx, fy, fw, fh)
      rx = fw / 2.0
      ry = fh / 2.0
      cx = fx + rx
      cy = fy + ry
      distance = Math.sqrt((((dx - cx)**2) / (rx**2)) + (((dy - cy)**2) / (ry**2)))
      return 0.0 if distance > 1.0

      distance > 0.75 ? (1.0 - distance) / 0.25 : 1.0
    end

    # Professional Smooth Blur (Bokeh-style)
    def self.apply_smooth_blur(canvas, left, top, w, h)
      region = canvas.crop(left, top, w, h)
      # Heavy downsample/upsample passes give privacy-grade soft focus.
      [10, 14, 18].each do |factor|
        sw = [2, w / factor.to_f].max.to_i
        sh = [2, (h * sw.to_f / w)].max.to_i
        region.resample_bilinear!(sw, sh)
        region.resample_bilinear!(w, h)
      end
      mask_ellipse(canvas, region, left, top, w, h, true)
    end

    def self.apply_mosaic(canvas, left, top, w, h)
      region = canvas.crop(left, top, w, h)
      sw = [2, w / 20.0].max.to_i
      sh = [2, (h * sw.to_f / w)].max.to_i
      region.resample_nearest_neighbor!(sw, sh)
      region.resample_nearest_neighbor!(w, h)
      mask_ellipse(canvas, region, left, top, w, h, false)
    end

    def self.apply_sunglasses(canvas, left, top, w, h)
      lens_w = [2, (w * 0.34).to_i].max
      lens_h = [2, (h * 0.18).to_i].max
      gap = [1, (w * 0.06).to_i].max
      y = top + (h * 0.33).to_i
      total_w = (lens_w * 2) + gap
      x = left + ((w - total_w) / 2)

      draw_rounded_rect(canvas, x, y, lens_w, lens_h, ChunkyPNG::Color.rgba(12, 16, 22, 245))
      draw_rounded_rect(canvas, x + lens_w + gap, y, lens_w, lens_h, ChunkyPNG::Color.rgba(12, 16, 22, 245))
      draw_bridge(canvas, x + lens_w, y + (lens_h / 2), gap, [1, (lens_h * 0.22).to_i].max)
    end

    def self.draw_rounded_rect(canvas, left, top, width, height, color)
      rx = width / 2.0
      ry = height / 2.0
      (0...width).each do |dx|
        (0...height).each do |dy|
          distance = (((dx - rx)**2) / (rx**2)) + (((dy - ry)**2) / (ry**2))
          next if distance > 1.0

          set_pixel_if_in_bounds(canvas, left + dx, top + dy, color)
        end
      end
    end

    def self.draw_bridge(canvas, left, center_y, width, height)
      (0...width).each do |dx|
        (0...height).each do |dy|
          set_pixel_if_in_bounds(canvas, left + dx, center_y - (height / 2) + dy, ChunkyPNG::Color::BLACK)
        end
      end
    end

    def self.set_pixel_if_in_bounds(canvas, x, y, color)
      return if x.negative? || y.negative? || x >= canvas.width || y >= canvas.height

      canvas.set_pixel(x, y, color)
    end

    def self.mask_ellipse(canvas, region, left, top, w, h, feather)
      rx = w / 2.0
      ry = h / 2.0
      (0...w).each do |dx|
        (0...h).each do |dy|
          dist = begin
            Math.sqrt((((dx - rx)**2) / (rx**2)) + (((dy - ry)**2) / (ry**2)))
          rescue StandardError
            2.0
          end
          next unless dist <= 1.0

          alpha = feather ? soft_mask_alpha(dist) : 1.0
          tx = left + dx
          ty = top + dy
          next if tx >= canvas.width || ty >= canvas.height

          src_pixel = region.get_pixel(dx, dy)
          dst_pixel = canvas.get_pixel(tx, ty)
          blended = ChunkyPNG::Color.interpolate_quick(src_pixel, dst_pixel, (alpha * 255).to_i)
          canvas.set_pixel(tx, ty, blended)
        end
      end
    end

    def self.soft_mask_alpha(distance)
      return 1.0 if distance <= SOFT_MASK_SOLID_RADIUS

      (1.0 - distance) / (1.0 - SOFT_MASK_SOLID_RADIUS)
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Naming/MethodParameterName
end
