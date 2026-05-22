require 'net/imap'

# Removes the given messages from the mailbox INBOX so Chatwoot does not re-import
# them on the next sync after a conversation is deleted.
#
# On Gmail, expunging a message from INBOX removes the INBOX label, which archives
# the message (it remains in All Mail) rather than permanently deleting it. Since
# Chatwoot only ever polls INBOX, this is sufficient to stop re-import.
class Imap::ArchiveEmailService
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

    imap_client.uid_store(uids, '+FLAGS', [:Deleted])
    imap_client.expunge
    Rails.logger.info "[IMAP::ARCHIVE_EMAIL_SERVICE] Archived #{channel.email} message-id <#{message_id}>."
    message_id
  rescue StandardError => e
    Rails.logger.error "[IMAP::ARCHIVE_EMAIL_SERVICE] Failed to archive #{channel.email} message-id <#{message_id}>: #{e.message}"
    nil
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
