"""dmgbuild settings for Nova's installer window.

Positions match the artwork drawn by Scripts/render-dmg-background.swift, which measures icon
centres from the top of the window exactly as Finder does.
"""
import os

app = defines.get("app", "build/Release/Nova.app")  # noqa: F821 - dmgbuild injects `defines`
app_name = os.path.basename(app)

# Contents
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("volume_icon")  # noqa: F821
hide_extension = [app_name]

# Image
format = "UDZO"
size = None

# Window
background = defines.get("background")  # noqa: F821
window_rect = ((240, 180), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
label_pos = "bottom"
text_size = 12
icon_size = 128
icon_locations = {
    app_name: (168, 214),
    "Applications": (492, 214),
}
