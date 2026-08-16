require 'net/imap'

# Removes the given messages from the mailbox INBOX so Chatwoot does not re-import
# them on the next sync after a conversation is deleted.
#
# For Google OAuth inboxes we use IMAP MOVE to `[Gmail]/All Mail`. This is the
# canonical Gmail archive operation: it removes the `\Inbox` label atomically and
# is not affected by the per-account "When a message is marked as deleted" /
# Auto-Expunge IMAP settings that make `+FLAGS \Deleted` + `EXPUNGE` a silent
# no-op on many Gmail accounts.
#
# For plain IMAP servers we mark the message `\Deleted` and EXPUNGE, which is the
# IMAP RFC behavior for removing a message from the current folder.
class Imap::ArchiveEmailService
  GMAIL_ALL_MAIL_MAILBOX = '[Gmail]/All Mail'.freeze

  pattr_initialize [:channel!, :message_ids!]

  def perform
    return [] if message_ids.blank?

    archived = archive_messages
    terminate_imap_connection
    archived
  rescue StandardError => e
    Rails.logger.error "[IMAP::ARCHIVE_EMAIL_SERVICE] Connection error for #{channel.email}: #{e.message}"
    []
  end

  private

  def archive_messages
    message_ids.filter_map { |message_id| archive_message(message_id) }
  end

  def archive_message(message_id)
    return if message_id.blank?

    uids = imap_client.uid_search(['HEADER', 'Message-ID', message_id])
    if uids.blank?
      Rails.logger.info "[IMAP::ARCHIVE_EMAIL_SERVICE] No message in INBOX for #{channel.email} with message-id <#{message_id}>."
      return
    end

    remove_from_inbox(uids)
    Rails.logger.info "[IMAP::ARCHIVE_EMAIL_SERVICE] Archived #{channel.email} message-id <#{message_id}>."
    message_id
  rescue StandardError => e
    Rails.logger.error "[IMAP::ARCHIVE_EMAIL_SERVICE] Failed to archive #{channel.email} message-id <#{message_id}>: #{e.message}"
    nil
  end

  def remove_from_inbox(uids)
    if channel.google?
      imap_client.uid_move(uids, GMAIL_ALL_MAIL_MAILBOX)
    else
      imap_client.uid_store(uids, '+FLAGS', [:Deleted])
      imap_client.expunge
    end
  end

  def imap_client
    @imap_client ||= build_imap_client
  end

  def build_imap_client
    imap = Net::IMAP.new(channel.imap_address, port: channel.imap_port, ssl: channel.imap_enable_ssl)
    Imap::Authentication.authenticate!(imap, authentication_type, channel.imap_login, imap_password)
    imap.select('INBOX')
    imap
  end

  def authentication_type
    return 'XOAUTH2' if channel.microsoft? || channel.google?

    channel.imap_authentication || 'plain'
  end

  def imap_password
    return Microsoft::RefreshOauthTokenService.new(channel: channel).access_token if channel.microsoft?
    return Google::RefreshOauthTokenService.new(channel: channel).access_token if channel.google?

    channel.imap_password
  end

  def terminate_imap_connection
    return if @imap_client.nil?

    imap_client.logout
  rescue Net::IMAP::Error => e
    Rails.logger.info "[IMAP::ARCHIVE_EMAIL_SERVICE] Logout failed for #{channel.email} - #{e.message}."
    imap_client.disconnect
  end
end
