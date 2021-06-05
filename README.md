# VLC-DL, vlc with a pinch of youtube-dl
## Installation
Place `youtube-dl.lua` in one of the following directories to enable it:
Windows: `C:\Program Files\VideoLAN\VLC\lua\playlist/`
Mac: `VLC.app/Contents/MacOS/share/lua/playlist/`
Linux: `/usr/share/vlc/lua/playlist/`

Place `vlc-dl.lua` in one of the following directories to enable it:
Windows: `C:\Program Files\VideoLAN\VLC\lua\sd/`
Mac: `VLC.app/Contents/MacOS/share/lua/sd/`
Linux: `/usr/share/vlc/lua/sd/`

For either of these to work you must install [`youtube-dl`](https://github.com/ytdl-org/youtube-dl#installation) first.

## Usage
### `youtube-dl.lua` 
This extension should have little to no effect on your viewing experience. Just put a link from any of the [sites youtube-dl supports](http://ytdl-org.github.io/youtube-dl/supportedsites.html) into your playlist and it should work just fine!

### `vlc-dl.lua`
Work in progress, not suggested to be used in it's current state. There is a small amount of documentation in the source, if you want to try it out.