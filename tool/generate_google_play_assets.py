from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "store" / "google-play" / "assets" / "en-US"
PHONE = OUT / "phone-screenshots"
LOGO = ROOT / "assets" / "branding" / "logo_webtui.png"
FONT_DIR = ROOT / "assets" / "fonts"


BLUE = (8, 119, 242)
BLUE_DARK = (5, 97, 199)
CYAN = (19, 168, 247)
INK = (23, 32, 51)
MUTED = (83, 96, 116)
PANEL = (255, 255, 255)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_DIR / name), size=size)


def paste_rounded(base: Image.Image, image: Image.Image, box: tuple[int, int], radius: int) -> None:
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    base.paste(image, box, mask)


def draw_shadowed_card(
    base: Image.Image,
    image: Image.Image,
    box: tuple[int, int],
    radius: int,
    shadow_alpha: int = 46,
) -> None:
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow_mask = Image.new("L", image.size, 0)
    shadow_draw = ImageDraw.Draw(shadow_mask)
    shadow_draw.rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=shadow_alpha)
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(12)))
    base.paste(shadow, (box[0] + 8, box[1] + 10), shadow)
    paste_rounded(base, image, box, radius)


def resize_cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_w, target_h = size
    source_w, source_h = image.size
    scale = max(target_w / source_w, target_h / source_h)
    resized = image.resize((round(source_w * scale), round(source_h * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - target_w) // 2
    top = (resized.height - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h))


def make_icon() -> None:
    logo = Image.open(LOGO).convert("RGBA")
    icon = logo.resize((512, 512), Image.Resampling.LANCZOS)
    icon.save(OUT / "icon-512.png", optimize=True)


def make_feature_graphic() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    base = Image.new("RGB", (1024, 500), (246, 250, 255))
    draw = ImageDraw.Draw(base)

    for y in range(base.height):
        t = y / max(1, base.height - 1)
        color = tuple(round(BLUE[i] * (1 - t) + CYAN[i] * t) for i in range(3))
        draw.line((0, y, 1024, y), fill=color)

    draw.rounded_rectangle((40, 44, 496, 456), radius=30, fill=(255, 255, 255, 232))

    logo = Image.open(LOGO).convert("RGBA").resize((104, 104), Image.Resampling.LANCZOS)
    base.paste(logo, (72, 82), logo)

    draw.text((72, 220), "WebTUI Chat", fill=INK, font=font("roboto-bold.ttf", 54))
    draw.text(
        (72, 292),
        "Workspace chat, calls and files",
        fill=MUTED,
        font=font("roboto-medium.ttf", 30),
    )
    draw.rounded_rectangle((72, 364, 306, 416), radius=16, fill=(232, 242, 255))
    draw.text((96, 376), "Self-host ready", fill=BLUE_DARK, font=font("roboto-bold.ttf", 24))

    shots = [
        PHONE / "01-conversations.png",
        PHONE / "02-chat-calls-files.png",
    ]
    positions = [(560, 36), (736, 72)]
    for path, pos in zip(shots, positions):
        shot = Image.open(path).convert("RGB")
        card = resize_cover(shot, (210, 374))
        draw_shadowed_card(base, card, pos, 24)

    base.save(OUT / "feature-graphic-1024x500.png", optimize=True)


def normalize_phone_screenshots() -> None:
    for path in sorted(PHONE.glob("*.png")):
        image = Image.open(path)
        if image.size != (1080, 1920):
            raise SystemExit(f"{path} has invalid size {image.size}, expected 1080x1920")
        if image.mode != "RGB":
            background = Image.new("RGB", image.size, PANEL)
            if image.mode == "RGBA":
                background.paste(image, mask=image.getchannel("A"))
            else:
                background.paste(image.convert("RGB"))
            image = background
        image.save(path, optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    make_icon()
    normalize_phone_screenshots()
    make_feature_graphic()


if __name__ == "__main__":
    main()
