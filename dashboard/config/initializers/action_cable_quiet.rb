# Silence ActionCable's per-broadcast/per-transmit logging.
#
# Each PTY frame from a terminal session would otherwise produce two log lines
# ("Broadcasting to ..." + "TerminalChannel transmitting ..."), which at ~50fps
# during a Claude streaming session means hundreds of disk writes per second
# on development.log. That synchronous I/O ends up starving the channel
# threads and the browser feels frozen. We don't need that noise in dev.
Rails.application.config.to_prepare do
  ActionCable.server.config.logger = Logger.new(nil)
end
