package main

import mu "vendor:microui"
import rl "vendor:raylib"
import "core:c"
import "core:fmt"
import "core:unicode/utf8"
import "core:strings"

GuiState :: struct {
	mu_ctx:         mu.Context,
	hi:             int,
	bg:             mu.Color,
	atlas_texture:  rl.RenderTexture2D,
	screen_width:   c.int,
	screen_height:  c.int,
	screen_texture: rl.RenderTexture2D,
}

mouse_buttons_map := [mu.Mouse]rl.MouseButton {
	.LEFT   = .LEFT,
	.RIGHT  = .RIGHT,
	.MIDDLE = .MIDDLE,
}

key_map := [mu.Key][2]rl.KeyboardKey {
	.SHIFT     = {.LEFT_SHIFT, .RIGHT_SHIFT},
	.CTRL      = {.LEFT_CONTROL, .RIGHT_CONTROL},
	.ALT       = {.LEFT_ALT, .RIGHT_ALT},
	.BACKSPACE = {.BACKSPACE, .KEY_NULL},
	.DELETE    = {.DELETE, .KEY_NULL},
	.RETURN    = {.ENTER, .KP_ENTER},
	.LEFT      = {.LEFT, .KEY_NULL},
	.RIGHT     = {.RIGHT, .KEY_NULL},
	.HOME      = {.HOME, .KEY_NULL},
	.END       = {.END, .KEY_NULL},
	.A         = {.A, .KEY_NULL},
	.X         = {.X, .KEY_NULL},
	.C         = {.C, .KEY_NULL},
	.V         = {.V, .KEY_NULL},
}

guistate: GuiState

mu_init :: proc() {
	guistate = {
		screen_width  = screen_width,
		screen_height = screen_height,
	}
	ctx := &guistate.mu_ctx
	mu.init(ctx, set_clipboard = proc(user_data: rawptr, text: string) -> (ok: bool) {
			cstr := strings.clone_to_cstring(text)
			rl.SetClipboardText(cstr)
			delete(cstr)
			return true
		}, get_clipboard = proc(user_data: rawptr) -> (text: string, ok: bool) {
			cstr := rl.GetClipboardText()
			if cstr != nil {
				text = string(cstr)
				ok = true
			}
			return
		})

	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

	guistate.atlas_texture = rl.LoadRenderTexture(c.int(mu.DEFAULT_ATLAS_WIDTH), c.int(mu.DEFAULT_ATLAS_HEIGHT))

	image := rl.GenImageColor(c.int(mu.DEFAULT_ATLAS_WIDTH), c.int(mu.DEFAULT_ATLAS_HEIGHT), rl.Color{0, 0, 0, 0})

	for alpha, i in mu.default_atlas_alpha {
		x := i % mu.DEFAULT_ATLAS_WIDTH
		y := i / mu.DEFAULT_ATLAS_WIDTH
		color := rl.Color{255, 255, 255, alpha}
		rl.ImageDrawPixel(&image, c.int(x), c.int(y), color)
	}

	rl.BeginTextureMode(guistate.atlas_texture)
	rl.UpdateTexture(guistate.atlas_texture.texture, rl.LoadImageColors(image))
	rl.EndTextureMode()

	guistate.screen_texture = rl.LoadRenderTexture(guistate.screen_width, guistate.screen_height)
}

mu_instrument :: proc() {
	ctx := &guistate.mu_ctx
	mouse_pos := rl.GetMousePosition()
	mouse_x, mouse_y := i32(mouse_pos.x), i32(mouse_pos.y)
	mu.input_mouse_move(ctx, mouse_x, mouse_y)

	mouse_wheel_pos := rl.GetMouseWheelMoveV()
	mu.input_scroll(ctx, i32(mouse_wheel_pos.x) * 30, i32(mouse_wheel_pos.y) * -30)

	for button_rl, button_mu in mouse_buttons_map {
		switch {
		case rl.IsMouseButtonPressed(button_rl):
			mu.input_mouse_down(ctx, mouse_x, mouse_y, button_mu)
		case rl.IsMouseButtonReleased(button_rl):
			mu.input_mouse_up(ctx, mouse_x, mouse_y, button_mu)
		}
	}

	for keys_rl, key_mu in key_map {
		for key_rl in keys_rl {
			switch {
			case key_rl == .KEY_NULL:
			// ignore
			case rl.IsKeyPressed(key_rl), rl.IsKeyPressedRepeat(key_rl):
				mu.input_key_down(ctx, key_mu)
			case rl.IsKeyReleased(key_rl):
				mu.input_key_up(ctx, key_mu)
			}
		}
	}

	{
		buf: [512]byte
		n: int
		for n < len(buf) {
			c := rl.GetCharPressed()
			if c == 0 {
				break
			}
			b, w := utf8.encode_rune(c)
			n += copy(buf[n:], b[:w])
		}
		mu.input_text(ctx, string(buf[:n]))
	}
}

mu_draw :: proc() {
	ctx := &guistate.mu_ctx

	mu.begin(ctx)

	if mu.begin_window(ctx, "my window", {10, 10, 200, 200}) {
		// mu.layout_row(ctx, {100, 100}, 0)
		mu.label(ctx, "First")
		if .SUBMIT in mu.button(ctx, "press me") {
			fmt.println("pressed")
		}
		mu.end_window(ctx)
	}

	mu.end(ctx)
}

mu_render :: proc "contextless" (ctx: ^mu.Context) {
	render_texture :: proc "contextless" (
		renderer: rl.RenderTexture2D,
		dst: ^rl.Rectangle,
		src: mu.Rect,
		color: rl.Color,
	) {
		dst.width = f32(src.w)
		dst.height = f32(src.h)

		rl.DrawTextureRec(
			texture = guistate.atlas_texture.texture,
			source = {f32(src.x), f32(src.y), f32(src.w), f32(src.h)},
			position = {dst.x, dst.y},
			tint = color,
		)
	}

	to_rl_color :: proc "contextless" (in_color: mu.Color) -> (out_color: rl.Color) {
		return {in_color.r, in_color.g, in_color.b, in_color.a}
	}

	height := rl.GetScreenHeight()

	rl.BeginTextureMode(guistate.screen_texture)
	rl.EndScissorMode()
	rl.ClearBackground(to_rl_color(guistate.bg))

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			dst := rl.Rectangle{f32(cmd.pos.x), f32(cmd.pos.y), 0, 0}
			for ch in cmd.str {
				if ch & 0xc0 != 0x80 {
					r := min(int(ch), 127)
					src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
					render_texture(guistate.screen_texture, &dst, src, to_rl_color(cmd.color))
					dst.x += dst.width
				}
			}
		case ^mu.Command_Rect:
			rl.DrawRectangle(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, to_rl_color(cmd.color))
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w) / 2
			y := cmd.rect.y + (cmd.rect.h - src.h) / 2
			render_texture(guistate.screen_texture, &rl.Rectangle{f32(x), f32(y), 0, 0}, src, to_rl_color(cmd.color))
		case ^mu.Command_Clip:
			rl.BeginScissorMode(cmd.rect.x, height - (cmd.rect.y + cmd.rect.h), cmd.rect.w, cmd.rect.h)
		case ^mu.Command_Jump:
			unreachable()
		}
	}
	rl.EndTextureMode()
	rl.DrawTextureRec(
		texture = guistate.screen_texture.texture,
		source = {0, 0, f32(guistate.screen_width), -f32(guistate.screen_height)},
		position = {0, 0},
		tint = rl.WHITE,
	)
}
