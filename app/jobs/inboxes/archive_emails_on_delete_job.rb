class Inboxes::ArchiveEmailsOnDeleteJob < ApplicationJob
  queue_as :low

  def perform(channel, message_ids)
    return if channel.blank? || message_ids.blank?

    Imap::ArchiveEmailService.new(channel: channel, message_ids: message_ids).perform
  end
end
