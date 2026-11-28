//! aegis-compositor — the AEGIS Wayland compositor, in Rust.
//!
//! The foundation of the new system (W102): window management, output
//! composition and the Wayland server for the whole desktop, one process —
//! the role cutefish-compositor plays in its C++ stack.
//!
//! Adapted from Smithay's `minimal` example (MIT, © Smithay contributors),
//! the smallest complete compositor upstream ships, so the first build is
//! KNOWN-COMPILING; the AEGIS layer grows from here:
//!
//! - round 3: zwlr_layer_shell_v1 — the island and the shell dock as
//!   layer surfaces (island-core drives the geometry springs),
//! - round 4: the DRM/udev backend replaces the nested winit window for
//!   real hardware sessions + libinput seats,
//! - round 5: window decorations, the app switcher, workspace logic
//!   (the cutefish `shell/`, `decoration/`, `switcher/` modules mapped),
//! - round 6: the effects stack (blur — the QML shell's eternal battle —
//!   becomes a render-element pass here).

use std::sync::Arc;

use ::winit::event_loop::pump_events::PumpStatus;
use smithay::{
    backend::{
        input::{InputEvent, InputTime, KeyboardKeyEvent},
        renderer::{
            Color32F, Frame, Renderer,
            element::{
                Kind,
                surface::{WaylandSurfaceRenderElement, render_elements_from_surface_tree},
            },
            gles::GlesRenderer,
            utils::{draw_render_elements, on_commit_buffer_handler},
        },
        winit::{self, WinitEvent},
    },
    input::{Seat, SeatHandler, SeatState, keyboard::FilterResult},
    reexports::wayland_server::{Display, protocol::wl_seat},
    utils::{Rectangle, Serial, Transform},
    wayland::{
        buffer::BufferHandler,
        compositor::{
            CompositorClientState, CompositorHandler, CompositorState, SurfaceAttributes, TraversalAction,
            with_surface_tree_downward,
        },
        pointer_constraints::PointerConstraintsHandler,
        selection::{
            SelectionHandler,
            data_device::{DataDeviceHandler, DataDeviceState, WaylandDndGrabHandler},
        },
        shell::xdg::{PopupSurface, PositionerState, ToplevelSurface, XdgShellHandler, XdgShellState},
        shm::{ShmHandler, ShmState},
    },
};
use wayland_protocols::xdg::shell::server::xdg_toplevel;
use wayland_server::{
    Client, ListeningSocket,
    backend::{ClientData, ClientId, DisconnectReason},
    protocol::{
        wl_buffer,
        wl_surface::{self, WlSurface},
    },
};

/// The AEGIS abyss — the wallpaper base tone the whole shell floats on
/// (`docs/DESIGN-TOKENS.md` §1: #0B1020).
pub const ABYSS: (f32, f32, f32, f32) = (0.043, 0.063, 0.125, 1.0);

/// The socket name clients connect to (`WAYLAND_DISPLAY=wayland-aegis`).
pub const WAYLAND_DISPLAY: &str = "wayland-aegis";

/// The shell process the compositor launches on startup; it speaks
/// layer-shell and owns the island + dock. Round 3.
pub const SHELL_PROCESS: &str = "aegis-shell";

/// The seed of window management: vertical stack layout. Pure math, so it
/// is testable without a display — the interactive wiring (focus, drag,
/// resize) lands with the input round.
pub fn stack_layout(
    output: Rectangle<i32, smithay::utils::Logical>,
    windows: usize,
) -> Vec<Rectangle<i32, smithay::utils::Logical>> {
    if windows == 0 {
        return Vec::new();
    }
    let h = output.size.h / windows as i32;
    (0..windows as i32)
        .map(|i| {
            let mut r = Rectangle::new((output.loc.x, output.loc.y + i * h).into(), output.size);
            r.size.h = h;
            r
        })
        .collect()
}

impl BufferHandler for AegisState {
    fn buffer_destroyed(&mut self, _buffer: &wl_buffer::WlBuffer) {}
}

impl XdgShellHandler for AegisState {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        &mut self.xdg_shell_state
    }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        surface.with_pending_state(|state| {
            state.states.set(xdg_toplevel::State::Activated);
        });
        surface.send_configure();
    }

    fn new_popup(&mut self, _surface: PopupSurface, _positioner: PositionerState) {
        // Popup positioning lands with the launcher round.
    }

    fn grab(&mut self, _surface: PopupSurface, _seat: wl_seat::WlSeat, _serial: Serial) {
        // Popup grabs land with the launcher round.
    }

    fn reposition_request(&mut self, _surface: PopupSurface, _positioner: PositionerState, _token: u32) {
        // Popup repositioning lands with the launcher round.
    }
}

impl SelectionHandler for AegisState {
    type SelectionUserData = ();
}

impl DataDeviceHandler for AegisState {
    fn data_device_state(&mut self) -> &mut DataDeviceState {
        &mut self.data_device_state
    }
}

impl WaylandDndGrabHandler for AegisState {}

impl CompositorHandler for AegisState {
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(&self, client: &'a Client) -> &'a CompositorClientState {
        &client.get_data::<ClientState>().unwrap().compositor_state
    }

    fn commit(&mut self, surface: &WlSurface) {
        on_commit_buffer_handler::<Self>(surface);
    }
}

impl ShmHandler for AegisState {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}

impl SeatHandler for AegisState {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Self> {
        &mut self.seat_state
    }

    fn focus_changed(&mut self, _seat: &Seat<Self>, _focused: Option<&WlSurface>) {}
    fn cursor_image(&mut self, _seat: &Seat<Self>, _image: smithay::input::pointer::CursorImageStatus) {}
}

impl PointerConstraintsHandler for AegisState {}

struct AegisState {
    compositor_state: CompositorState,
    xdg_shell_state: XdgShellState,
    shm_state: ShmState,
    seat_state: SeatState<Self>,
    data_device_state: DataDeviceState,

    seat: Seat<Self>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    if let Ok(env_filter) = tracing_subscriber::EnvFilter::try_from_default_env() {
        tracing_subscriber::fmt().with_env_filter(env_filter).init();
    } else {
        tracing_subscriber::fmt().init();
    }

    run_winit()
}

pub fn run_winit() -> Result<(), Box<dyn std::error::Error>> {
    let mut display: Display<AegisState> = Display::new()?;
    let dh = display.handle();

    let compositor_state = CompositorState::new::<AegisState>(&dh);
    let shm_state = ShmState::new::<AegisState>(&dh, vec![]);
    let mut seat_state = SeatState::new();
    let seat = seat_state.new_wl_seat(&dh, "winit");

    let mut state = {
        AegisState {
            compositor_state,
            xdg_shell_state: XdgShellState::new::<AegisState>(&dh),
            shm_state,
            seat_state,
            data_device_state: DataDeviceState::new::<AegisState>(&dh),
            seat,
        }
    };

    let listener = ListeningSocket::bind(WAYLAND_DISPLAY).unwrap();
    let mut clients = Vec::new();

    let (mut backend, mut winit) = winit::init::<GlesRenderer>()?;

    let start_time = std::time::Instant::now();

    let keyboard = state.seat.add_keyboard(Default::default(), 200, 200).unwrap();

    unsafe { std::env::set_var("WAYLAND_DISPLAY", WAYLAND_DISPLAY) };
    // The shell process (island + dock, layer-shell clients). Until round
    // 3 it does not exist yet — degrade quietly like upstream does.
    std::process::Command::new(SHELL_PROCESS).spawn().ok();

    loop {
        let status = winit.dispatch_new_events(|event| match event {
            WinitEvent::Resized { .. } => {}
            WinitEvent::Input(event) => match event {
                InputEvent::Keyboard { event } => {
                    keyboard.input::<(), _>(
                        &mut state,
                        event.key_code(),
                        event.state(),
                        0.into(),
                        InputTime::now(),
                        |_, _, _| {
                            //
                            FilterResult::Forward
                        },
                    );
                }
                InputEvent::PointerMotionAbsolute { .. } => {
                    if let Some(surface) = state.xdg_shell_state.toplevel_surfaces().first().cloned() {
                        let surface = surface.wl_surface().clone();
                        keyboard.set_focus(&mut state, Some(surface), 0.into());
                    };
                }
                _ => {}
            },
            _ => (),
        });

        match status {
            PumpStatus::Continue => (),
            PumpStatus::Exit(_) => return Ok(()),
        };

        let size = backend.window_size();
        let damage = Rectangle::from_size(size);
        {
            let (renderer, mut framebuffer) = backend.bind().unwrap();
            let elements = state
                .xdg_shell_state
                .toplevel_surfaces()
                .iter()
                .flat_map(|surface| {
                    render_elements_from_surface_tree(
                        renderer,
                        surface.wl_surface(),
                        (0, 0),
                        1.0,
                        1.0,
                        Kind::Unspecified,
                    )
                })
                .collect::<Vec<WaylandSurfaceRenderElement<GlesRenderer>>>();

            let mut frame = renderer
                .render(&mut framebuffer, size, Transform::Flipped180)
                .unwrap();
            frame.clear(Color32F::new(ABYSS.0, ABYSS.1, ABYSS.2, ABYSS.3), &[damage]).unwrap();
            draw_render_elements(&mut frame, 1.0, &elements, &[damage]).unwrap();
            // We rely on the nested compositor to do the sync for us
            let _ = frame.finish().unwrap();

            for surface in state.xdg_shell_state.toplevel_surfaces() {
                send_frames_surface_tree(surface.wl_surface(), start_time.elapsed().as_millis() as u32);
            }

            if let Some(stream) = listener.accept()? {
                tracing::info!("Got a client: {:?}", stream);

                let client = display
                    .handle()
                    .insert_client(stream, Arc::new(ClientState::default()))
                    .unwrap();
                clients.push(client);
            }

            display.dispatch_clients(&mut state)?;
            display.flush_clients()?;
        }

        // It is important that all events on the display have been dispatched and flushed to clients before
        // swapping buffers because this operation may block.
        backend.submit(Some(&[damage])).unwrap();
    }
}

pub fn send_frames_surface_tree(surface: &wl_surface::WlSurface, time: u32) {
    with_surface_tree_downward(
        surface,
        (),
        |_, _, &()| TraversalAction::DoChildren(()),
        |_surf, states, &()| {
            // the surface may not have any user_data if it is a subsurface and has not
            // yet been committed
            for callback in states
                .cached_state
                .get::<SurfaceAttributes>()
                .current()
                .frame_callbacks
                .drain(..)
            {
                callback.done(time);
            }
        },
        |_, _, &()| true,
    );
}

#[derive(Default)]
struct ClientState {
    compositor_state: CompositorClientState,
}
impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {
        tracing::info!("initialized");
    }

    fn disconnected(&self, _client_id: ClientId, _reason: DisconnectReason) {
        tracing::info!("disconnected");
    }
}

smithay::delegate_dispatch2!(AegisState);

#[cfg(test)]
mod tests {
    use super::*;

    fn output(w: i32, h: i32) -> Rectangle<i32, smithay::utils::Logical> {
        Rectangle::new((0, 0).into(), (w, h).into())
    }

    #[test]
    fn stack_tiles_split_height_evenly() {
        let tiles = stack_layout(output(1920, 1080), 3);
        assert_eq!(tiles.len(), 3);
        assert_eq!(tiles[0].size.h, 360);
        assert_eq!(tiles[0].loc, (0, 0).into());
        assert_eq!(tiles[2].loc, (0, 720).into());
        assert_eq!(tiles[2].size.h, 360);
    }

    #[test]
    fn stack_of_none_and_one() {
        assert!(stack_layout(output(1920, 1080), 0).is_empty());
        let one = stack_layout(output(1920, 1080), 1);
        assert_eq!(one.len(), 1);
        assert_eq!(one[0].size.w, 1920);
        assert_eq!(one[0].size.h, 1080);
    }
}
