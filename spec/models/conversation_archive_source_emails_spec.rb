require 'rails_helper'

RSpec.describe Conversation, '#archive_source_emails' do
  let(:account) { create(:account) }

  def email_inbox(archive:)
    create(:channel_email, :imap_email, account: account, archive_email_on_conversation_delete: archive).inbox
  end

  it 'enqueues the archive job with incoming source ids when the toggle is on' do
    inbox = email_inbox(archive: true)
    conversation = create(:conversation, inbox: inbox, account: account)
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, source_id: '<a@example.com>')
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :outgoing, source_id: '<reply@example.com>')

    expect { conversation.destroy! }
      .to have_enqueued_job(Inboxes::ArchiveEmailsOnDeleteJob)
      .with(inbox.channel, ['<a@example.com>'])
  end

  it 'does not enqueue when the toggle is off' do
    inbox = email_inbox(archive: false)
    conversation = create(:conversation, inbox: inbox, account: account)
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, source_id: '<a@example.com>')

    expect { conversation.destroy! }.not_to have_enqueued_job(Inboxes::ArchiveEmailsOnDeleteJob)
  end

  it 'does not enqueue when there are no incoming source ids' do
    inbox = email_inbox(archive: true)
    conversation = create(:conversation, inbox: inbox, account: account)
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :outgoing, source_id: '<reply@example.com>')

    expect { conversation.destroy! }.not_to have_enqueued_job(Inboxes::ArchiveEmailsOnDeleteJob)
  end

  it 'does not enqueue for non-email inboxes' do
    inbox = create(:inbox, account: account)
    conversation = create(:conversation, inbox: inbox, account: account)
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, source_id: '<a@example.com>')

    expect { conversation.destroy! }.not_to have_enqueued_job(Inboxes::ArchiveEmailsOnDeleteJob)
  end
end
