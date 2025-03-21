# qBittorrent Notes

- `DAC_OVERRIDE` capability is required when adding a torrent from the command
line with `qbittorrent-nox --add-paused=true`, otherwise you get
`QtLockedFile::lock(): file is not opened` error.
- When using `runsc` need to set the Network Interface, eg Options > Advanced >
Network Interface: wg0 (or tun0 with OpenVPN). Each restart this will need to
be flicked to one of the other options and back to your interface of choice.
