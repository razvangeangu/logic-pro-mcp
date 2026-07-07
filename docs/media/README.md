# Media Asset Provenance

These binary media files are intentionally tracked release/demo assets, not generated build output.

- `logic-pro-mcp-demo.mp4`: 36-second Logic Pro 12.3 capture with sound — an 82 BPM D-minor lofi loop composed live by the MCP (tempo, three `record_sequence` MIDI parts, a Drummer, piano roll, real-time playback). Assembled in Palmier Pro; audio bed is Logic's own bounce of the loop. Used by the README.
- `logic-pro-mcp-demo.gif`: README-friendly silent derivative (reveal + playback) of the MP4 capture.
- `logic-pro-mcp-thumbnail.png`: static thumbnail derivative for release/social surfaces.

Retention policy:

- Keep these files only while they are referenced by README or release documentation.
- Replace them with new captures rather than editing in place when demo behavior changes materially.
- If the media set grows beyond small README assets, move large files to Git LFS or release attachments.
