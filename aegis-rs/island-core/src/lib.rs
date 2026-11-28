//! island-core — the Dynamic Island's brain, in Rust.
//!
//! Ported 1:1 from the QML implementation (`shell/src/qml/Island.qml`,
//! `shell/src/qml/Tokens.qml` §2.4 Table 5b, docs/LIVE-ACTIVITY-API.md) so
//! the behavior contract survives the QML→Rust migration unchanged. The
//! renderer (layer-shell surface, blur, crossfade choreography) attaches in
//! `island-shell`; this crate owns ONLY the decisions:
//!
//! - which state the island is in (the priority stack),
//! - the geometry record that state resolves to (width/height/radius),
//! - how the geometry moves (the spring solver — mass 1 · stiffness 420 ·
//!   damping 28, the same constants the QML `Spring` uses),
//! - how activities rank, queue and retire.

/// The publish kinds (docs/LIVE-ACTIVITY-API.md — Table 5b, fixed).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Kind {
    /// Incoming call — `call`
    Call,
    /// Aegis ID state — `aegisId`
    AegisId,
    /// Countdown — `timer`
    Timer,
    /// Now Playing — `media`
    Media,
    /// AC transition, shell-owned — `charging`
    Charging,
    /// Everything else — `generic`
    Generic,
}

impl Kind {
    /// The priority order (Table 5b): `call > aegisId > timer > media >
    /// charging > generic`. Higher ranks first; the top TWO render as the
    /// split capsule; everything else queues.
    pub fn rank(self) -> u8 {
        match self {
            Kind::Call => 5,
            Kind::AegisId => 4,
            Kind::Timer => 3,
            Kind::Media => 2,
            Kind::Charging => 1,
            Kind::Generic => 0,
        }
    }

    /// The state name the geometry table keys on (`Tokens.islandStates`).
    pub fn state(self) -> &'static str {
        match self {
            Kind::Call => "call",
            Kind::AegisId => "aegisId",
            Kind::Timer => "timer",
            Kind::Media => "nowPlaying",
            Kind::Charging => "charging",
            Kind::Generic => "generic",
        }
    }
}

/// One geometry record per state (§2.4 Table 5b — width, height, radius).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Geometry {
    pub w: i32,
    pub h: i32,
    /// Radius tracks height (r = h/2) capped at 32, per `islandRadius()`.
    pub r: i32,
}

pub const IDLE_WIDTH: i32 = 104;
pub const IDLE_HEIGHT: i32 = 32;
/// The split lobes' widths (`lobeWidth()`) and the 8 px gap.
pub const LOBE_GAP: i32 = 8;

/// The per-kind lobe width in split mode (`Island.qml lobeWidth()`):
/// media 132 · call 150 · aegisId 128 · everything else 108.
pub fn lobe_width(kind: Kind) -> i32 {
    match kind {
        Kind::Media => 132,
        Kind::Call => 150,
        Kind::AegisId => 128,
        _ => 108,
    }
}

/// `Tokens.islandRadius(height)`: r = h/2, capped at 32 — the capsule
/// never grows rounder than the expanded states demand.
pub fn island_radius(h: i32) -> i32 {
    (h / 2).min(32)
}

/// The geometry the island resolves to for a given stack. `stack` holds
/// every live activity kind, ANY order. Single activity → its state's
/// record; two or more → the split capsule (the top two lobes, 8 px
/// apart); empty → idle.
pub fn resolve(stack: &[Kind]) -> Geometry {
    match stack.len() {
        0 => Geometry { w: IDLE_WIDTH, h: IDLE_HEIGHT, r: island_radius(IDLE_HEIGHT) },
        1 => state_geometry(stack[0]),
        _ => {
            let mut sorted: Vec<Kind> = stack.to_vec();
            sorted.sort_by(|a, b| b.rank().cmp(&a.rank()));
            let w = lobe_width(sorted[0]) + LOBE_GAP + lobe_width(sorted[1]);
            let h = IDLE_HEIGHT;
            Geometry { w, h, r: island_radius(h) }
        }
    }
}

/// The single-state geometry records (§2.4 Table 5b): Now Playing
/// 356×96 r32 · Call 300×64 · Aegis ID / Timer 200×56 r28 · Charging
/// 216×32 · Generic 300×56.
pub fn state_geometry(kind: Kind) -> Geometry {
    let (w, h) = match kind {
        Kind::Media => (356, 96),
        Kind::Call => (300, 64),
        Kind::AegisId => (200, 56),
        Kind::Timer => (200, 56),
        Kind::Charging => (216, IDLE_HEIGHT),
        Kind::Generic => (300, 56),
    };
    Geometry { w, h, r: island_radius(h) }
}

/// The damped spring behind every geometry move (`Tokens.islandSpring*`:
/// mass 1 · stiffness 420 · damping 28). Semi-implicit Euler — the same
/// integrator shape the QML `Spring` component uses in `FrameAnimation`,
/// with the frame time clamped so a stalled compositor cannot launch the
/// capsule across the screen.
#[derive(Clone, Debug)]
pub struct Spring {
    pub value: f64,
    velocity: f64,
    pub target: f64,
    mass: f64,
    stiffness: f64,
    damping: f64,
}

impl Spring {
    pub fn new(initial: f64) -> Self {
        Spring {
            value: initial,
            velocity: 0.0,
            target: initial,
            mass: 1.0,
            stiffness: 420.0,
            damping: 28.0,
        }
    }

    pub fn set_target(&mut self, t: f64) {
        self.target = t;
    }

    /// One frame. `dt` is seconds (a 60 Hz frame ≈ 0.0167); clamped to
    /// 50 ms so a hiccup never injects a huge step (the W66 morph-switch
    /// lesson: the solver must never teleports the geometry).
    pub fn step(&mut self, dt: f64) {
        let dt = dt.min(0.05);
        let a = -(self.stiffness * (self.value - self.target)
                  + self.damping * self.velocity)
                / self.mass;
        self.velocity += a * dt;
        self.value += self.velocity * dt;
    }

    /// The morph switch (W66): `islandMorph: false` snaps straight to the
    /// target — no solver time, the capsule still reaches every shape.
    pub fn snap(&mut self) {
        self.value = self.target;
        self.velocity = 0.0;
    }

    pub fn settled(&self) -> bool {
        (self.value - self.target).abs() < 0.05
            && self.velocity.abs() < 0.05
    }
}

/// The island's whole brain: a stack of live activities, resolved into
/// the geometry the springs chase. The renderer reads `.geometry()` each
/// frame and steps `.width_spring()` / `.height_spring()` toward it.
#[derive(Default)]
pub struct Island {
    stack: Vec<Kind>,
    width_spring: Option<Spring>,
    height_spring: Option<Spring>,
}

impl Island {
    pub fn new() -> Self {
        let mut i = Island::default();
        i.width_spring = Some(Spring::new(IDLE_WIDTH as f64));
        i.height_spring = Some(Spring::new(IDLE_HEIGHT as f64));
        i
    }

    /// Publish an activity (idempotent per kind — the QML model keys on
    /// kind for the stack).
    pub fn publish(&mut self, kind: Kind) {
        if !self.stack.contains(&kind) {
            self.stack.push(kind);
        }
    }

    /// Retire an activity — the island morphs back to idle / the next in
    /// the stack.
    pub fn end(&mut self, kind: Kind) {
        self.stack.retain(|k| *k != kind);
    }

    pub fn stack(&self) -> &[Kind] {
        &self.stack
    }

    /// The target geometry for the CURRENT stack.
    pub fn geometry(&self) -> Geometry {
        resolve(&self.stack)
    }

    pub fn width_spring(&mut self) -> &mut Spring {
        self.width_spring.as_mut().unwrap()
    }

    pub fn height_spring(&mut self) -> &mut Spring {
        self.height_spring.as_mut().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn radius_caps_at_32() {
        assert_eq!(island_radius(96), 32);
        assert_eq!(island_radius(64), 32);
        assert_eq!(island_radius(32), 16);
        assert_eq!(island_radius(56), 28);
    }

    #[test]
    fn idle_geometry() {
        let g = resolve(&[]);
        assert_eq!(g, Geometry { w: 104, h: 32, r: 16 });
    }

    #[test]
    fn now_playing_is_the_expanded_card() {
        let g = state_geometry(Kind::Media);
        assert_eq!(g, Geometry { w: 356, h: 96, r: 32 });
    }

    #[test]
    fn split_sums_the_top_two_lobes() {
        // call (150) > charging (108): 150 + 8 + 108
        let g = resolve(&[Kind::Charging, Kind::Call, Kind::Generic]);
        assert_eq!(g.w, 150 + 8 + 108);
        assert_eq!(g.h, IDLE_HEIGHT);
        // media (132) + timer (108): 132 + 8 + 108
        let g2 = resolve(&[Kind::Timer, Kind::Media]);
        assert_eq!(g2.w, 132 + 8 + 108);
    }

    #[test]
    fn priority_order_matches_table_5b() {
        let mut ks = vec![Kind::Generic, Kind::Media, Kind::Charging,
                          Kind::Timer, Kind::AegisId, Kind::Call];
        ks.sort_by(|a, b| b.rank().cmp(&a.rank()));
        assert_eq!(ks, vec![Kind::Call, Kind::AegisId, Kind::Timer,
                            Kind::Media, Kind::Charging, Kind::Generic]);
    }

    #[test]
    fn spring_converges_without_teleport() {
        let mut s = Spring::new(104.0);
        s.set_target(356.0);
        let mut max_step = 0.0f64;
        for _ in 0..600 {
            let before = s.value;
            s.step(1.0 / 60.0);
            max_step = max_step.max((s.value - before).abs());
        }
        assert!((s.value - 356.0).abs() < 1.0, "did not converge: {}", s.value);
        assert!(max_step < 60.0, "teleported: step {max_step}");
    }

    #[test]
    fn spring_is_underdamped_like_the_qml() {
        // ζ = c / (2·√(k·m)) = 28 / (2·√420) ≈ 0.683 — underdamped, the
        // small overshoot the island's morphs are known for.
        let zeta = 28.0 / (2.0 * (420.0_f64).sqrt());
        assert!((zeta - 0.683).abs() < 0.01, "{zeta}");
    }

    #[test]
    fn island_morphs_idle_to_media_and_back() {
        let mut isl = Island::new();
        // The renderer contract: targets track the resolved geometry every
        // frame, the springs do the moving.
        let chase = |isl: &mut Island| {
            let g = isl.geometry();
            isl.width_spring().set_target(g.w as f64);
            isl.height_spring().set_target(g.h as f64);
        };
        isl.publish(Kind::Media);
        chase(&mut isl);
        assert_eq!(isl.geometry().w, 356);
        let mut frames = 0;
        while !(isl.width_spring().settled() && isl.height_spring().settled())
            && frames < 600
        {
            isl.width_spring().step(1.0 / 60.0);
            isl.height_spring().step(1.0 / 60.0);
            frames += 1;
        }
        assert!((isl.width_spring().value - 356.0).abs() < 0.5);
        assert!((isl.height_spring().value - 96.0).abs() < 0.5);
        isl.end(Kind::Media);
        chase(&mut isl);
        while !(isl.width_spring().settled() && isl.height_spring().settled())
            && frames < 1200
        {
            isl.width_spring().step(1.0 / 60.0);
            isl.height_spring().step(1.0 / 60.0);
            frames += 1;
        }
        assert!((isl.width_spring().value - 104.0).abs() < 0.5);
    }

    #[test]
    fn snap_reaches_every_shape() {
        let mut s = Spring::new(104.0);
        s.set_target(356.0);
        s.snap();
        assert_eq!(s.value, 356.0);
        assert!(s.settled());
    }

    #[test]
    fn publish_is_idempotent_and_end_retires() {
        let mut isl = Island::new();
        isl.publish(Kind::Timer);
        isl.publish(Kind::Timer);
        assert_eq!(isl.stack().len(), 1);
        isl.publish(Kind::Call);
        isl.end(Kind::Timer);
        assert_eq!(isl.stack(), &[Kind::Call]);
    }
}
