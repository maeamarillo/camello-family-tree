import 'dart:math';
import 'package:flutter/material.dart';

double distancePointToRect(Offset p, Rect r) {
  final dx = (p.dx < r.left)
      ? (r.left - p.dx)
      : (p.dx > r.right)
          ? (p.dx - r.right)
          : 0.0;

  final dy = (p.dy < r.top)
      ? (r.top - p.dy)
      : (p.dy > r.bottom)
          ? (p.dy - r.bottom)
          : 0.0;

  return sqrt(dx * dx + dy * dy);
}

Offset nearestPointOnRect(Offset p, Rect r) {
  final x = p.dx.clamp(r.left, r.right);
  final y = p.dy.clamp(r.top, r.bottom);
  return Offset(x, y);
}
