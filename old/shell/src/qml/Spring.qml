import QtQuick

// Overdamped spring solver — the exact §2.2 step-3 recipe:
// "each tile width chases its target through a spring (mass 0.1 · stiffness 170
//  · damping 13 — overdamped, ζ ≈ 1.58, visually settled in about 220 ms),
//  integrated every animation frame with two Euler substeps".
//
// Owners drive it from a FrameAnimation and write results into layout
// properties (width/height), so neighbours slide aside as the value moves.
QtObject {
    property real target: 0
    property real value: 0
    property real velocity: 0
    property real mass: 0.1
    property real stiffness: 170
    property real damping: 13

    function reset(v) {
        value = v
        velocity = 0
        target = v
    }

    function step(dt) {
        // two Euler substeps; dt clamped so a stalled frame can't explode
        var h = Math.min(dt, 0.05) / 2.0
        for (var i = 0; i < 2; ++i) {
            var acceleration = (stiffness * (target - value) - damping * velocity) / mass
            velocity += acceleration * h
            value += velocity * h
        }
    }
}
