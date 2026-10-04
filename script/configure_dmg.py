"""Write the installer layout directly; no Finder automation or GUI permissions needed."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "vendor"))
from ds_store import DSStore
from mac_alias import Alias

# statfs returns /private/var on macOS; canonicalize /var before building volume-relative aliases.
root = pathlib.Path(sys.argv[1]).resolve()
app_name = sys.argv[2]
background = root / ".background" / "DMGBackground.tiff"
background_alias = Alias.for_file(str(background))
assert background_alias.target.posix_path == b"/.background/DMGBackground.tiff"
with DSStore.open(str(root / ".DS_Store"), "w+") as store:
    store["."]["vSrn"] = ("long", 1)
    store["."]["icvl"] = ("type", b"icnv")
    store["."]["bwsp"] = {
        # Leave room for Finder's path/status bars if the user's preferences show them.
        "WindowBounds": "{{240, 160}, {660, 480}}",
        "ShowStatusBar": False, "ShowToolbar": False, "ShowSidebar": False,
        "ShowPathbar": False, "ShowTabView": False, "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False, "SidebarWidth": 0,
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1, "backgroundType": 2,
        "backgroundImageAlias": background_alias.to_bytes(),
        "backgroundColorRed": 0.97, "backgroundColorGreen": 0.97, "backgroundColorBlue": 1.0,
        "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0,
        "arrangeBy": "none", "showIconPreview": True, "showItemInfo": False,
        "labelOnBottom": True, "textSize": 13.0, "iconSize": 96.0,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
    }
    store[app_name + ".app"]["Iloc"] = (180, 220)
    store["Applications"]["Iloc"] = (480, 220)

# Read back the saved layout before the writable disk image is detached.
with DSStore.open(str(root / ".DS_Store"), "r") as store:
    assert store[app_name + ".app"]["Iloc"] == (180, 220)
    assert store["Applications"]["Iloc"] == (480, 220)
    assert store["."]["icvp"]["backgroundType"] == 2
print("Installer layout saved: 660 x 480, app left, Applications right.")
