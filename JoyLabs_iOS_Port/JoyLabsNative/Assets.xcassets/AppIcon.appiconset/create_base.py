from PIL import Image, ImageDraw, ImageFont
import os

# Create a 1024x1024 base icon with JoyLabs branding
def create_base_icon():
    size = 1024
    img = Image.new('RGB', (size, size), color='#007AFF')  # iOS blue
    draw = ImageDraw.Draw(img)
    
    # Add a simple "J" in the center
    try:
        # Try to use a system font
        font = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 400)
    except:
        # Fallback to default font
        font = ImageFont.load_default()
    
    # Draw white "J" in center
    text = "J"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (size - text_width) // 2
    y = (size - text_height) // 2
    draw.text((x, y), text, fill='white', font=font)
    
    img.save('icon-1024.png', 'PNG')
    return img

# Create base icon
base_img = create_base_icon()

# Create all other sizes by resizing the base
sizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180]
for size in sizes:
    resized = base_img.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(f'icon-{size}.png', 'PNG')
    print(f'Created icon-{size}.png ({size}x{size})')

print('All icon files created successfully!')
