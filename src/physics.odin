package src

import "core:math"
import "core:math/linalg"

CollisionInfo :: struct {
	Point:               Vector2,
	PenetrationDistance: f32,
}

Rect :: struct {
	Min: Vector2,
	Max: Vector2,
}

ClosestPointInARect :: #force_inline proc(Point: Vector2, RectIn: Rect) -> Vector2 {
	result: Vector2
	result.x = math.clamp(Point.x, RectIn.Min.x, RectIn.Max.x)
	result.y = math.clamp(Point.y, RectIn.Min.y, RectIn.Max.y)
	return result
}

CirclePointCollision :: proc(
	CirclePos: Vector2,
	CircleRadius: f32,
	Point: Vector2,
) -> (
	bool,
	CollisionInfo,
) {
	distance := linalg.vector_length(CirclePos - Point)
	hitInfo: CollisionInfo
	if distance < CircleRadius {
		hitInfo.PenetrationDistance = CircleRadius - distance
		hitInfo.Point = {Point.x, Point.y}
		return true, hitInfo
	}
	return false, hitInfo
}

CircleRectCollision :: proc(
	CirclePos: Vector2,
	CircleRadius: f32,
	RectIn: Rect,
) -> (
	bool,
	CollisionInfo,
) {
	closestPoint := ClosestPointInARect(CirclePos, RectIn)
	hit, info := CirclePointCollision(CirclePos, CircleRadius, closestPoint)

	return hit, info
}

RectContainsPoint :: proc(RectIn: Rect, Point: Vector2) -> bool {
	return(
		Point.x <= RectIn.Max.x &&
		Point.x >= RectIn.Min.x &&
		Point.y <= RectIn.Max.y &&
		Point.y >= RectIn.Min.y \
	)
}

Project :: #force_inline proc(InVector: Vector2, Normal: Vector2) -> Vector2 {
	dot: f32 = linalg.dot(InVector, Normal)
	return InVector - (dot * Normal)
}