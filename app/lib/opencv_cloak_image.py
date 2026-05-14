#!/usr/bin/env python3
import json
import sys
from pathlib import Path

import cv2
import numpy as np

LOCAL_FILTER_X_PADDING = 0.08
LOCAL_FILTER_Y_PADDING = 0.12
SOFT_MASK_SOLID_RADIUS = 0.82


def bbox_pixel_coords(face, width, height):
    x_min = float_or_default(face.get("x_min"), 0.0)
    x_max = float_or_default(face.get("x_max"), 1.0)
    y_min = float_or_default(face.get("y_min"), 0.0)
    y_max = float_or_default(face.get("y_max"), 1.0)

    pad_w = (x_max - x_min) * LOCAL_FILTER_X_PADDING
    pad_h = (y_max - y_min) * LOCAL_FILTER_Y_PADDING
    left = int((x_min - pad_w) * width)
    top = int((y_min - pad_h) * height)
    right = int((x_max + pad_w) * width)
    bottom = int((y_max + pad_h) * height)

    left = clamp(left, 0, width - 2)
    top = clamp(top, 0, height - 2)
    right = clamp(right, left + 2, width - 1)
    bottom = clamp(bottom, top + 2, height - 1)
    return left, top, right - left, bottom - top


def float_or_default(value, default):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def clamp(value, low, high):
    return max(low, min(value, high))


def apply_face_cloak(image, face):
    cloak_type = face.get("cloak_type") or "blur"
    if cloak_type == "unveil":
        return

    height, width = image.shape[:2]
    left, top, box_w, box_h = bbox_pixel_coords(face, width, height)
    if box_w < 2 or box_h < 2:
        return

    if cloak_type == "pixelate":
        apply_mosaic(image, left, top, box_w, box_h)
    elif cloak_type == "sunglasses":
        apply_sunglasses(image, left, top, box_w, box_h)
    elif cloak_type == "comic":
        apply_comic(image, left, top, box_w, box_h)
    else:
        apply_smooth_blur(image, left, top, box_w, box_h)


def apply_smooth_blur(image, left, top, width, height):
    region = image[top : top + height, left : left + width].copy()
    blurred = region
    for factor in (10, 14, 18):
        small_w = max(2, int(width / factor))
        small_h = max(2, int(height * small_w / width))
        small = cv2.resize(blurred, (small_w, small_h), interpolation=cv2.INTER_LINEAR)
        blurred = cv2.resize(small, (width, height), interpolation=cv2.INTER_LINEAR)
    blend_ellipse(image, blurred, left, top, feather=True)


def apply_mosaic(image, left, top, width, height):
    region = image[top : top + height, left : left + width].copy()
    small_w = max(2, int(width / 20.0))
    small_h = max(2, int(height * small_w / width))
    small = cv2.resize(region, (small_w, small_h), interpolation=cv2.INTER_NEAREST)
    mosaic = cv2.resize(small, (width, height), interpolation=cv2.INTER_NEAREST)
    blend_ellipse(image, mosaic, left, top, feather=False)


def apply_comic(image, left, top, width, height):
    region = image[top : top + height, left : left + width].copy()
    smoothed = cv2.bilateralFilter(region, 9, 75, 75)
    gray = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)
    edges = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C, cv2.THRESH_BINARY, 9, 6)
    edges = cv2.cvtColor(edges, cv2.COLOR_GRAY2BGR)
    comic = cv2.bitwise_and(smoothed, edges)
    blend_ellipse(image, comic, left, top, feather=True)


def apply_sunglasses(image, left, top, width, height):
    # Detect profile (side-facing) vs front-facing based on width-to-height ratio.
    # Profile faces are typically narrower (width < 0.7 * height).
    is_profile = width < (height * 0.7)
    
    lens_w = max(2, int(width * 0.34))
    lens_h = max(2, int(height * 0.18))
    gap = max(1, int(width * 0.06))
    y = top + int(height * 0.33)
    color = (12, 16, 22)

    if is_profile:
        # Profile face: draw sunglasses on the visible eye (right side, assume left profile).
        # Position lens on the right side of the face area.
        x = left + int(width * 0.65)
        draw_filled_ellipse_rect(image, x, y, lens_w, lens_h, color)
    else:
        # Front-facing: draw symmetric sunglasses with bridge.
        total_w = (lens_w * 2) + gap
        x = left + int((width - total_w) / 2)
        draw_filled_ellipse_rect(image, x, y, lens_w, lens_h, color)
        draw_filled_ellipse_rect(image, x + lens_w + gap, y, lens_w, lens_h, color)
        cv2.rectangle(
            image,
            (x + lens_w, y + int(lens_h * 0.39)),
            (x + lens_w + gap, y + int(lens_h * 0.61)),
            color,
            thickness=-1,
        )


def draw_filled_ellipse_rect(image, left, top, width, height, color):
    center = (left + width // 2, top + height // 2)
    axes = (max(1, width // 2), max(1, height // 2))
    cv2.ellipse(image, center, axes, 0, 0, 360, color, thickness=-1)


def blend_ellipse(image, filtered_region, left, top, feather):
    height, width = filtered_region.shape[:2]
    mask = ellipse_alpha_mask(width, height, feather)
    region = image[top : top + height, left : left + width]
    alpha = mask[:, :, np.newaxis]
    blended = (filtered_region * alpha) + (region * (1.0 - alpha))
    image[top : top + height, left : left + width] = blended.astype(np.uint8)


def ellipse_alpha_mask(width, height, feather):
    y_indices, x_indices = np.ogrid[:height, :width]
    rx = width / 2.0
    ry = height / 2.0
    cx = rx
    cy = ry
    distance = np.sqrt(((x_indices - cx) ** 2 / (rx**2)) + ((y_indices - cy) ** 2 / (ry**2)))
    if feather:
        alpha = np.where(distance <= SOFT_MASK_SOLID_RADIUS, 1.0, (1.0 - distance) / (1.0 - SOFT_MASK_SOLID_RADIUS))
    else:
        alpha = np.where(distance <= 1.0, 1.0, 0.0)
    return np.clip(alpha, 0.0, 1.0)


def context_window(face, width, height):
    left, top, face_w, face_h = bbox_pixel_coords(face, width, height)
    context_left = max(0, left - int(face_w * 1.5))
    context_top = max(0, top - int(face_h * 1.5))
    context_right = min(width - 1, left + face_w + int(face_w * 1.5))
    context_bottom = min(height - 1, top + face_h + int(face_h * 1.5))
    return {
        "cx": context_left,
        "cy": context_top,
        "cw": context_right - context_left,
        "ch": context_bottom - context_top,
        "fx": left - context_left,
        "fy": top - context_top,
        "fw": face_w,
        "fh": face_h,
    }


def prepare_ai_context(input_path, context_path, mask_path, face):
    image = cv2.imread(input_path, cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"Unable to read image: {input_path}")

    height, width = image.shape[:2]
    metadata = context_window(face, width, height)
    cx, cy, cw, ch = metadata["cx"], metadata["cy"], metadata["cw"], metadata["ch"]
    context = image[cy : cy + ch, cx : cx + cw]
    mask = np.zeros((ch, cw), dtype=np.uint8)

    center = (metadata["fx"] + metadata["fw"] // 2, metadata["fy"] + metadata["fh"] // 2)
    axes = (max(1, int(metadata["fw"] / 1.5)), max(1, int(metadata["fh"] / 1.5)))
    cv2.ellipse(mask, center, axes, 0, 0, 360, 255, thickness=-1)

    Path(context_path).parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(context_path, context):
        raise RuntimeError(f"Unable to write AI context: {context_path}")
    if not cv2.imwrite(mask_path, mask):
        raise RuntimeError(f"Unable to write AI mask: {mask_path}")

    print(json.dumps(metadata))


def apply_ai_patch(input_path, patch_path, output_path, metadata):
    image = cv2.imread(input_path, cv2.IMREAD_COLOR)
    patch = cv2.imread(patch_path, cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"Unable to read image: {input_path}")
    if patch is None:
        raise RuntimeError(f"Unable to read AI patch: {patch_path}")

    cx, cy, cw, ch = metadata["cx"], metadata["cy"], metadata["cw"], metadata["ch"]
    patch = cv2.resize(patch, (cw, ch), interpolation=cv2.INTER_LINEAR)
    mask = ai_face_alpha_mask(cw, ch, metadata["fx"], metadata["fy"], metadata["fw"], metadata["fh"])
    region = image[cy : cy + ch, cx : cx + cw]
    alpha = mask[:, :, np.newaxis]
    image[cy : cy + ch, cx : cx + cw] = ((patch * alpha) + (region * (1.0 - alpha))).astype(np.uint8)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(output_path, image):
        raise RuntimeError(f"Unable to write AI composed image: {output_path}")


def ai_face_alpha_mask(width, height, fx, fy, face_w, face_h):
    y_indices, x_indices = np.ogrid[:height, :width]
    rx = face_w / 2.0
    ry = face_h / 2.0
    cx = fx + rx
    cy = fy + ry
    distance = np.sqrt(((x_indices - cx) ** 2 / (rx**2)) + ((y_indices - cy) ** 2 / (ry**2)))
    alpha = np.where(distance > 1.0, 0.0, np.where(distance > 0.75, (1.0 - distance) / 0.25, 1.0))
    return np.clip(alpha, 0.0, 1.0)


def render(input_path, output_path, faces):
    image = cv2.imread(input_path, cv2.IMREAD_COLOR)
    if image is None:
        raise RuntimeError(f"Unable to read image: {input_path}")

    for face in faces:
        apply_face_cloak(image, face)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    success = cv2.imwrite(output_path, image)
    if not success:
        raise RuntimeError(f"Unable to write image: {output_path}")


def main():
    if len(sys.argv) < 3:
        print("usage: opencv_cloak_image.py [prepare-ai|apply-ai-patch] ...", file=sys.stderr)
        sys.exit(2)

    try:
        if sys.argv[1] == "prepare-ai":
            payload = json.load(sys.stdin)
            prepare_ai_context(sys.argv[2], sys.argv[3], sys.argv[4], payload["face"])
        elif sys.argv[1] == "apply-ai-patch":
            payload = json.load(sys.stdin)
            apply_ai_patch(sys.argv[2], sys.argv[3], sys.argv[4], payload["metadata"])
        else:
            payload = json.load(sys.stdin)
            render(sys.argv[1], sys.argv[2], payload.get("faces", []))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
