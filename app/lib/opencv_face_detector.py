#!/usr/bin/env python3
import json
import sys
from pathlib import Path

import cv2

MODEL_PATH = Path(__file__).resolve().parents[2] / "vendor/models/face_detection_yunet_2023mar.onnx"


def detect_faces(image_path):
    image = cv2.imread(image_path)
    if image is None:
        raise RuntimeError(f"Unable to read image: {image_path}")

    height, width = image.shape[:2]
    if MODEL_PATH.exists():
        return detect_with_yunet(image, width, height)

    return detect_with_haar(image, width, height)


def detection_payload(x, y, w, h, width, height):
    return {
        "box": [
            (y / height) * 1000.0,
            (x / width) * 1000.0,
            ((y + h) / height) * 1000.0,
            ((x + w) / width) * 1000.0,
        ]
    }


def detect_with_yunet(image, width, height):
    detector = cv2.FaceDetectorYN_create(
        str(MODEL_PATH),
        "",
        (width, height),
        score_threshold=0.75,
        nms_threshold=0.30,
        top_k=5000,
    )
    _, detections = detector.detect(image)
    if detections is None:
        return []

    return [
        detection_payload(float(x), float(y), float(w), float(h), width, height)
        for x, y, w, h, *_rest in detections
    ]


def detect_with_haar(image, width, height):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    gray = cv2.equalizeHist(gray)

    cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    detector = cv2.CascadeClassifier(cascade_path)
    if detector.empty():
        raise RuntimeError(f"Unable to load OpenCV face cascade: {cascade_path}")

    min_size = max(24, min(width, height) // 30)
    detections = detector.detectMultiScale(
        gray,
        scaleFactor=1.05,
        minNeighbors=6,
        minSize=(min_size, min_size),
        flags=cv2.CASCADE_SCALE_IMAGE,
    )

    return [
        detection_payload(float(x), float(y), float(w), float(h), width, height)
        for (x, y, w, h) in detections
    ]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: opencv_face_detector.py IMAGE_PATH", file=sys.stderr)
        sys.exit(2)

    try:
        print(json.dumps(detect_faces(sys.argv[1])))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
